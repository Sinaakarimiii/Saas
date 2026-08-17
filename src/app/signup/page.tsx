"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
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

const schema = z.object({
  fullName: z.string().min(2, "نام باید حداقل ۲ حرف باشد"),
  email: z.string().email("ایمیل معتبر نیست"),
  password: z.string().min(8, "رمز عبور باید حداقل ۸ کاراکتر باشد"),
});

type FormValues = z.infer<typeof schema>;

export default function SignupPage() {
  const router = useRouter();
  const [serverError, setServerError] = useState<string | null>(null);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { fullName: "", email: "", password: "" },
  });

  async function onSubmit(values: FormValues) {
    setServerError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signUp({
      email: values.email,
      password: values.password,
      options: { data: { full_name: values.fullName } },
    });

    if (error) {
      setServerError(
        error.message === "User already registered"
          ? "این ایمیل قبلاً ثبت‌نام کرده — وارد شوید."
          : "ثبت‌نام انجام نشد. دوباره تلاش کنید.",
      );
      return;
    }

    router.push("/orgs");
    router.refresh();
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>ساخت حساب کاربری</CardTitle>
          <CardDescription>
            برای شروع، یک حساب کاربری جدید بسازید.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form {...form}>
            <form
              onSubmit={form.handleSubmit(onSubmit)}
              className="grid gap-4"
            >
              <FormField
                control={form.control}
                name="fullName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>نام و نام‌خانوادگی</FormLabel>
                    <FormControl>
                      <Input placeholder="مثلاً سینا کریمی" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="email"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>ایمیل</FormLabel>
                    <FormControl>
                      <Input
                        type="email"
                        dir="ltr"
                        placeholder="you@example.com"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="password"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>رمز عبور</FormLabel>
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
                ثبت‌نام
              </Button>
            </form>
          </Form>
          <p className="text-muted-foreground mt-4 text-center text-sm">
            حساب دارید؟{" "}
            <Link href="/login" className="text-primary underline">
              وارد شوید
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
