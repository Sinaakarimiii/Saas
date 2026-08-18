-- ROADMAP.md already decided attendance event types beyond clock in/out
-- (lunch/meeting, etc.) must be per-org configurable, not hardcoded -- what
-- was missing was (a) a way for orgs to actually create one, and (b) a way
-- to mark a type as a toggle (start/end pair reported through one button)
-- instead of a single stateless click. `toggle` is per-type, editable, and
-- generic -- no event name is ever special-cased in code.
alter table public.attendance_event_types
  add column toggle boolean not null default false;
