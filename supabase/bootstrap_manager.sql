-- Run this after manually creating the first manager user in Supabase Auth.
-- In Auth, create email quanly01@tuibao.invalid and choose a strong password.
-- This script grants the manager role; it does not contain or set a password.
insert into public.profiles (user_id, username, full_name, role, branch_id)
select u.id, 'quanly01', 'Quản lý Tuibao', 'manager', null
from auth.users u
where u.email = 'quanly01@tuibao.invalid'
on conflict (user_id) do update set username = excluded.username, full_name = excluded.full_name, role = 'manager', branch_id = null;
