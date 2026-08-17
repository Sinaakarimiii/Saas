-- organizations --------------------------------------------------------
-- No insert/update policy: organizations are only ever created through
-- the create_organization() function (0010), which also sets up the
-- owner role and first membership atomically.
create policy "organizations_select_member" on public.organizations for select
  using (private.is_org_member(id));

grant select on public.organizations to authenticated;

-- profiles: allow org co-members to see each other's names/emails -------
create policy "profiles_select_org_comembers" on public.profiles for select
  using (
    exists (
      select 1
      from public.org_members me
      join public.org_members them on them.org_id = me.org_id
      where me.user_id = (select auth.uid())
        and me.deleted_at is null
        and them.user_id = public.profiles.id
        and them.deleted_at is null
    )
  );

-- roles -------------------------------------------------------------------
create policy "roles_select_member" on public.roles for select
  using (private.is_org_member(org_id));

create policy "roles_insert_manager" on public.roles for insert
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_roles')
  );

-- is_system roles (the auto-created "مالک" role) can't be edited/removed
-- through the API, only through a migration.
create policy "roles_update_manager" on public.roles for update
  using (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_roles')
    and is_system = false
  )
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_roles')
    and is_system = false
  );

grant select, insert, update on public.roles to authenticated;

-- org_members ---------------------------------------------------------------
create policy "org_members_select_member" on public.org_members for select
  using (private.is_org_member(org_id));

create policy "org_members_insert_manager" on public.org_members for insert
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_members')
  );

create policy "org_members_update_manager" on public.org_members for update
  using (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_members')
  )
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'org.manage_members')
  );

grant select, insert, update on public.org_members to authenticated;

-- role_permissions --------------------------------------------------------
create policy "role_permissions_select_member" on public.role_permissions for select
  using (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and private.is_org_member(r.org_id)
    )
  );

create policy "role_permissions_manage" on public.role_permissions for all
  using (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and private.is_org_member(r.org_id)
        and private.has_permission(r.org_id, 'org.manage_roles')
        and r.is_system = false
    )
  )
  with check (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and private.is_org_member(r.org_id)
        and private.has_permission(r.org_id, 'org.manage_roles')
        and r.is_system = false
    )
  );

grant select, insert, update, delete on public.role_permissions to authenticated;
