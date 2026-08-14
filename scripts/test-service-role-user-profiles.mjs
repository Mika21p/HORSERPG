import { createClient } from "@supabase/supabase-js";

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function createAuthUser(admin, email, password) {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !data.user) {
    throw new Error("Unable to create local Auth fixture.");
  }
  return data.user;
}

async function signIn(url, publishableKey, email, password) {
  const client = createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) {
    throw new Error("Unable to sign in local Auth fixture.");
  }
  return client;
}

async function main() {
  const url = requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL");
  const publishableKey = requiredEnvironment("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  const suffix = `${Date.now()}-${process.pid}`;
  const gmEmail = `gm-${suffix}@horserpg.test`;
  const playerEmail = `player-${suffix}@horserpg.test`;
  const targetEmail = `target-${suffix}@horserpg.test`;
  const password = "LocalTestPassword2026!";

  const service = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const gmUser = await createAuthUser(service, gmEmail, password);
  const { error: gmProfileError } = await service.from("user_profiles").insert({
    id: gmUser.id,
    role: "GM",
    owner_id: null,
    display_name: "Local GM",
  });
  assert(!gmProfileError, "service_role INSERT user_profiles failed.");

  const { data: selectedGM, error: selectError } = await service
    .from("user_profiles")
    .select("id, role")
    .eq("id", gmUser.id)
    .single();
  assert(!selectError && selectedGM?.role === "GM", "service_role SELECT user_profiles failed.");

  const { data: updatedGM, error: updateError } = await service
    .from("user_profiles")
    .update({ display_name: "Local GM Updated" })
    .eq("id", gmUser.id)
    .select("display_name")
    .single();
  assert(!updateError && updatedGM?.display_name === "Local GM Updated", "service_role UPDATE user_profiles failed.");

  const { error: deleteError } = await service
    .from("user_profiles")
    .delete()
    .eq("id", gmUser.id);
  assert(deleteError, "service_role DELETE user_profiles unexpectedly succeeded.");

  const gmClient = await signIn(url, publishableKey, gmEmail, password);
  const { data: owner, error: ownerError } = await gmClient
    .from("owners")
    .insert({ display_name: `Local Test Owner ${suffix}`, initial_funds: "1000" })
    .select("id")
    .single();
  assert(!ownerError && owner, "Authenticated GM could not create Owner.");

  const playerUser = await createAuthUser(service, playerEmail, password);
  const { error: playerProfileError } = await service.from("user_profiles").insert({
    id: playerUser.id,
    role: "PLAYER",
    owner_id: owner.id,
    display_name: "Local PLAYER",
  });
  assert(!playerProfileError, "service_role INSERT PLAYER profile failed.");

  const playerClient = await signIn(url, publishableKey, playerEmail, password);
  const { data: playerProfiles, error: playerSelectError } = await playerClient
    .from("user_profiles")
    .select("id, role, owner_id");
  assert(
    !playerSelectError && playerProfiles?.length === 1 && playerProfiles[0].id === playerUser.id,
    "PLAYER did not remain limited to its own profile.",
  );

  const targetUser = await createAuthUser(service, targetEmail, password);
  const { error: playerInsertError } = await playerClient.from("user_profiles").insert({
    id: targetUser.id,
    role: "GM",
    owner_id: null,
  });
  assert(playerInsertError, "PLAYER unexpectedly created a user profile.");

  const { data: playerUpdateRows, error: playerUpdateError } = await playerClient
    .from("user_profiles")
    .update({ display_name: "PLAYER mutation attempt" })
    .eq("id", playerUser.id)
    .select("id");
  assert(
    playerUpdateError || playerUpdateRows?.length === 0,
    "PLAYER unexpectedly updated its profile.",
  );

  const { data: gmProfiles, error: gmSelectError } = await gmClient
    .from("user_profiles")
    .select("id")
    .in("id", [gmUser.id, playerUser.id]);
  assert(!gmSelectError && gmProfiles?.length === 2, "GM lost profile read access.");

  const { data: gmUpdatedPlayer, error: gmUpdateError } = await gmClient
    .from("user_profiles")
    .update({ display_name: "GM regression check" })
    .eq("id", playerUser.id)
    .select("display_name")
    .single();
  assert(
    !gmUpdateError && gmUpdatedPlayer?.display_name === "GM regression check",
    "GM lost profile update access.",
  );

  console.log("service_role SELECT user_profiles: PASS");
  console.log("service_role INSERT user_profiles: PASS");
  console.log("service_role UPDATE user_profiles: PASS");
  console.log("service_role DELETE user_profiles: PASS (rejected)");
  console.log("service_role GM profile creation: PASS");
  console.log("service_role PLAYER profile creation: PASS");
  console.log("authenticated PLAYER RLS regression: PASS");
  console.log("authenticated GM RLS regression: PASS");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Permission test failed.");
  process.exitCode = 1;
});
