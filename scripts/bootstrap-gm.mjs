import { createClient } from "@supabase/supabase-js";

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

async function findUserByEmail(admin, email) {
  let page = 1;
  const perPage = 1000;

  while (true) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) {
      throw new Error("Unable to look up the requested Auth user.");
    }

    const user = data.users.find((candidate) => candidate.email?.toLowerCase() === email);
    if (user) {
      return user;
    }

    if (data.users.length < perPage) {
      return null;
    }
    page += 1;
  }
}

async function main() {
  const url = requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL");
  const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  const email = requiredEnvironment("BOOTSTRAP_GM_EMAIL").toLowerCase();
  const password = process.env.BOOTSTRAP_GM_PASSWORD;
  const displayName = process.env.BOOTSTRAP_GM_DISPLAY_NAME?.trim() || null;

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let user = await findUserByEmail(admin, email);
  if (!user) {
    if (!password || password.length < 8) {
      throw new Error(
        "BOOTSTRAP_GM_PASSWORD (at least 8 characters) is required when creating the first GM.",
      );
    }

    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (error || !data.user) {
      throw new Error("Unable to create the requested Auth user.");
    }
    user = data.user;
  }

  const { data: profile, error: profileLookupError } = await admin
    .from("user_profiles")
    .select("id, role, owner_id")
    .eq("id", user.id)
    .maybeSingle();
  if (profileLookupError) {
    throw new Error("Unable to look up the requested user profile.");
  }

  if (profile?.role === "GM") {
    console.log("Bootstrap complete: the requested account is already a GM.");
    return;
  }

  const promotion = { role: "GM", owner_id: null };
  if (displayName) {
    promotion.display_name = displayName;
  }

  const { error: profileWriteError } = profile
    ? await admin.from("user_profiles").update(promotion).eq("id", user.id)
    : await admin.from("user_profiles").insert({
        id: user.id,
        role: "GM",
        owner_id: null,
        display_name: displayName,
      });

  if (profileWriteError) {
    throw new Error("Unable to create or promote the requested GM profile.");
  }

  console.log("Bootstrap complete: the requested account is now a GM.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "GM bootstrap failed.");
  process.exitCode = 1;
});
