-- ExpenseWise Lenred v1.4
-- Run AFTER v1.3 stabilization.
-- Adds category activity logs and keeps custom/auto category codes editable.

create table if not exists public.expense_activity_logs (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.expense_categories(id) on delete cascade,
  section_id uuid,
  actor_id uuid references public.expense_profiles(id) on delete set null,
  actor_name text,
  actor_username text,
  category_name text,
  list_title text,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  item_name text,
  quantity numeric(14,3),
  unit_name text,
  currency text,
  price numeric(14,2),
  remarks text,
  details text,
  activity_note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_expense_activity_cat_time on public.expense_activity_logs(category_id,created_at desc);

alter table public.expense_activity_logs enable row level security;
drop policy if exists expense_activity_read on public.expense_activity_logs;
create policy expense_activity_read on public.expense_activity_logs
for select to authenticated
using (
  public.expense_is_admin()
  or exists (
    select 1 from public.expense_category_members m
    where m.category_id=expense_activity_logs.category_id and m.user_id=auth.uid()
  )
);

create or replace function public.expense_log_activity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_actor_name text;
  v_actor_username text;
  v_category_name text;
  v_list_title text;
  v_unit_name text;
  v_action text;
begin
  if tg_op='DELETE' then
    r := old;
  else
    r := new;
  end if;
  select full_name,username into v_actor_name,v_actor_username
  from public.expense_profiles where id=auth.uid();

  if r.category_id is not null then
    select name into v_category_name from public.expense_categories where id=r.category_id;
  end if;

  v_action := lower(tg_op);

  if tg_table_name='expense_items' then
    select title into v_list_title from public.expense_list_sections where id=r.section_id;
    if r.unit_id is not null then select name into v_unit_name from public.expense_units where id=r.unit_id; end if;
    insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,item_name,quantity,unit_name,currency,price,remarks,activity_note)
    values(r.category_id,r.section_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,v_list_title,'item',r.id,v_action,r.name,r.quantity,coalesce(v_unit_name,r.unit_text),r.currency,r.price,r.remarks,
      case tg_op when 'INSERT' then 'Added an expense item' when 'UPDATE' then 'Edited an expense item' else 'Deleted an expense item' end);
  elsif tg_table_name='expense_list_sections' then
    insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,details,activity_note)
    values(r.category_id,r.id,auth.uid(),v_actor_name,v_actor_username,v_category_name,r.title,'list',r.id,v_action,r.title,
      case tg_op when 'INSERT' then 'Created a list' when 'UPDATE' then 'Edited a list' else 'Deleted a list' end);
  elsif tg_table_name='expense_weekly_budgets' then
    insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,currency,price,details,activity_note)
    values(r.category_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,'budget',r.id,v_action,r.currency,r.amount,'Weekly budget',
      case tg_op when 'INSERT' then 'Created weekly budget' when 'UPDATE' then 'Updated weekly budget' else 'Deleted weekly budget' end);
  elsif tg_table_name='expense_categories' then
    insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,details,activity_note)
    values(r.id,auth.uid(),v_actor_name,v_actor_username,r.name,'category',r.id,v_action,r.name,
      case tg_op when 'INSERT' then 'Created category' when 'UPDATE' then 'Updated category' else 'Deleted category' end);
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

drop trigger if exists expense_activity_items on public.expense_items;
create trigger expense_activity_items after insert or update or delete on public.expense_items for each row execute procedure public.expense_log_activity();
drop trigger if exists expense_activity_sections on public.expense_list_sections;
create trigger expense_activity_sections after insert or update or delete on public.expense_list_sections for each row execute procedure public.expense_log_activity();
drop trigger if exists expense_activity_budgets on public.expense_weekly_budgets;
create trigger expense_activity_budgets after insert or update or delete on public.expense_weekly_budgets for each row execute procedure public.expense_log_activity();
drop trigger if exists expense_activity_categories on public.expense_categories;
create trigger expense_activity_categories after insert or update on public.expense_categories for each row execute procedure public.expense_log_activity();
