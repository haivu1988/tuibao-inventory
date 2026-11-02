-- Tuibao inventory: additive schema for a new shared application.
-- Run only in the intended Supabase project after reviewing this migration.
create extension if not exists pgcrypto;

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  full_name text not null,
  role text not null check (role in ('manager','staff')),
  branch_id uuid references public.branches(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint staff_requires_branch check (role <> 'staff' or branch_id is not null)
);

create table if not exists public.ingredients (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text not null default 'Khác',
  unit text not null,
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory (
  branch_id uuid not null references public.branches(id) on delete restrict,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  minimum_quantity numeric(14,3) not null default 0 check (minimum_quantity >= 0),
  is_available boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (branch_id, ingredient_id)
);

create table if not exists public.stock_transactions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('in','out','adjust','transfer')),
  branch_id uuid not null references public.branches(id) on delete restrict,
  destination_branch_id uuid references public.branches(id) on delete restrict,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity >= 0),
  before_quantity numeric(14,3) not null,
  after_quantity numeric(14,3) not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  note text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists stock_transactions_created_at_idx on public.stock_transactions (created_at desc);
create index if not exists stock_transactions_branch_idx on public.stock_transactions (branch_id, created_at desc);
create index if not exists inventory_ingredient_idx on public.inventory (ingredient_id);

insert into public.branches (name) values
  ('Tuibao — Chi nhánh TKTQ'),
  ('Tuibao chi nhánh Âu Cơ')
on conflict (name) do nothing;

create or replace function public.current_profile_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where user_id = auth.uid() $$;

create or replace function public.current_profile_branch()
returns uuid language sql stable security definer set search_path = public
as $$ select branch_id from public.profiles where user_id = auth.uid() $$;

revoke all on function public.current_profile_role() from public;
revoke all on function public.current_profile_branch() from public;
grant execute on function public.current_profile_role() to authenticated;
grant execute on function public.current_profile_branch() to authenticated;

alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.ingredients enable row level security;
alter table public.inventory enable row level security;
alter table public.stock_transactions enable row level security;

drop policy if exists branches_read_authenticated on public.branches;
create policy branches_read_authenticated on public.branches for select to authenticated using (true);
drop policy if exists branches_manager_write on public.branches;
create policy branches_manager_write on public.branches for all to authenticated
  using (public.current_profile_role() = 'manager') with check (public.current_profile_role() = 'manager');

drop policy if exists profiles_read_self_or_manager on public.profiles;
create policy profiles_read_self_or_manager on public.profiles for select to authenticated
  using (user_id = auth.uid() or public.current_profile_role() = 'manager');
drop policy if exists profiles_manager_update on public.profiles;
create policy profiles_manager_update on public.profiles for update to authenticated
  using (public.current_profile_role() = 'manager') with check (public.current_profile_role() = 'manager');

drop policy if exists ingredients_read_authenticated on public.ingredients;
create policy ingredients_read_authenticated on public.ingredients for select to authenticated
  using (is_active or public.current_profile_role() = 'manager');
drop policy if exists ingredients_manager_write on public.ingredients;
create policy ingredients_manager_write on public.ingredients for all to authenticated
  using (public.current_profile_role() = 'manager') with check (public.current_profile_role() = 'manager');

drop policy if exists inventory_read_branch_scope on public.inventory;
create policy inventory_read_branch_scope on public.inventory for select to authenticated
  using (public.current_profile_role() = 'manager' or (branch_id = public.current_profile_branch() and is_available));
drop policy if exists inventory_manager_write on public.inventory;
create policy inventory_manager_write on public.inventory for all to authenticated
  using (public.current_profile_role() = 'manager') with check (public.current_profile_role() = 'manager');

drop policy if exists transactions_read_branch_scope on public.stock_transactions;
create policy transactions_read_branch_scope on public.stock_transactions for select to authenticated
  using (public.current_profile_role() = 'manager' or branch_id = public.current_profile_branch());

