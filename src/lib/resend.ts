import "server-only";

type SendInvitationInput = {
  to: string;
  actionLink: string;
};

export async function sendInvitationEmail({ to, actionLink }: SendInvitationInput) {
  const mailpitUrl = process.env.INVITATION_MAILPIT_URL;
  if (mailpitUrl) {
    try {
      const url = new URL(mailpitUrl);
      if (
        process.env.NODE_ENV === "production" ||
        url.protocol !== "http:" ||
        !["127.0.0.1", "localhost"].includes(url.hostname) ||
        url.username || url.password || url.search || url.hash || url.pathname !== "/"
      ) {
        return { ok: false as const, reason: "not_configured" as const, status: undefined };
      }
      const response = await fetch(new URL("/api/v1/send", url), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          From: { Email: "invites@org-platform.local", Name: "Org Platform" },
          To: [{ Email: to }],
          Subject: "دعوت به سازمان",
          HTML: `<p>برای تکمیل عضویت و تعیین رمز عبور، روی لینک زیر کلیک کنید:</p><p><a href="${actionLink}">تکمیل عضویت</a></p>`,
          Text: `برای تکمیل عضویت و تعیین رمز عبور، این لینک را باز کنید: ${actionLink}`,
        }),
        signal: AbortSignal.timeout(10000),
      });
      return response.ok
        ? { ok: true as const }
        : { ok: false as const, reason: "delivery_failed" as const, status: response.status };
    } catch {
      return { ok: false as const, reason: "delivery_failed" as const, status: undefined };
    }
  }
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM_EMAIL;
  if (!apiKey || !from) {
    return { ok: false as const, reason: "not_configured" as const, status: undefined };
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: "دعوت به سازمان",
        html: `<p>برای تکمیل عضویت و تعیین رمز عبور، روی لینک زیر کلیک کنید:</p><p><a href="${actionLink}">تکمیل عضویت</a></p>`,
      }),
    });

    return response.ok
      ? { ok: true as const }
      : { ok: false as const, reason: "delivery_failed" as const, status: response.status };
  } catch {
    return { ok: false as const, reason: "delivery_failed" as const, status: undefined };
  }
}
