"use client";

import { useTransition } from "react";
import { removeField } from "../actions";
import { Button } from "@/components/ui/button";

export function RemoveFieldButton({
  orgId,
  formTemplateId,
  fieldId,
}: {
  orgId: string;
  formTemplateId: string;
  fieldId: string;
}) {
  const [isPending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={isPending}
      onClick={() => {
        if (!confirm("این فیلد حذف شود؟")) return;
        startTransition(async () => {
          await removeField(orgId, formTemplateId, fieldId);
        });
      }}
    >
      حذف
    </Button>
  );
}
