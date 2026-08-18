-- One direct supervisor per member -- a real tree, not a matrix. A member
-- with manager_id = null sits at the top of the chart (typically the
-- owner).
alter table public.org_members add column manager_id uuid references public.org_members(id);
alter table public.org_members add constraint org_members_manager_not_self check (manager_id is distinct from id);

-- Blocks a manager_id change/insert that would create a cycle (A manages
-- B, B manages A, ...) -- a cycle would make is_manager_of() below loop
-- forever and silently corrupt every permission check built on it, so
-- this is enforced at write time rather than trusted to the UI.
create or replace function public.prevent_manager_cycle()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_current uuid;
  v_depth int := 0;
begin
  if new.manager_id is null then
    return new;
  end if;

  v_current := new.manager_id;
  while v_current is not null loop
    if v_current = new.id then
      raise exception 'حلقه در زنجیره‌ی سرپرستی مجاز نیست';
    end if;
    v_depth := v_depth + 1;
    if v_depth > 100 then
      raise exception 'زنجیره‌ی سرپرستی خیلی عمیق است';
    end if;
    select manager_id into v_current from public.org_members where id = v_current;
  end loop;

  return new;
end;
$$;

create trigger trg_org_members_manager_cycle
  before insert or update of manager_id on public.org_members
  for each row execute function public.prevent_manager_cycle();

-- Is the current user somewhere above p_target_member_id in the
-- reporting chain (direct manager, manager's manager, ... to any depth)?
-- This is the one mechanism every "team scope" permission (leave.approve,
-- attendance.view, shift.manage) reuses -- see 20260818100002.
create or replace function private.is_manager_of(p_org_id uuid, p_target_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive ancestors as (
    select om.manager_id as ancestor_id
    from public.org_members om
    where om.id = p_target_member_id and om.org_id = p_org_id

    union all

    select om.manager_id as ancestor_id
    from public.org_members om
    join ancestors a on om.id = a.ancestor_id
    where a.ancestor_id is not null
  )
  select exists (
    select 1 from ancestors a
    join public.org_members me
      on me.id = a.ancestor_id
    where me.org_id = p_org_id
      and me.user_id = auth.uid()
      and me.deleted_at is null
  );
$$;

grant execute on function private.is_manager_of(uuid, uuid) to authenticated;

create or replace function public.is_manager_of(p_org_id uuid, p_target_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_manager_of(p_org_id, p_target_member_id);
$$;

grant execute on function public.is_manager_of(uuid, uuid) to authenticated;
