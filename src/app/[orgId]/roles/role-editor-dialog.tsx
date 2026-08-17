"use client";

import { useState, useTransition, type ReactNode } from "react";
import { saveRole, type PermissionInput } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

type PermissionCatalogItem = {
  key: string;
  label_fa: string;
  is_scopable: boolean;
};

type ExistingRole = {
  id: string;
  name: string;
  isSystem: boolean;
  grants: Record<string, "own" | "all" | null>;
};

export function RoleEditorDialog({
  orgId,
  permissionsCatalog,
  role,
  trigger,
}: {
  orgId: string;
  permissionsCatalog: PermissionCatalogItem[];
  role?: ExistingRole;
  trigger: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(role?.name ?? "");
  const [grants, setGrants] = useState<
    Record<string, { granted: boolean; scope: "own" | "all" | null }>
  >(() => {
    const initial: Record<string, { granted: boolean; scope: "own" | "all" | null }> = {};
    for (const p of permissionsCatalog) {
      const existingScope = role?.grants[p.key];
      initial[p.key] = {
        granted: role ? p.key in role.grants : false,
        scope: existingScope ?? (p.is_scopable ? "own" : null),
      };
    }
    return initial;
  });
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const isSystem = !!role?.isSystem;

  function toggle(key: string, checked: boolean) {
    setGrants((prev) => ({
      ...prev,
      [key]: { ...prev[key], granted: checked },
    }));
  }

  function setScope(key: string, scope: "own" | "all") {
    setGrants((prev) => ({ ...prev, [key]: { ...prev[key], scope } }));
  }

  function onSubmit() {
    setError(null);
    const permissions: PermissionInput[] = permissionsCatalog.map((p) => ({
      key: p.key,
      granted: grants[p.key]?.granted ?? false,
      scope: p.is_scopable ? (grants[p.key]?.scope ?? "own") : null,
    }));

    startTransition(async () => {
      const result = await saveRole(orgId, role?.id ?? null, name, permissions);
      if (result.error) {
        setError(result.error);
        return;
      }
      setOpen(false);
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{role ? "ویرایش نقش" : "نقش جدید"}</DialogTitle>
          <DialogDescription>
            {isSystem
              ? "این نقش سیستمی است و قابل ویرایش نیست."
              : "دسترسی‌های این نقش را انتخاب کنید."}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="role-name">نام نقش</Label>
            <Input
              id="role-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              disabled={isSystem}
              placeholder="مثلاً کارشناس پشتیبانی"
            />
          </div>

          <div className="grid gap-3">
            <Label>دسترسی‌ها</Label>
            {permissionsCatalog.map((p) => (
              <div key={p.key} className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <Checkbox
                    id={`perm-${p.key}`}
                    checked={grants[p.key]?.granted ?? false}
                    disabled={isSystem}
                    onCheckedChange={(checked) => toggle(p.key, checked === true)}
                  />
                  <Label htmlFor={`perm-${p.key}`} className="font-normal">
                    {p.label_fa}
                  </Label>
                </div>
                {p.is_scopable && grants[p.key]?.granted && (
                  <Select
                    value={grants[p.key]?.scope ?? "own"}
                    onValueChange={(v) => setScope(p.key, v as "own" | "all")}
                    disabled={isSystem}
                  >
                    <SelectTrigger className="w-32" size="sm">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="own">فقط خودم</SelectItem>
                      <SelectItem value="all">همه</SelectItem>
                    </SelectContent>
                  </Select>
                )}
              </div>
            ))}
          </div>

          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>

        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending || isSystem}>
            ذخیره
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
