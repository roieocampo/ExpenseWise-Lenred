-- ExpenseWise Lenred v1.9.4
-- Persist Summary include/exclude contributor choices by category + week + account.

create table if not exists public.expense_summary_inclusions (
  category_id uuid not null references public.expense_categories(id) on delete cascade,
  week_start date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  included boolean not null default true,
  updated_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (category_id, week_start, user_id)
);

alter table public.expense_summary_inclusions enable row level security;

drop policy if exists expense_summary_inclusions_select on public.expense_summary_inclusions;
create policy expense_summary_inclusions_select
on public.expense_summary_inclusions
for select
to authenticated
using (
  public.expense_is_admin()
  or public.expense_can_access_category(category_id)
);

drop policy if exists expense_summary_inclusions_admin_insert on public.expense_summary_inclusions;
create policy expense_summary_inclusions_admin_insert
on public.expense_summary_inclusions
for insert
to authenticated
with check (public.expense_is_admin());

drop policy if exists expense_summary_inclusions_admin_update on public.expense_summary_inclusions;
create policy expense_summary_inclusions_admin_update
on public.expense_summary_inclusions
for update
to authenticated
using (public.expense_is_admin())
with check (public.expense_is_admin());

drop policy if exists expense_summary_inclusions_admin_delete on public.expense_summary_inclusions;
create policy expense_summary_inclusions_admin_delete
on public.expense_summary_inclusions
for delete
to authenticated
using (public.expense_is_admin());

create or replace function public.expense_touch_summary_inclusion()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists expense_touch_summary_inclusion on public.expense_summary_inclusions;
create trigger expense_touch_summary_inclusion
before update on public.expense_summary_inclusions
for each row execute function public.expense_touch_summary_inclusion();
