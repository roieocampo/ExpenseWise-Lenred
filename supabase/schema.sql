-- ExpenseWise PH schema for a SHARED Supabase project (e.g. SLIC_DashBoards)
-- All application objects use the expense_ prefix to avoid collisions.

create extension if not exists pgcrypto;

DO $$ BEGIN
  CREATE TYPE public.expense_app_role AS ENUM ('admin','user');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.expense_money_currency AS ENUM ('PHP','USD');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

create table if not exists public.expense_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  username text not null unique,
  role public.expense_app_role not null default 'user',
  created_at timestamptz not null default now()
);

create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  share_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,10)),
  created_by uuid not null references public.expense_profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.expense_category_members (
  category_id uuid not null references public.expense_categories(id) on delete cascade,
  user_id uuid not null references public.expense_profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(category_id,user_id)
);

create table if not exists public.expense_units (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_by uuid references public.expense_profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.expense_weekly_budgets (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.expense_categories(id) on delete cascade,
  week_start date not null,
  currency public.expense_money_currency not null default 'PHP',
  amount numeric(14,2) not null default 0 check(amount >= 0),
  updated_by uuid references public.expense_profiles(id),
  updated_at timestamptz not null default now(),
  unique(category_id,week_start,currency)
);

create table if not exists public.expense_list_sections (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.expense_categories(id) on delete cascade,
  week_start date not null,
  title text not null,
  sort_order integer not null default 0,
  created_by uuid references public.expense_profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.expense_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.expense_categories(id) on delete cascade,
  section_id uuid not null references public.expense_list_sections(id) on delete cascade,
  week_start date not null,
  name text not null default '',
  quantity numeric(14,3),
  unit_id uuid references public.expense_units(id) on delete set null,
  unit_text text,
  currency public.expense_money_currency not null default 'PHP',
  price numeric(14,2),
  remarks text,
  sort_order integer not null default 0,
  created_by uuid references public.expense_profiles(id),
  updated_by uuid references public.expense_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(quantity is null or quantity >= 0),
  check(price is null or price >= 0)
);

create index if not exists idx_expense_sections_cat_week on public.expense_list_sections(category_id,week_start);
create index if not exists idx_expense_items_cat_week on public.expense_items(category_id,week_start);
create index if not exists idx_expense_items_section on public.expense_items(section_id);

create or replace function public.expense_is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.expense_profiles p
    where p.id=auth.uid() and p.role='admin'
  );
$$;

create or replace function public.expense_can_access_category(p_category uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.expense_is_admin() or exists(
    select 1 from public.expense_category_members cm
    where cm.category_id=p_category and cm.user_id=auth.uid()
  );
$$;

create or replace function public.expense_handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- Important for a shared Supabase project: ignore non-ExpenseWise Auth users.
  if coalesce(new.raw_user_meta_data->>'app','') <> 'expensewise' then
    return new;
  end if;

  insert into public.expense_profiles(id,full_name,username,role)
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name','User'),
    lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1))),
    'user'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- A unique trigger name prevents collisions with triggers used by your SLIC app.
drop trigger if exists expense_on_auth_user_created on auth.users;
create trigger expense_on_auth_user_created
after insert on auth.users
for each row execute procedure public.expense_handle_new_user();

create or replace function public.expense_join_category_by_code(p_code text)
returns text language plpgsql security definer set search_path=public as $$
declare v_cat public.expense_categories%rowtype;
begin
  select * into v_cat
  from public.expense_categories
  where upper(share_code)=upper(trim(p_code));

  if v_cat.id is null then
    raise exception 'Invalid category code';
  end if;

  insert into public.expense_category_members(category_id,user_id)
  values(v_cat.id,auth.uid())
  on conflict do nothing;

  return v_cat.name;
end;
$$;
grant execute on function public.expense_join_category_by_code(text) to authenticated;

