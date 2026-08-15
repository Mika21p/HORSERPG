import "server-only";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export type AppRole = "PLAYER" | "GM";

export type CurrentProfile = {
  id: string;
  role: AppRole;
  owner_id: string | null;
  display_name: string | null;
};

export async function getCurrentSession() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { supabase, user: null, profile: null };
  }

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("id, role, owner_id, display_name")
    .eq("id", user.id)
    .maybeSingle();

  return {
    supabase,
    user,
    profile: (profile as CurrentProfile | null) ?? null,
  };
}

export async function requireUser() {
  const session = await getCurrentSession();

  if (!session.user) {
    redirect("/login");
  }

  return session as typeof session & { user: NonNullable<typeof session.user> };
}

/** Server-side authorization for PLAYER-only actions and private projections. */
export async function requirePlayer() {
  const session = await requireUser();

  if (session.profile?.role !== "PLAYER" || !session.profile.owner_id) {
    redirect("/");
  }

  return session as typeof session & {
    profile: CurrentProfile & { role: "PLAYER"; owner_id: string };
  };
}

/** Server-side authorization for pages and every privileged Server Action. */
export async function requireGM() {
  const session = await requireUser();

  if (session.profile?.role !== "GM") {
    redirect("/");
  }

  return session as typeof session & { profile: CurrentProfile & { role: "GM" } };
}
