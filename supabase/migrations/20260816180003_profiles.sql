create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.profiles enable row level security;

-- A user can always see/update their own profile. The additional policy
-- allowing org co-members to see each other's profiles is added in 0009,
-- once org_members exists.
create policy "profiles_select_own" on public.profiles for select
  using (id = (select auth.uid()));

create policy "profiles_update_own" on public.profiles for update
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

grant select, update on public.profiles to authenticated;

-- Auto-create a profile row whenever a new auth user is created.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, nullif(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
