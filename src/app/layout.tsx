import type { Metadata } from "next";
import { Vazirmatn } from "next/font/google";
import { ThemeProvider } from "next-themes";
import { Toaster } from "@/components/ui/sonner";
import "./globals.css";

const vazirmatn = Vazirmatn({
  variable: "--font-sans",
  subsets: ["arabic", "latin"],
});

export const metadata: Metadata = {
  title: "پلتفرم اتوماسیون سازمانی",
  description: "پلتفرم چندسازمانی اتوماسیون کارهای سازمانی",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="fa"
      dir="rtl"
      className={`${vazirmatn.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <body className="min-h-full flex flex-col">
        <ThemeProvider attribute={["class", "data-theme"]} defaultTheme="system" enableSystem>
          {children}
          <Toaster position="top-center" dir="rtl" />
        </ThemeProvider>
      </body>
    </html>
  );
}
