-- ExpenseWise Lenred v1.3 stabilization
-- Run AFTER the v1.2 upgrade has completed successfully.
-- No enum changes are made here.

-- 1) Fix audit trigger: only reference columns that actually exist on each table.
create or replace function public.expense_set_audit_fields()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_table_name = 'expense_categories' then
    if tg_op='INSERT' and new.created_by is null then new.created_by=auth.uid(); end if;
  elsif tg_table_name = 'expense_units' then
    if tg_op='INSERT' and new.created_by is null then new.created_by=auth.uid(); end if;
  elsif tg_table_name = 'expense_list_sections' then
    if tg_op='INSERT' and new.created_by is null then new.created_by=auth.uid(); end if;
  elsif tg_table_name = 'expense_items' then
    if tg_op='INSERT' and new.created_by is null then new.created_by=auth.uid(); end if;
    new.updated_by=auth.uid();
    new.updated_at=now();
  elsif tg_table_name = 'expense_weekly_budgets' then
    new.updated_by=auth.uid();
    new.updated_at=now();
  end if;
  return new;
end;
$$;

-- 2) Weekly budget is readable by category viewers, but writable only by admins/super admins.
drop policy if exists expense_budgets_insert on public.expense_weekly_budgets;
create policy expense_budgets_insert on public.expense_weekly_budgets
for insert to authenticated
with check(public.expense_is_admin());

drop policy if exists expense_budgets_update on public.expense_weekly_budgets;
create policy expense_budgets_update on public.expense_weekly_budgets
for update to authenticated
using(public.expense_is_admin())
with check(public.expense_is_admin());

drop policy if exists expense_budgets_delete on public.expense_weekly_budgets;
create policy expense_budgets_delete on public.expense_weekly_budgets
for delete to authenticated
using(public.expense_is_admin());

-- Existing SELECT policy remains category-access based.

-- 3) Keep the old reset RPC admin-only, but the v1.3 UI uses the protected Edge Function instead.
create or replace function public.expense_admin_reset_category(p_category_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.expense_is_admin() then raise exception 'Admin access required'; end if;
  delete from public.expense_items where category_id=p_category_id;
  delete from public.expense_list_sections where category_id=p_category_id;
  delete from public.expense_weekly_budgets where category_id=p_category_id;
  delete from public.expense_category_members where category_id=p_category_id;
end;
$$;

-- 4) Secure per-category/per-user summary available to admins and members of that category.
create or replace function public.expense_category_summary(p_category_id uuid, p_week_start date)
returns table(
  user_id uuid,
  full_name text,
  username text,
  category_id uuid,
  category_name text,
  currency text,
  subtotal numeric
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if p_category_id is null then
    if not public.expense_is_admin() then raise exception 'Admin access required'; end if;
    return query
      select p.id,p.full_name,p.username,c.id,c.name,i.currency,coalesce(sum(i.price),0)::numeric
      from public.expense_items i
      join public.expense_profiles p on p.id=i.created_by
      join public.expense_categories c on c.id=i.category_id
      where i.week_start=p_week_start
      group by p.id,p.full_name,p.username,c.id,c.name,i.currency
      order by p.full_name,c.name;
  else
    if not (public.expense_is_admin() or exists(
      select 1 from public.expense_category_members m where m.category_id=p_category_id and m.user_id=auth.uid()
    )) then raise exception 'Category access required'; end if;
    return query
      select p.id,p.full_name,p.username,c.id,c.name,i.currency,coalesce(sum(i.price),0)::numeric
      from public.expense_items i
      join public.expense_profiles p on p.id=i.created_by
      join public.expense_categories c on c.id=i.category_id
      where i.week_start=p_week_start and i.category_id=p_category_id
      group by p.id,p.full_name,p.username,c.id,c.name,i.currency
      order by p.full_name;
  end if;
end;
$$;
grant execute on function public.expense_category_summary(uuid,date) to authenticated;
