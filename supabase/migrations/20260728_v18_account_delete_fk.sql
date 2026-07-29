-- ExpenseWise Lenred v1.8
-- Allow Auth account deletion without deleting historical expense rows.
-- Memberships still cascade away; creator/updater references become NULL.

alter table public.expense_categories alter column created_by drop not null;

alter table public.expense_categories drop constraint if exists expense_categories_created_by_fkey;
alter table public.expense_categories add constraint expense_categories_created_by_fkey foreign key (created_by) references public.expense_profiles(id) on delete set null;

alter table public.expense_units drop constraint if exists expense_units_created_by_fkey;
alter table public.expense_units add constraint expense_units_created_by_fkey foreign key (created_by) references public.expense_profiles(id) on delete set null;

alter table public.expense_weekly_budgets drop constraint if exists expense_weekly_budgets_updated_by_fkey;
alter table public.expense_weekly_budgets add constraint expense_weekly_budgets_updated_by_fkey foreign key (updated_by) references public.expense_profiles(id) on delete set null;

alter table public.expense_list_sections drop constraint if exists expense_list_sections_created_by_fkey;
alter table public.expense_list_sections add constraint expense_list_sections_created_by_fkey foreign key (created_by) references public.expense_profiles(id) on delete set null;

alter table public.expense_items drop constraint if exists expense_items_created_by_fkey;
alter table public.expense_items add constraint expense_items_created_by_fkey foreign key (created_by) references public.expense_profiles(id) on delete set null;

alter table public.expense_items drop constraint if exists expense_items_updated_by_fkey;
alter table public.expense_items add constraint expense_items_updated_by_fkey foreign key (updated_by) references public.expense_profiles(id) on delete set null;