create or replace function public.expense_admin_reset_category(p_category_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.expense_is_admin() then
    raise exception 'Admin access required';
  end if;

  delete from public.expense_items where category_id=p_category_id;
  delete from public.expense_list_sections where category_id=p_category_id;
  delete from public.expense_weekly_budgets where category_id=p_category_id;
end;
$$;
grant execute on function public.expense_admin_reset_category(uuid) to authenticated;

create or replace function public.expense_set_audit_fields()
returns trigger language plpgsql as $$
begin
  if tg_op='INSERT' then
    if new.created_by is null then new.created_by=auth.uid(); end if;
  end if;
  if to_jsonb(new) ? 'updated_by' then new.updated_by=auth.uid(); end if;
  if to_jsonb(new) ? 'updated_at' then new.updated_at=now(); end if;
  return new;
end;
$$;

drop trigger if exists expense_audit_categories on public.expense_categories;
create trigger expense_audit_categories before insert on public.expense_categories for each row execute procedure public.expense_set_audit_fields();
drop trigger if exists expense_audit_units on public.expense_units;
create trigger expense_audit_units before insert on public.expense_units for each row execute procedure public.expense_set_audit_fields();
drop trigger if exists expense_audit_sections on public.expense_list_sections;
create trigger expense_audit_sections before insert on public.expense_list_sections for each row execute procedure public.expense_set_audit_fields();
drop trigger if exists expense_audit_items on public.expense_items;
create trigger expense_audit_items before insert or update on public.expense_items for each row execute procedure public.expense_set_audit_fields();
drop trigger if exists expense_audit_budgets on public.expense_weekly_budgets;
create trigger expense_audit_budgets before insert or update on public.expense_weekly_budgets for each row execute procedure public.expense_set_audit_fields();

alter table public.expense_profiles enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expense_category_members enable row level security;
alter table public.expense_units enable row level security;
alter table public.expense_weekly_budgets enable row level security;
alter table public.expense_list_sections enable row level security;
alter table public.expense_items enable row level security;

-- Re-runnable policy creation
DO $$ BEGIN CREATE POLICY expense_profiles_read_self_or_admin ON public.expense_profiles FOR SELECT TO authenticated USING(id=auth.uid() OR public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_categories_read_access ON public.expense_categories FOR SELECT TO authenticated USING(public.expense_can_access_category(id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_categories_admin_insert ON public.expense_categories FOR INSERT TO authenticated WITH CHECK(public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_categories_admin_update ON public.expense_categories FOR UPDATE TO authenticated USING(public.expense_is_admin()) WITH CHECK(public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_categories_admin_delete ON public.expense_categories FOR DELETE TO authenticated USING(public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE POLICY expense_members_read_access ON public.expense_category_members FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_members_admin_delete ON public.expense_category_members FOR DELETE TO authenticated USING(public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE POLICY expense_units_read ON public.expense_units FOR SELECT TO authenticated USING(true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_units_insert ON public.expense_units FOR INSERT TO authenticated WITH CHECK(auth.uid() IS NOT NULL); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_units_admin_delete ON public.expense_units FOR DELETE TO authenticated USING(public.expense_is_admin()); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE POLICY expense_budgets_read ON public.expense_weekly_budgets FOR SELECT TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_budgets_insert ON public.expense_weekly_budgets FOR INSERT TO authenticated WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_budgets_update ON public.expense_weekly_budgets FOR UPDATE TO authenticated USING(public.expense_can_access_category(category_id)) WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_budgets_delete ON public.expense_weekly_budgets FOR DELETE TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE POLICY expense_sections_read ON public.expense_list_sections FOR SELECT TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_sections_insert ON public.expense_list_sections FOR INSERT TO authenticated WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_sections_update ON public.expense_list_sections FOR UPDATE TO authenticated USING(public.expense_can_access_category(category_id)) WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_sections_delete ON public.expense_list_sections FOR DELETE TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE POLICY expense_items_read ON public.expense_items FOR SELECT TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_items_insert ON public.expense_items FOR INSERT TO authenticated WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_items_update ON public.expense_items FOR UPDATE TO authenticated USING(public.expense_can_access_category(category_id)) WITH CHECK(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY expense_items_delete ON public.expense_items FOR DELETE TO authenticated USING(public.expense_can_access_category(category_id)); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

insert into public.expense_units(name)
values ('pc'),('pack'),('gram'),('kilo'),('litre'),('ml'),('bottle'),('can'),('box'),('dozen'),('bundle'),('tray'),('sack')
on conflict do nothing;

-- After creating your first expense admin Auth user, promote it once:
-- update public.expense_profiles set role='admin' where username='admin';
