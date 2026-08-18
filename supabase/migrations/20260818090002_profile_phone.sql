-- Full name + mobile number are now required at signup and when an
-- invited member sets their password (the invite flow only ever collects
-- an email, never a name/phone). Nullable at the DB level since existing
-- profiles predate this and a hard NOT NULL would break them; the
-- requirement is enforced in the signup/set-password forms instead.
-- Kept for later reuse (OTP login, password recovery) as requested, not
-- wired into either flow yet.
alter table public.profiles add column phone text;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', '')
  );
  return new;
end;
$$;
