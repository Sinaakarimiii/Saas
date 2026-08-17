-- The original audit_log select policy only checked org membership, which
-- let a user with only "دیدن تیکت‌های خودم" (ticket.view = own) read the
-- audit history -- including old/new field values -- of OTHER people's
-- tickets, just by querying audit_log directly. That leaks the same data
-- the tickets RLS policy is supposed to hide. Tighten it: for
-- table_name='tickets', apply the same ticket.view scope as the tickets
-- table itself. Other table_names keep the plain org-membership check
-- until they get their own scoped view logic.
drop policy "audit_log_select_member" on public.audit_log;

create policy "audit_log_select_member" on public.audit_log for select
  using (
    private.is_org_member(org_id)
    and (
      table_name <> 'tickets'
      or exists (
        select 1 from public.tickets t
        where t.id = audit_log.record_id
          and (
            private.permission_scope(audit_log.org_id, 'ticket.view') = 'all'
            or (
              private.permission_scope(audit_log.org_id, 'ticket.view') = 'own'
              and t.created_by = (select auth.uid())
            )
          )
      )
    )
  );
