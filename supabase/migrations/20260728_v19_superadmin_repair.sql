-- ExpenseWise Lenred v1.9: repair/register the super-admin profile.
-- This does NOT create or change the Auth password.
-- First create/reset roieocampo@expensewise.app in Authentication > Users.

insert into public.expense_profiles (id, full_name, username, role)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data->>'full_name',''), 'Super Administrator'),
  'roieocampo',
  'super_admin'::public.expense_app_role
from auth.users u
where lower(u.email) = 'roieocampo@expensewise.app'
on conflict (id) do update
set full_name = excluded.full_name,
    username = 'roieocampo',
    role = 'super_admin'::public.expense_app_role;

select p.id,p.full_name,p.username,p.role,u.email
from public.expense_profiles p
join auth.users u on u.id=p.id
where p.username='roieocampo';
