-- Each reported physical damage invalidates every earlier outgoing test and quality release.
alter table public.repair_cases
  add column custody_damage_epoch integer not null default 0 check (custody_damage_epoch >= 0);
alter table public.repair_return_outgoing_checks
  add column custody_damage_epoch integer not null default 0 check (custody_damage_epoch >= 0);

-- Preserve the invalidation for damage reports created before this migration.
update public.repair_cases c
   set custody_damage_epoch = prior.damage_count
  from (select org_id, case_id, count(*)::integer as damage_count
          from public.repair_device_custody_discrepancies
         where kind = 'damage'
         group by org_id, case_id) prior
 where c.org_id = prior.org_id and c.id = prior.case_id;

create function private.mark_repair_custody_damage() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.kind = 'damage' then
    update public.repair_cases
       set custody_damage_epoch = custody_damage_epoch + 1
     where org_id = new.org_id and id = new.case_id
       and verified_device_id = new.device_id;
    if not found then
      raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger repair_custody_damage_epoch
after insert on public.repair_device_custody_discrepancies
for each row execute function private.mark_repair_custody_damage();

create function private.guard_repair_damage_outgoing_check() returns trigger
language plpgsql set search_path = '' as $$
declare v_epoch integer;
begin
  select custody_damage_epoch into v_epoch from public.repair_cases
    where org_id = new.org_id and id = new.case_id;
  if exists (select 1 from public.repair_device_custody_discrepancies d
      where d.org_id = new.org_id and d.device_id = new.device_id
        and d.kind = 'damage' and d.status = 'open') then
    raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode = '23514';
  end if;
  new.custody_damage_epoch := v_epoch;
  return new;
end;
$$;
create trigger repair_damage_outgoing_check_guard
before insert on public.repair_return_outgoing_checks
for each row execute function private.guard_repair_damage_outgoing_check();

create function private.guard_repair_damage_quality_release() returns trigger
language plpgsql set search_path = '' as $$
declare v_epoch integer; v_check public.repair_return_outgoing_checks;
begin
  select custody_damage_epoch into v_epoch from public.repair_cases
    where org_id = new.org_id and id = new.case_id;
  select * into v_check from public.repair_return_outgoing_checks
    where org_id = new.org_id and case_id = new.case_id and id = new.check_id;
  if v_check.custody_damage_epoch is distinct from v_epoch
     or exists (select 1 from public.repair_device_custody_discrepancies d
       where d.org_id = new.org_id and d.device_id = v_check.device_id
         and d.kind = 'damage' and d.status = 'open') then
    raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger repair_damage_quality_release_guard
before insert on public.repair_return_outgoing_releases
for each row execute function private.guard_repair_damage_quality_release();

create function private.guard_repair_damage_delivery() returns trigger
language plpgsql set search_path = '' as $$
declare v_check public.repair_return_outgoing_checks;
begin
  if new.stage = 'delivery' and old.stage = 'test' then
    if exists (select 1 from public.repair_device_custody_discrepancies d
         where d.org_id = new.org_id and d.device_id = new.verified_device_id
           and d.kind = 'damage' and d.status = 'open') then
      raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode = '23514';
    end if;
    select * into v_check from public.repair_return_outgoing_checks
      where org_id = new.org_id and case_id = new.id
      order by revision desc limit 1;
    if v_check.id is null or v_check.custody_damage_epoch <> new.custody_damage_epoch then
      raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger repair_damage_delivery_guard
before update of stage on public.repair_cases
for each row execute function private.guard_repair_damage_delivery();
