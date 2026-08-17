import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Supabase's local site_url (and therefore every invite/magic-link
  // email) points at 127.0.0.1:3000. Without this, Next 16's dev server
  // treats that as a cross-origin request and 403s every JS chunk --
  // including the Supabase client itself -- so the page never hydrates.
  allowedDevOrigins: ["127.0.0.1", "localhost"],
};

export default nextConfig;
