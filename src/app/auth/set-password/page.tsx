"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";

import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";

const schema = z
  .object({
    password: z.string().min(8, "رمز عبور باید حداقل ۸ کاراکتر باشد"),
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "رمز عبور و تکرار آن یکسان نیستند",
    path: ["confirmPassword"],
  });

type FormValues = z.infer<typeof schema>;

type SessionStatus = "checking" | "ready" | "invalid";

const EXPIRED_LINK_MESSAGE =
  "این لینک دعوت قبلاً استفاده شده یا منقضی شده است. از فرد دعوت‌کننده بخواهید دوباره برایتان دعوت‌نامه بفرستد.";

// Supabase's invite/magic-link email points at GoTrue's own /verify
// endpoint, which verifies the token itself and redirects back here with
// the session tokens in the URL *hash fragment*
// (#access_token=...&refresh_token=...) rather than a query param -- a
// fragment is never sent to the server, so this has to run client-side.
// GoTrue reports a used/expired link the same way, but with
// #error=...&error_description=... instead.
function useSessionFromEmailLink() {
  const [status, setStatus] = useState<SessionStatus>("checking");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    function finish(next: SessionStatus, nextMessage: string | null = null) {
      if (cancelled) return;
      setMessage(nextMessage);
      setStatus(next);
    }

    async function run() {
      try {
        const supabase = createClient();
        // Read the hash but DON'T clear it yet -- in dev, React Strict
        // Mode runs this effect twice (mount, cleanup, mount again). If we
        // clear the hash before the async setSession() below resolves,
        // the second run reads an already-emptied hash and wrongly
        // reports the link as expired. Clearing only after the awaited
        // call resolves means both runs see the same tokens and both
        // harmlessly reach the same "ready" outcome.
        const hash = window.location.hash.startsWith("#")
          ? window.location.hash.slice(1)
          : "";
        const hashParams = new URLSearchParams(hash);

        if (hashParams.get("error")) {
          window.history.replaceState(null, "", window.location.pathname);
          finish("invalid", EXPIRED_LINK_MESSAGE);
          return;
        }

        const accessToken = hashParams.get("access_token");
        const refreshToken = hashParams.get("refresh_token");

        if (accessToken && refreshToken) {
          const { error } = await supabase.auth.setSession({
            access_token: accessToken,
            refresh_token: refreshToken,
          });
          window.history.replaceState(null, "", window.location.pathname);
          finish(error ? "invalid" : "ready", error ? EXPIRED_LINK_MESSAGE : null);
          return;
        }

        const {
          data: { session },
        } = await supabase.auth.getSession();
        finish(session ? "ready" : "invalid", session ? null : EXPIRED_LINK_MESSAGE);
      } catch {
        finish("invalid", "خطایی رخ داد. دوباره تلاش کنید.");
      }
    }

    run();
    return () => {
      cancelled = true;
    };
  }, []);

  return { status, message };
}

export default function SetPasswordPage() {
  const router = useRouter();
  const { status, message } = useSessionFromEmailLink();
  const [serverError, setServerError] = useState<string | null>(null);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { password: "", confirmPassword: "" },
  });

  async function onSubmit(values: FormValues) {
    setServerError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.updateUser({
      password: values.password,
    });

    if (error) {
      setServerError("تعیین رمز عبور انجام نشد. دوباره تلاش کنید.");
      return;
    }

    router.push("/orgs");
    router.refresh();
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>تعیین رمز عبور</CardTitle>
          <CardDescription>
            به این سازمان دعوت شده‌اید. برای ادامه، یک رمز عبور برای حساب
            خود تعیین کنید.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {status === "checking" && (
            <p className="text-muted-foreground text-sm">
              در حال بررسی لینک دعوت...
            </p>
          )}

          {status === "invalid" && (
            <p className="text-destructive text-sm">{message}</p>
          )}

          {status === "ready" && (
            <Form {...form}>
              <form
                onSubmit={form.handleSubmit(onSubmit)}
                className="grid gap-4"
              >
                <FormField
                  control={form.control}
                  name="password"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>رمز عبور جدید</FormLabel>
                      <FormControl>
                        <Input type="password" dir="ltr" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="confirmPassword"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>تکرار رمز عبور</FormLabel>
                      <FormControl>
                        <Input type="password" dir="ltr" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                {serverError && (
                  <p className="text-destructive text-sm">{serverError}</p>
                )}
                <Button
                  type="submit"
                  disabled={form.formState.isSubmitting}
                  className="w-full"
                >
                  تایید و ورود
                </Button>
              </form>
            </Form>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