create or replace function public.apply_stock_operation(
  p_kind text,
  p_branch_id uuid,
  p_ingredient_id uuid,
  p_quantity numeric,
  p_note text default '',
  p_destination_branch_id uuid default null
)
returns public.stock_transactions
language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_branch uuid;
  v_before numeric(14,3);
  v_after numeric(14,3);
  v_dest_before numeric(14,3);
  v_result public.stock_transactions;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role, branch_id into v_role, v_branch from public.profiles where user_id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;
  if p_kind not in ('in','out','adjust','transfer') then raise exception 'Invalid operation'; end if;
  if p_kind in ('adjust','transfer') and v_role <> 'manager' then raise exception 'Manager permission required'; end if;
  if p_kind in ('in','out') and v_role = 'staff' and p_branch_id <> v_branch then raise exception 'Branch permission denied'; end if;
  if p_kind = 'transfer' and p_destination_branch_id is null then raise exception 'Destination branch required'; end if;
  if p_kind = 'transfer' and p_destination_branch_id = p_branch_id then raise exception 'Branches must differ'; end if;
  if p_quantity < 0 or (p_kind <> 'adjust' and p_quantity <= 0) then raise exception 'Invalid quantity'; end if;
  if not exists (select 1 from public.branches where id = p_branch_id and is_active) then raise exception 'Source branch is inactive'; end if;
  if p_kind = 'transfer' and not exists (select 1 from public.branches where id = p_destination_branch_id and is_active) then raise exception 'Destination branch is inactive'; end if;

  select quantity into v_before from public.inventory
    where branch_id = p_branch_id and ingredient_id = p_ingredient_id and is_available for update;
  if not found then raise exception 'Ingredient is not assigned to the source branch'; end if;

  if p_kind = 'adjust' then
    v_after := p_quantity;
  elsif p_kind = 'in' then
    v_after := v_before + p_quantity;
  else
    if v_before < p_quantity then raise exception 'Insufficient stock'; end if;
    v_after := v_before - p_quantity;
  end if;

  update public.inventory set quantity = v_after, updated_at = now()
    where branch_id = p_branch_id and ingredient_id = p_ingredient_id;

  if p_kind = 'transfer' then
    insert into public.inventory (branch_id, ingredient_id, quantity, minimum_quantity, is_available)
      values (p_destination_branch_id, p_ingredient_id, 0, 0, true)
      on conflict (branch_id, ingredient_id) do update set is_available = true;
    select quantity into v_dest_before from public.inventory
      where branch_id = p_destination_branch_id and ingredient_id = p_ingredient_id for update;
    update public.inventory set quantity = v_dest_before + p_quantity, updated_at = now()
      where branch_id = p_destination_branch_id and ingredient_id = p_ingredient_id;
  end if;

  insert into public.stock_transactions (kind, branch_id, destination_branch_id, ingredient_id,
    quantity, before_quantity, after_quantity, actor_id, note)
  values (p_kind, p_branch_id, p_destination_branch_id, p_ingredient_id, p_quantity,
    v_before, v_after, auth.uid(), coalesce(p_note,'')) returning * into v_result;
  return v_result;
end;
$$;
revoke all on function public.apply_stock_operation(text,uuid,uuid,numeric,text,uuid) from public;
grant execute on function public.apply_stock_operation(text,uuid,uuid,numeric,text,uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ingredient-images','ingredient-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
drop policy if exists ingredient_images_read on storage.objects;
create policy ingredient_images_read on storage.objects for select to authenticated using (bucket_id = 'ingredient-images');
drop policy if exists ingredient_images_manager_insert on storage.objects;
create policy ingredient_images_manager_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'ingredient-images' and public.current_profile_role() = 'manager');
drop policy if exists ingredient_images_manager_update on storage.objects;
create policy ingredient_images_manager_update on storage.objects for update to authenticated
  using (bucket_id = 'ingredient-images' and public.current_profile_role() = 'manager')
  with check (bucket_id = 'ingredient-images' and public.current_profile_role() = 'manager');
drop policy if exists ingredient_images_manager_delete on storage.objects;
create policy ingredient_images_manager_delete on storage.objects for delete to authenticated
  using (bucket_id = 'ingredient-images' and public.current_profile_role() = 'manager');

do $$ begin
  alter publication supabase_realtime add table public.inventory;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.stock_transactions;
exception when duplicate_object then null;
end $$;
