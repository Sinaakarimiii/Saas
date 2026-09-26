"use client";

import { useState, useTransition } from "react";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { setRoleInvitationApproval } from "./actions";

export function RoleInvitationApproval({
  orgId,
  roleId,
  initialApproved,
}: {
  orgId: string;
  roleId: string;
  initialApproved: boolean;
}) {
  const [approved, setApproved] = useState(initialApproved);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function change(value: boolean) {
    setError(null);
    startTransition(async () => {
      const result = await setRoleInvitationApproval(orgId, roleId, value);
      if (result.error) setError(result.error);
      else setApproved(value);
    });
  }

  return (
    <div className="space-y-1">
      <div className="flex items-center gap-2">
        <Checkbox
          id={`invite-${roleId}`}
          checked={approved}
          disabled={pending}
          onCheckedChange={(value) => change(value === true)}
        />
        <Label htmlFor={`invite-${roleId}`} className="text-sm font-normal">
          مدیر اعضا می‌تواند این نقش را دعوت کند
        </Label>
      </div>
      {error && <p className="text-destructive text-sm">{error}</p>}
    </div>
  );
}
