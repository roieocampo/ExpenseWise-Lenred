-- ExpenseWise Lenred v1.2 upgrade.
-- Run AFTER 20260728_predeploy_stabilization.sql.
-- Safe for shared SLIC_DashBoards: only expense_* objects are changed.

-- 1) Support a protected super-admin role.
alter type public.expense_app_role add value if not exists 'super_admin';

-- 2) Change currency storage from the old PHP/USD enum to ISO-style 3-letter text.
alter table public.expense_weekly_budgets alter column currency drop default;
alter table public.expense_list_sections alter column currency drop default;
alter table public.expense_items alter column currency drop default;
alter table public.expense_weekly_budgets alter column currency type text using currency::text;
alter table public.expense_list_sections alter column currency type text using currency::text;
alter table public.expense_items alter column currency type text using currency::text;
alter table public.expense_weekly_budgets alter column currency set default 'PHP';
alter table public.expense_list_sections alter column currency set default 'PHP';
alter table public.expense_items alter column currency set default 'PHP';

alter table public.expense_categories add column if not exists currency text not null default 'PHP';
alter table public.expense_categories add column if not exists available_date date not null default current_date;

-- Preserve existing category currency using the first existing list currency when possible.
update public.expense_categories c
set currency=coalesce((select s.currency from public.expense_list_sections s where s.category_id=c.id order by s.created_at limit 1),'PHP')
where c.currency is null or c.currency='PHP';

-- Make historical lists/items/budgets follow their category currency.
update public.expense_list_sections s set currency=c.currency from public.expense_categories c where c.id=s.category_id;
update public.expense_items i set currency=c.currency from public.expense_categories c where c.id=i.category_id;
update public.expense_weekly_budgets b set currency=c.currency from public.expense_categories c where c.id=b.category_id;

-- Currency values must look like ISO 4217 codes (PHP, USD, SGD, ...).
alter table public.expense_categories drop constraint if exists expense_categories_currency_code;
alter table public.expense_categories add constraint expense_categories_currency_code check(currency ~ '^[A-Z]{3}$');
alter table public.expense_weekly_budgets drop constraint if exists expense_weekly_budgets_currency_code;
alter table public.expense_weekly_budgets add constraint expense_weekly_budgets_currency_code check(currency ~ '^[A-Z]{3}$');
alter table public.expense_list_sections drop constraint if exists expense_list_sections_currency_code;
alter table public.expense_list_sections add constraint expense_list_sections_currency_code check(currency ~ '^[A-Z]{3}$');
alter table public.expense_items drop constraint if exists expense_items_currency_code;
alter table public.expense_items add constraint expense_items_currency_code check(currency ~ '^[A-Z]{3}$');

-- Admin includes normal admin and protected super admin.
create or replace function public.expense_is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.expense_profiles p where p.id=auth.uid() and p.role in ('admin','super_admin'));
$$;

-- Hidden categories cannot be edited by anyone from the expense workspace.
create or replace function public.expense_can_edit_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.expense_categories c where c.id=p_category and c.is_visible=true)
  and (public.expense_is_admin() or exists(select 1 from public.expense_category_members cm where cm.category_id=p_category and cm.user_id=auth.uid()));
$$;

-- Admin can still read hidden categories in Category Management; normal users cannot discover/read them.
create or replace function public.expense_can_view_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.expense_is_admin()
  or exists(select 1 from public.expense_categories c where c.id=p_category and c.is_visible=true);
$$;

create or replace function public.expense_can_access_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$ select public.expense_can_edit_category(p_category); $$;

-- Category join is category-specific and rejects hidden categories.
create or replace function public.expense_join_category_by_code(p_code text,p_category_id uuid default null)
returns text language plpgsql security definer set search_path=public as $$
declare v_category public.expense_categories%rowtype;
begin
  select * into v_category from public.expense_categories
  where upper(share_code)=upper(trim(p_code))
    and is_visible=true
    and (p_category_id is null or id=p_category_id);
  if v_category.id is null then raise exception 'Invalid code or category is hidden.'; end if;
  insert into public.expense_category_members(category_id,user_id) values(v_category.id,auth.uid()) on conflict do nothing;
  return v_category.name;
end; $$;

grant execute on function public.expense_join_category_by_code(text,uuid) to authenticated;

-- Resolve a username to its actual Supabase Auth email so usernames remain editable.
-- Only the exact requested username is resolved.
create or replace function public.expense_resolve_login_email(p_username text)
returns text language sql stable security definer set search_path=public,auth as $$
  select u.email
  from public.expense_profiles p join auth.users u on u.id=p.id
  where lower(p.username)=lower(trim(p_username))
  limit 1;
$$;
grant execute on function public.expense_resolve_login_email(text) to anon,authenticated;

-- Recreate data policies using the new hidden-category edit rule.
drop policy if exists expense_budgets_insert on public.expense_weekly_budgets;
create policy expense_budgets_insert on public.expense_weekly_budgets for insert to authenticated with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_budgets_update on public.expense_weekly_budgets;
create policy expense_budgets_update on public.expense_weekly_budgets for update to authenticated using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_budgets_delete on public.expense_weekly_budgets;
create policy expense_budgets_delete on public.expense_weekly_budgets for delete to authenticated using(public.expense_can_edit_category(category_id));
drop policy if exists expense_sections_insert on public.expense_list_sections;
create policy expense_sections_insert on public.expense_list_sections for insert to authenticated with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_sections_update on public.expense_list_sections;
create policy expense_sections_update on public.expense_list_sections for update to authenticated using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_sections_delete on public.expense_list_sections;
create policy expense_sections_delete on public.expense_list_sections for delete to authenticated using(public.expense_can_edit_category(category_id));
drop policy if exists expense_items_insert on public.expense_items;
create policy expense_items_insert on public.expense_items for insert to authenticated with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_items_update on public.expense_items;
create policy expense_items_update on public.expense_items for update to authenticated using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_items_delete on public.expense_items;
create policy expense_items_delete on public.expense_items for delete to authenticated using(public.expense_can_edit_category(category_id));

-- IMPORTANT SUPER ADMIN SETUP:
-- Create the requested super-admin account in Authentication > Users first,
-- with username metadata "roieocampo" and app="expensewise".
-- Then run:
-- update public.expense_profiles set role='super_admin' where username='roieocampo';
