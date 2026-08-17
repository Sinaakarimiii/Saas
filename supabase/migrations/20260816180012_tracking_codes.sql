-- Central registry every module's "important record" registers into.
-- One shared source of uniqueness/generation for the whole platform.
create table public.tracking_codes (
  code text primary key,
  org_id uuid not null references public.organizations(id),
  entity_type text not null,
  entity_id uuid not null,
  created_at timestamptz not null default now(),
  unique (entity_type, entity_id)
);

alter table public.tracking_codes enable row level security;

create policy "tracking_codes_select_member" on public.tracking_codes for select
  using (private.is_org_member(org_id));

grant select on public.tracking_codes to authenticated;

-- Generates an 8-char random code (uppercase letters + digits, excluding
-- visually ambiguous characters O/0/I/1), retrying on collision.
create or replace function private.generate_tracking_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_taken boolean;
  i int;
begin
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, (floor(random() * length(v_alphabet)) + 1)::int, 1);
    end loop;
    select exists (select 1 from public.tracking_codes where code = v_code) into v_taken;
    exit when not v_taken;
  end loop;
  return v_code;
end;
$$;

-- Generic BEFORE INSERT trigger: any table with a `tracking_code text` and
-- `org_id uuid` column can attach this trigger (passing the entity type as
-- the trigger argument) to get a tracking code for free.
create or replace function public.assign_tracking_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  v_code := private.generate_tracking_code();
  new.tracking_code := v_code;
  insert into public.tracking_codes (code, org_id, entity_type, entity_id)
  values (v_code, new.org_id, TG_ARGV[0], new.id);
  return new;
end;
$$;
