import "server-only";

import { createClient } from "@supabase/supabase-js";

function getAdminEnvironment() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing server-only Supabase admin environment variables. Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY outside browser code.",
    );
  }

  return { url, serviceRoleKey };
}

/**
 * Creates a server-only client for the two operations that require Supabase
 * Auth administration. Never import this module from a Client Component.
 */
export function createAdminClient() {
  const { url, serviceRoleKey } = getAdminEnvironment();

  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
