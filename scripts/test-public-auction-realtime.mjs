/*
 * Local-only Realtime integration verification for HorseRPG v0.3-A.
 *
 * Required environment variables are intentionally supplied by the caller
 * from `npx supabase status -o env`; no key is stored in this repository.
 */

import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

const localUrl = process.env.HORSE_RPG_LOCAL_SUPABASE_URL;
const localPublishableKey = process.env.HORSE_RPG_LOCAL_SUPABASE_PUBLISHABLE_KEY;
const localServiceRoleKey = process.env.HORSE_RPG_LOCAL_SERVICE_ROLE_KEY;

if (!localUrl || !localPublishableKey || !localServiceRoleKey) {
  throw new Error(
    "Missing HORSE_RPG_LOCAL_SUPABASE_URL, HORSE_RPG_LOCAL_SUPABASE_PUBLISHABLE_KEY, or HORSE_RPG_LOCAL_SERVICE_ROLE_KEY.",
  );
}

const fixture = {
  ownerAId: "00000000-0000-0000-0000-000000009101",
  ownerBId: "00000000-0000-0000-0000-000000009102",
  horseId: "00000000-0000-0000-0000-000000009301",
  futureHorseId: "00000000-0000-0000-0000-000000009302",
};
const password = `Realtime-${randomUUID()}-Local-Test`;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function unwrap(result, action) {
  if (result.error) {
    throw new Error(`${action}: ${result.error.message}`);
  }
  return result.data;
}

function asRow(value, action) {
  const row = Array.isArray(value) ? value[0] : value;
  if (!row) {
    throw new Error(`${action}: RPC returned no row.`);
  }
  return row;
}

function pause(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function createBrowserLikeClient() {
  return createClient(localUrl, localPublishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function createTestUser(admin, email, role, ownerId) {
  const created = unwrap(
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    }),
    `create local Auth user ${email}`,
  );

  unwrap(
    await admin.from("user_profiles").insert({
      id: created.user.id,
      role,
      owner_id: ownerId,
      display_name: `Realtime ${role}`,
    }),
    `create ${role} profile`,
  );

  return created.user;
}

async function signIn(email) {
  const client = createBrowserLikeClient();
  unwrap(await client.auth.signInWithPassword({ email, password }), `sign in ${email}`);
  await client.realtime.setAuth();
  return client;
}

async function subscribe(client, topic, label) {
  const events = [];
  const clientBusinessMessages = [];

  const channel = client
    .channel(topic, { config: { private: true } })
    .on("broadcast", { event: "auction_state_changed" }, ({ payload }) => {
      events.push(payload);
    })
    .on("broadcast", { event: "client_business_message" }, ({ payload }) => {
      clientBusinessMessages.push(payload);
    });

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`${label} did not subscribe within 10 seconds.`)), 10_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        clearTimeout(timeout);
        reject(new Error(`${label} private subscription failed with ${status}.`));
      }
    });
  });

  return { channel, events, clientBusinessMessages };
}

async function expectSubscriptionDenied(client, topic, label) {
  const channel = client.channel(topic, { config: { private: true } });
  const result = await new Promise((resolve) => {
    const timeout = setTimeout(() => resolve("TIMED_OUT"), 4_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED" || status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        clearTimeout(timeout);
        resolve(status);
      }
    });
  });
  await client.removeChannel(channel);
  assert(result !== "SUBSCRIBED", `${label} unexpectedly subscribed to ${topic}.`);
}

async function waitForEvent(subscribers, predicate, label) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 10_000) {
    if (subscribers.every(({ events }) => events.some(predicate))) {
      return;
    }
    await pause(40);
  }

  const received = subscribers.map(({ events }) => events.map((event) => event.kind).join(",") || "none").join(" | ");
  throw new Error(`${label}: not all subscribers received the expected broadcast. Received: ${received}`);
}

async function readAtomicSnapshot(client, eventId, action) {
  const snapshot = unwrap(
    await client.rpc("get_public_auction_snapshot", { p_event_id: eventId }),
    action,
  );
  assert(snapshot, `${action}: authenticated caller did not receive an Event snapshot.`);
  return snapshot;
}

