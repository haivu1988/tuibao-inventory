-- Adds private avatar storage without changing inventory or auth records.
alter table public.profiles add column if not exists avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('staff-avatars', 'staff-avatars', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists staff_avatars_read on storage.objects;
create policy staff_avatars_read on storage.objects for select to authenticated
  using (bucket_id = 'staff-avatars' and
    (public.current_profile_role() = 'manager' or (storage.foldername(name))[1] = auth.uid()::text));

drop policy if exists staff_avatars_insert on storage.objects;
create policy staff_avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'staff-avatars' and
    (public.current_profile_role() = 'manager' or (storage.foldername(name))[1] = auth.uid()::text));

drop policy if exists staff_avatars_update on storage.objects;
create policy staff_avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'staff-avatars' and
    (public.current_profile_role() = 'manager' or (storage.foldername(name))[1] = auth.uid()::text))
  with check (bucket_id = 'staff-avatars' and
    (public.current_profile_role() = 'manager' or (storage.foldername(name))[1] = auth.uid()::text));

drop policy if exists staff_avatars_delete on storage.objects;
create policy staff_avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'staff-avatars' and
    (public.current_profile_role() = 'manager' or (storage.foldername(name))[1] = auth.uid()::text));

create or replace function public.set_my_avatar_path(p_path text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_path is not null and split_part(p_path, '/', 1) <> auth.uid()::text then
    raise exception 'Avatar path must belong to the signed-in user';
  end if;
  update public.profiles set avatar_path = p_path where user_id = auth.uid();
end;
$$;
revoke all on function public.set_my_avatar_path(text) from public;
grant execute on function public.set_my_avatar_path(text) to authenticated;

