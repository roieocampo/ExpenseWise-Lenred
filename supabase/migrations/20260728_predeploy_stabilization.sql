-- Run this ONCE on an existing ExpenseWise installation before testing v1.1.
-- It is safe for the shared SLIC_DashBoards Supabase project and only changes expense_* objects.

alter table public.expense_items alter column name drop not null;
alter table public.expense_items alter column name drop default;
alter table public.expense_categories add column if not exists is_visible boolean not null default true;
alter table public.expense_list_sections add column if not exists currency public.expense_money_currency not null default 'PHP';

-- Existing item rows inherit their list currency.
update public.expense_items i
set currency=s.currency
from public.expense_list_sections s
where i.section_id=s.id and i.currency is distinct from s.currency;

create or replace function public.expense_can_edit_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.expense_is_admin() or exists(
    select 1 from public.expense_category_members cm
    where cm.category_id=p_category and cm.user_id=auth.uid()
  );
$$;

create or replace function public.expense_can_view_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.expense_is_admin()
    or exists(select 1 from public.expense_categories c where c.id=p_category and c.is_visible=true)
    or exists(select 1 from public.expense_category_members cm where cm.category_id=p_category and cm.user_id=auth.uid());
$$;

create or replace function public.expense_can_access_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.expense_can_edit_category(p_category);
$$;

-- Replace data policies so visible categories are readable but only members/admins can edit.
drop policy if exists expense_categories_read_access on public.expense_categories;
create policy expense_categories_read_access on public.expense_categories for select to authenticated
using(public.expense_can_view_category(id));

drop policy if exists expense_budgets_read on public.expense_weekly_budgets;
create policy expense_budgets_read on public.expense_weekly_budgets for select to authenticated
using(public.expense_can_view_category(category_id));
drop policy if exists expense_budgets_insert on public.expense_weekly_budgets;
create policy expense_budgets_insert on public.expense_weekly_budgets for insert to authenticated
with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_budgets_update on public.expense_weekly_budgets;
create policy expense_budgets_update on public.expense_weekly_budgets for update to authenticated
using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_budgets_delete on public.expense_weekly_budgets;
create policy expense_budgets_delete on public.expense_weekly_budgets for delete to authenticated
using(public.expense_can_edit_category(category_id));

drop policy if exists expense_sections_read on public.expense_list_sections;
create policy expense_sections_read on public.expense_list_sections for select to authenticated
using(public.expense_can_view_category(category_id));
drop policy if exists expense_sections_insert on public.expense_list_sections;
create policy expense_sections_insert on public.expense_list_sections for insert to authenticated
with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_sections_update on public.expense_list_sections;
create policy expense_sections_update on public.expense_list_sections for update to authenticated
using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_sections_delete on public.expense_list_sections;
create policy expense_sections_delete on public.expense_list_sections for delete to authenticated
using(public.expense_can_edit_category(category_id));

drop policy if exists expense_items_read on public.expense_items;
create policy expense_items_read on public.expense_items for select to authenticated
using(public.expense_can_view_category(category_id));
drop policy if exists expense_items_insert on public.expense_items;
create policy expense_items_insert on public.expense_items for insert to authenticated
with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_items_update on public.expense_items;
create policy expense_items_update on public.expense_items for update to authenticated
using(public.expense_can_edit_category(category_id)) with check(public.expense_can_edit_category(category_id));
drop policy if exists expense_items_delete on public.expense_items;
create policy expense_items_delete on public.expense_items for delete to authenticated
using(public.expense_can_edit_category(category_id));
