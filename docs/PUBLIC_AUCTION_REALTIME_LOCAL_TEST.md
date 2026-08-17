# Public Auction Realtime local test

This development-only procedure verifies the v0.3-A broadcast notification and
atomic authoritative snapshot design without touching Production.

1. Start the local Supabase stack, reset the local database, and apply every migration.
2. Run the existing Core, Foal Trade, Owner Funds, and Public Auction SQL suites, followed by `supabase/tests/public_auction_realtime_v0_3.sql`.
3. Load `supabase/tests/public_auction_realtime_fixture_v0_3.sql` into the local database.
4. Export the local URL, publishable key, and service-role key from the local Supabase status only for the test process, then run `node scripts/test-public-auction-realtime.mjs`.
5. Reset the local database again to remove its test users and fixture data.

For a visual multi-browser check, run the local Next server and sign in as an existing local PLAYER or GM. Visit:

`/dev/public-auction-realtime?eventId=<event UUID>`

Open the same URL in separate browser profiles for PLAYER A, PLAYER B, and GM. The development-only page shows the private channel state, received broadcast count, authoritative Snapshot refresh count, and the safe snapshot. It returns 404 outside development mode.

Expected behavior:

- an Event ID causes an immediate HTTP Snapshot request before the private
  Realtime channel has connected; this first state is still usable if the
  channel cannot connect;
- after `SUBSCRIBED`, the browser requests a second Snapshot to close the
  WebSocket-join race window;
- each Reveal, Open, accepted Bid, Settlement, and completed Emergency Rollback causes a small Broadcast notification and a Snapshot refresh;
- after a `CLOSED` Channel, the browser removes that Channel and reconnects
  with bounded backoff; it keeps its last successful Snapshot while doing so;
- switching to a different Event immediately clears the old display, aborts
  its outstanding Snapshot request, and never allows that response to paint
  over the new Event;
- a disconnected browser does not need missed messages: once it is subscribed again it immediately refreshes its Snapshot;
- the snapshot never includes an un-revealed Lot, a `VOIDED` Round, rollback details, financial transactions, or other internal records;
- if the channel is unavailable, the page reports its connection state instead of claiming to be live.
