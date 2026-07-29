-- ExpenseWise Lenred v1.6
-- Run AFTER v1.4/v1.5 migrations.
-- Fixes category activity trigger crash and keeps activity logging table-safe.

create or replace function public.expense_log_activity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor_name text;
  v_actor_username text;
  v_category_id uuid;
  v_category_name text;
  v_list_title text;
  v_unit_name text;
  v_action text:=lower(tg_op);
begin
  select full_name,username into v_actor_name,v_actor_username
  from public.expense_profiles where id=auth.uid();

  if tg_table_name='expense_categories' then
    if tg_op='DELETE' then
      v_category_id:=old.id; v_category_name:=old.name;
      insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,details,activity_note)
      values(null,auth.uid(),v_actor_name,v_actor_username,v_category_name,'category',old.id,v_action,old.name,'Deleted category');
      return old;
    else
      v_category_id:=new.id; v_category_name:=new.name;
      insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,details,activity_note)
      values(new.id,auth.uid(),v_actor_name,v_actor_username,new.name,'category',new.id,v_action,new.name,
        case tg_op when 'INSERT' then 'Created category' else 'Updated category' end);
      return new;
    end if;
  end if;

  if tg_table_name='expense_items' then
    if tg_op='DELETE' then v_category_id:=old.category_id; else v_category_id:=new.category_id; end if;
    select name into v_category_name from public.expense_categories where id=v_category_id;
    if tg_op='DELETE' then
      select title into v_list_title from public.expense_list_sections where id=old.section_id;
      if old.unit_id is not null then select name into v_unit_name from public.expense_units where id=old.unit_id; end if;
      insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,item_name,quantity,unit_name,currency,price,remarks,activity_note)
      values(old.category_id,old.section_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,v_list_title,'item',old.id,v_action,old.name,old.quantity,coalesce(v_unit_name,old.unit_text),old.currency,old.price,old.remarks,'Deleted an expense item');
      return old;
    else
      select title into v_list_title from public.expense_list_sections where id=new.section_id;
      if new.unit_id is not null then select name into v_unit_name from public.expense_units where id=new.unit_id; end if;
      insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,item_name,quantity,unit_name,currency,price,remarks,activity_note)
      values(new.category_id,new.section_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,v_list_title,'item',new.id,v_action,new.name,new.quantity,coalesce(v_unit_name,new.unit_text),new.currency,new.price,new.remarks,
        case tg_op when 'INSERT' then 'Added an expense item' else 'Edited an expense item' end);
      return new;
    end if;
  end if;

  if tg_table_name='expense_list_sections' then
    if tg_op='DELETE' then v_category_id:=old.category_id; else v_category_id:=new.category_id; end if;
    select name into v_category_name from public.expense_categories where id=v_category_id;
    if tg_op='DELETE' then
      insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,details,activity_note)
      values(old.category_id,old.id,auth.uid(),v_actor_name,v_actor_username,v_category_name,old.title,'list',old.id,v_action,old.title,'Deleted a list');
      return old;
    else
      insert into public.expense_activity_logs(category_id,section_id,actor_id,actor_name,actor_username,category_name,list_title,entity_type,entity_id,action,details,activity_note)
      values(new.category_id,new.id,auth.uid(),v_actor_name,v_actor_username,v_category_name,new.title,'list',new.id,v_action,new.title,
        case tg_op when 'INSERT' then 'Created a list' else 'Edited a list' end);
      return new;
    end if;
  end if;

  if tg_table_name='expense_weekly_budgets' then
    if tg_op='DELETE' then v_category_id:=old.category_id; else v_category_id:=new.category_id; end if;
    select name into v_category_name from public.expense_categories where id=v_category_id;
    if tg_op='DELETE' then
      insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,currency,price,details,activity_note)
      values(old.category_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,'budget',old.id,v_action,old.currency,old.amount,'Weekly budget','Deleted weekly budget');
      return old;
    else
      insert into public.expense_activity_logs(category_id,actor_id,actor_name,actor_username,category_name,entity_type,entity_id,action,currency,price,details,activity_note)
      values(new.category_id,auth.uid(),v_actor_name,v_actor_username,v_category_name,'budget',new.id,v_action,new.currency,new.amount,'Weekly budget',
        case tg_op when 'INSERT' then 'Created weekly budget' else 'Updated weekly budget' end);
      return new;
    end if;
  end if;

  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

-- Category delete is performed by protected Edge Function; keep RLS as-is.
