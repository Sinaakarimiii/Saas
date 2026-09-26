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

type Scope = "own" | "all" | "team";

const SCOPE_LABELS: Record<Scope, string> = {
  own: "فقط خودم",
  all: "همه",
  team: "زیرمجموعه‌ی من",
};

type PermissionCatalogItem = {
  key: string;
  label_fa: string;
  scope_options: string[];
};

type ExistingRole = {
  id: string;
  name: string;
  isSystem: boolean;
  managementRank: number;
  grants: Record<string, Scope | null>;
};

export function RoleEditorDialog({
  orgId,
  permissionsCatalog,
  role,
  maxRank,
  trigger,
}: {
  orgId: string;
  permissionsCatalog: PermissionCatalogItem[];
  role?: ExistingRole;
  maxRank: number;
  trigger: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(role?.name ?? "");
  const [managementRank, setManagementRank] = useState(String(role?.managementRank ?? Math.max(0, maxRank - 1)));
  const [grants, setGrants] = useState<Record<string, { granted: boolean; scope: Scope | null }>>(
    () => {
      const initial: Record<string, { granted: boolean; scope: Scope | null }> = {};
      for (const p of permissionsCatalog) {
        const existingScope = role?.grants[p.key];
        const isScopable = p.scope_options.length > 0;
        initial[p.key] = {
          granted: role ? p.key in role.grants : false,
          scope: existingScope ?? (isScopable ? (p.scope_options[0] as Scope) : null),
        };
      }
      return initial;
    },
  );
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const isSystem = !!role?.isSystem;

  function toggle(key: string, checked: boolean) {
    setGrants((prev) => ({
      ...prev,
      [key]: { ...prev[key], granted: checked },
    }));
  }

  function setScope(key: string, scope: Scope) {
    setGrants((prev) => ({ ...prev, [key]: { ...prev[key], scope } }));
  }

  function onSubmit() {
    setError(null);
    const permissions: PermissionInput[] = permissionsCatalog.map((p) => {
      const isScopable = p.scope_options.length > 0;
      return {
        key: p.key,
        granted: grants[p.key]?.granted ?? false,
        scope: isScopable ? (grants[p.key]?.scope ?? (p.scope_options[0] as Scope)) : null,
      };
    });

    startTransition(async () => {
      const result = await saveRole(orgId, role?.id ?? null, name, Number(managementRank), permissions);
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

          <div className="grid gap-2">
            <Label htmlFor="role-rank">سطح مدیریتی</Label>
            <Input
              id="role-rank"
              type="number"
              min="0"
              max={Math.max(0, maxRank - 1)}
              value={managementRank}
              onChange={(e) => setManagementRank(e.target.value)}
              disabled={isSystem}
            />
            <p className="text-muted-foreground text-xs">فقط نقش‌های با سطح پایین‌تر قابل مدیریت هستند.</p>
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
                {p.scope_options.length > 0 && grants[p.key]?.granted && (
                  <Select
                    value={grants[p.key]?.scope ?? p.scope_options[0]}
                    onValueChange={(v) => setScope(p.key, v as Scope)}
                    disabled={isSystem}
                  >
                    <SelectTrigger className="w-36" size="sm">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {p.scope_options.map((opt) => (
                        <SelectItem key={opt} value={opt}>
                          {SCOPE_LABELS[opt as Scope]}
                        </SelectItem>
                      ))}
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
