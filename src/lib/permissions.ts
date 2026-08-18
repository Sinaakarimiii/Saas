// Mirrors the rows seeded into public.permissions (see
// supabase/migrations/20260816180004_permissions_catalog.sql). Keeping the
// keys here means the UI never hardcodes the string in more than one place.
export const PERMISSIONS = {
  MANAGE_MEMBERS: "org.manage_members",
  MANAGE_ROLES: "org.manage_roles",
  MANAGE_FORMS: "form.manage",
  TICKET_CREATE: "ticket.create",
  TICKET_VIEW: "ticket.view",
  TICKET_EDIT: "ticket.edit",
  SHIFT_MANAGE: "shift.manage",
  LEAVE_REQUEST: "leave.request",
  LEAVE_APPROVE: "leave.approve",
  ATTENDANCE_RECORD: "attendance.record",
  ATTENDANCE_VIEW: "attendance.view",
  CALENDAR_MANAGE_DAYS: "calendar.manage_days",
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
export type PermissionScope = "own" | "all" | "team";