function assertSnapshotConsistent(snapshot) {
  assert(!JSON.stringify(snapshot).includes("VOIDED"), "Snapshot exposed a VOIDED historical Round.");
  if (!snapshot.currentRound) {
    assert(snapshot.bids.length === 0, "Snapshot exposed Bids without a current Round.");
    return;
  }

  if (snapshot.currentRound.current_price !== null) {
    const currentPrice = BigInt(snapshot.currentRound.current_price);
    let leadingBid = null;
    for (const bid of snapshot.bids) {
      assert(BigInt(bid.amount) <= currentPrice, "Snapshot combined a stale Round price with a newer accepted Bid.");
      if (!leadingBid || BigInt(bid.amount) > BigInt(leadingBid.amount)) {
        leadingBid = bid;
      }
    }
    if (leadingBid) {
      assert(
        BigInt(leadingBid.amount) === currentPrice
          && snapshot.currentRound.current_winner_owner_id === leadingBid.owner?.id,
        "Snapshot combined a Round winner with Bids from another state point.",
      );
    }
  }
}

async function main() {
  const runId = randomUUID().slice(0, 8);
  const emails = {
    gm: `realtime-gm-${runId}@example.test`,
    playerA: `realtime-player-a-${runId}@example.test`,
    playerB: `realtime-player-b-${runId}@example.test`,
  };
  const admin = createClient(localUrl, localServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  await createTestUser(admin, emails.gm, "GM", null);
  await createTestUser(admin, emails.playerA, "PLAYER", fixture.ownerAId);
  await createTestUser(admin, emails.playerB, "PLAYER", fixture.ownerBId);

  const [gm, playerA, playerB] = await Promise.all([
    signIn(emails.gm),
    signIn(emails.playerA),
    signIn(emails.playerB),
  ]);

  // Authorization is channel/topic based. Anon and an authenticated user on
  // a non-auction namespace must both be denied before business data exists.
  await expectSubscriptionDenied(createBrowserLikeClient(), "public-auction:local-anon", "anon");
  await expectSubscriptionDenied(playerA, "private-owner:other", "authenticated user outside auction namespace");

  const event = asRow(
    unwrap(
      await gm.rpc("create_public_auction_event", {
        p_wp_year: 2099,
        p_name: "Realtime local integration event",
        p_minimum_increment: 100000,
      }),
      "GM creates public-auction Event",
    ),
    "GM creates public-auction Event",
  );
  const lot = asRow(
    unwrap(
      await gm.rpc("create_public_auction_lot", {
        p_event_id: event.id,
        p_horse_id: fixture.horseId,
        p_lot_number: 1,
        p_starting_price: 10000000,
        p_evaluation_value: 20000000,
      }),
      "GM creates public-auction Lot",
    ),
    "GM creates public-auction Lot",
  );
  const futureLot = asRow(
    unwrap(
      await gm.rpc("create_public_auction_lot", {
        p_event_id: event.id,
        p_horse_id: fixture.futureHorseId,
        p_lot_number: 2,
        p_starting_price: 10000000,
        p_evaluation_value: 20000000,
      }),
      "GM creates future public-auction Lot",
    ),
    "GM creates future public-auction Lot",
  );

  for (let slot = 1; slot <= 5; slot += 1) {
    unwrap(
      await gm.rpc("upsert_public_auction_lot_review", {
        p_lot_id: lot.id,
        p_slot: slot,
        p_stars: 4,
        p_comment: `Realtime review ${slot}`,
      }),
      `GM writes review ${slot}`,
    );
  }
  unwrap(
    await gm.rpc("set_public_auction_event_status", {
      p_event_id: event.id,
      p_status: "OPEN",
    }),
    "GM opens public-auction Event",
  );

  // Snapshot-first does not need a Realtime connection. It is caller-RLS
  // scoped, shows the Event, and cannot reveal the queued future Lot.
  const anonymousSnapshot = await createBrowserLikeClient().rpc("get_public_auction_snapshot", {
    p_event_id: event.id,
  });
  assert(anonymousSnapshot.error, "anon called the public-auction Snapshot RPC.");
  let state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads initial atomic Snapshot without Realtime");
  assert(state.currentLot === null && state.currentRound === null && state.bids.length === 0, "Initial Snapshot exposed a queued Lot or Round.");
  assert(!JSON.stringify(state).includes(futureLot.id), "Initial Snapshot exposed the future Lot.");

  const topic = `public-auction:${event.id}`;
  const subscribers = await Promise.all([
    subscribe(gm, topic, "GM"),
    subscribe(playerA, topic, "PLAYER A"),
    subscribe(playerB, topic, "PLAYER B"),
  ]);

  // The private channel has no client broadcast permission.
  await subscribers[1].channel.send({
    type: "broadcast",
    event: "client_business_message",
    payload: { should_not_send: true },
  });
  await pause(500);
  assert(
    subscribers.every(({ clientBusinessMessages }) => clientBusinessMessages.length === 0),
    "Authenticated client broadcast reached a public-auction Channel despite the absence of an INSERT RLS policy.",
  );

  // This is the second authoritative read after the private channel joins.
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER re-reads Snapshot after Realtime subscribe");
  assert(state.currentLot === null, "Second Snapshot before Reveal exposed a queued Lot.");

  unwrap(await gm.rpc("reveal_public_auction_lot", { p_lot_id: lot.id }), "GM reveals Lot");
  await waitForEvent(subscribers, (eventPayload) => eventPayload.kind === "LOT_REVEALED", "Reveal notification");
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads revealed atomic Snapshot");
  assert(state.currentLot?.revealed_at, "Reveal did not become visible after the authoritative reread.");
  assert(state.currentLot?.id === lot.id && !JSON.stringify(state).includes(futureLot.id), "Snapshot exposed a future Lot after the first Reveal.");

  unwrap(await gm.rpc("open_public_auction_lot", { p_lot_id: lot.id }), "GM opens Lot");
  await waitForEvent(
    subscribers,
    (eventPayload) => eventPayload.kind === "LOT_CHANGED" || eventPayload.kind === "ROUND_CHANGED",
    "Open notification",
  );
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads opened atomic Snapshot");
  assert(state.currentRound?.status === "OPEN_WAITING", "Opened Lot did not expose an OPEN_WAITING Round.");
  assert(state.currentRound?.no_bid_deadline, "Opened Lot did not expose a no-bid deadline.");
  assert(state.currentRound?.close_at === null, "Opened Lot incorrectly exposed a bidding close time before the first Bid.");

  // Session A repeatedly reads the one-statement Snapshot while Session B and
  // GM drive bids, settlement, and rollback below. Every observed state must
  // be self-consistent; a mixed multi-query read would fail this check.
  let keepReadingSnapshots = true;
  let snapshotReaderFailure = null;
  let snapshotsObserved = 0;
  const snapshotReader = (async () => {
    while (keepReadingSnapshots) {
      try {
        const concurrentSnapshot = await readAtomicSnapshot(playerA, event.id, "concurrent Snapshot reader");
        assertSnapshotConsistent(concurrentSnapshot);
        snapshotsObserved += 1;
      } catch (error) {
        snapshotReaderFailure = error;
        return;
      }
      await pause(25);
    }
  })();

  // PLAYER B intentionally misses A's first bid; a new private subscription
  // must use a fresh authoritative read rather than depend on replay.
  await playerB.removeChannel(subscribers[2].channel);
  unwrap(
    await playerA.rpc("submit_public_auction_bid", {
      p_lot_id: lot.id,
      p_expected_round_id: state.currentRound.id,
      p_amount: 10000000,
      p_request_id: randomUUID(),
    }),
    "PLAYER A first Bid",
  );
  await waitForEvent(subscribers.slice(0, 2), (eventPayload) => eventPayload.kind === "BID_ACCEPTED", "First Bid notification");

  const reconnectedPlayerB = await subscribe(playerB, topic, "PLAYER B reconnect");
  state = await readAtomicSnapshot(playerB, event.id, "PLAYER B reads Snapshot after reconnect");
  assert(
    String(state.currentRound?.current_price) === "10000000" && state.currentRound.current_winner_owner_id === fixture.ownerAId,
    "PLAYER B reconnect did not recover A's first Bid from the authoritative state.",
  );

  unwrap(
    await playerB.rpc("submit_public_auction_bid", {
      p_lot_id: lot.id,
      p_expected_round_id: state.currentRound.id,
      p_amount: 10100000,
      p_request_id: randomUUID(),
    }),
    "PLAYER B higher Bid",
  );
  await waitForEvent(
    [subscribers[0], subscribers[1], reconnectedPlayerB],
    (eventPayload) => eventPayload.kind === "BID_ACCEPTED",
    "Higher Bid notification",
  );
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads post-bid atomic Snapshot");
  assert(
    String(state.currentRound?.current_price) === "10100000" && state.currentRound.current_winner_owner_id === fixture.ownerBId && state.bids.length === 2,
    "Higher Bid did not refresh price, winner, and public Bid history.",
  );

  // The database, not Realtime, decides that the ten-second clock has ended.
  await pause(11_000);
  const lateBid = await playerA.rpc("submit_public_auction_bid", {
    p_lot_id: lot.id,
    p_expected_round_id: state.currentRound.id,
    p_amount: 10200000,
    p_request_id: randomUUID(),
  });
  assert(lateBid.error, "A Bid was accepted after the server-side ten-second deadline.");

  await playerB.removeChannel(reconnectedPlayerB.channel);
  unwrap(await gm.rpc("settle_public_auction_lot", { p_lot_id: lot.id, p_reason: "Realtime local settlement" }), "GM settles Lot");
  await waitForEvent(
    subscribers.slice(0, 2),
    (eventPayload) => eventPayload.kind === "LOT_CHANGED" || eventPayload.kind === "ROUND_CHANGED",
    "Settlement notification",
  );
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads settled atomic Snapshot");
  assert(
    state.currentLot?.status === "SOLD" && state.currentRound?.status === "SOLD" && state.settlement?.winner_owner_id === fixture.ownerBId,
    "Settlement did not refresh public Lot, Round, and final settlement state.",
  );
  const internalSettlementRead = unwrap(
    await playerA.from("public_auction_settlements").select("id").eq("lot_id", lot.id),
    "PLAYER direct internal settlement read",
  );
  assert(internalSettlementRead.length === 0, "PLAYER read an internal public-auction settlement row.");

  const rollbackRequest = asRow(
    unwrap(
      await gm.rpc("request_public_auction_emergency_rollback", {
        p_lot_id: lot.id,
        p_reason: "Realtime local rollback verification",
      }),
      "GM requests emergency rollback",
    ),
    "GM requests emergency rollback",
  );
  unwrap(
    await gm.rpc("confirm_public_auction_emergency_rollback", {
      p_rollback_request_id: rollbackRequest.id,
      p_confirmation: "ROLLBACK LOT 001",
    }),
    "GM confirms emergency rollback",
  );
  await waitForEvent(
    subscribers.slice(0, 2),
    (eventPayload) => eventPayload.kind === "LOT_CHANGED",
    "Emergency rollback notification",
  );
  state = await readAtomicSnapshot(playerA, event.id, "PLAYER reads rollback atomic Snapshot");
  assert(
    state.currentLot?.status === "QUEUED" && state.currentRound?.status === "QUEUED" && state.currentRound.current_price === null && state.currentRound.current_winner_owner_id === null,
    "Emergency rollback did not refresh the new clean current Round.",
  );
  assertSnapshotConsistent(state);
  const serializedRollbackSnapshot = JSON.stringify(state);
  assert(
    !serializedRollbackSnapshot.includes("Realtime local rollback verification")
      && !serializedRollbackSnapshot.includes("financial_transactions")
      && !serializedRollbackSnapshot.includes("audit_logs"),
    "Atomic Snapshot exposed rollback, financial, or audit data.",
  );
  const rollbackRead = unwrap(
    await playerA.from("public_auction_rollback_requests").select("id").eq("lot_id", lot.id),
    "PLAYER direct rollback-request read",
  );
  assert(rollbackRead.length === 0, "PLAYER read an internal emergency rollback request.");

  keepReadingSnapshots = false;
  await snapshotReader;
  assert(!snapshotReaderFailure, `Concurrent Snapshot reader failed: ${snapshotReaderFailure?.message ?? "unknown error"}`);
  assert(snapshotsObserved > 5, "Concurrent Snapshot reader did not observe the live auction state.");

  await Promise.all([
    gm.removeChannel(subscribers[0].channel),
    playerA.removeChannel(subscribers[1].channel),
  ]);

  console.log("PASS public-auction Realtime integration: private authorization, Broadcast, reconnect, deadline, settlement, and rollback.");
}

main().catch((error) => {
  console.error(`FAIL public-auction Realtime integration: ${error.message}`);
  process.exitCode = 1;
});
