"use client";

import { useActionState } from "react";
import { createOrganization } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

const initialState = { error: undefined as string | undefined };

export default function NewOrgPage() {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState, formData: FormData) => {
      const result = await createOrganization(formData);
      return result ?? initialState;
    },
    initialState,
  );

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>ساخت سازمان جدید</CardTitle>
          <CardDescription>
            شما مالک این سازمان خواهید بود و می‌توانید بقیه‌ی اعضا را دعوت
            کنید.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action={formAction} className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="name">نام سازمان</Label>
              <Input id="name" name="name" placeholder="مثلاً وایزر" required />
            </div>
            {state.error && (
              <p className="text-destructive text-sm">{state.error}</p>
            )}
            <Button type="submit" disabled={isPending} className="w-full">
              ساخت سازمان
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
