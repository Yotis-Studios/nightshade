# Nightshade — Networking Architecture & v1 Structural Constraints

**Status:** SOURCE OF TRUTH. Binding on all Nightshade code.
**Author:** multiplayer architect (recon pass)
**Date:** 2026-07-27
**Scope:** v1 ships **single-player**. This document specifies how v1 must be *built* so that
authoritative-server multiplayer is a **layer added on top**, not a rewrite.

> **Read this before you write a line of gameplay code.** Section 16 ("Anti-Patterns") is the
> short version. If you only read one section, read that one — but the rest is the *why*, and
> reviewers will cite section numbers.

---

## 0. How to use this document

- Sections 1–4 are **recon**: what gn.hml actually is, measured, not guessed. Every claim
  marked **[VERIFIED]** was proven by running code against Hemlock 2.8.1 and the current
  gn.hml `main` (`22f937c`). Claims marked **[BY INSPECTION]** come from reading the source.
- Sections 5–15 are the **architecture** the team must implement in v1.
- Section 16 is the **prohibition list**.
- Sections 17–20 are budgets, phasing, and test criteria.

Nothing in this document asks you to write networking code in v1. It asks you to write
single-player code that is *shaped* like a client of a server that does not exist yet.

---

## 1. Recon: what gn.hml is

`/home/nbeerbower/Projects/gn.hml` is a Hemlock port of `gn.js` — a **WebSocket** framework with
a self-describing binary packet format. Four modules:

| File | Exports | Role |
|---|---|---|
| `src/network/packet.hml` | `Packet(net_id)` | build/load the wire format |
| `src/util/gm_convert.hml` | `determine_type`, `data_size`, `write_data_to_buffer`, `parse_data_from_buffer`, `create_buffer_from_data` | per-element type detection + codec |
| `src/network/server.hml` | `Server()` | accept loop + blocking event loop |
| `src/network/client.hml` | `Client()` | connect + background recv loop |
| `src/network/connection.hml` | `Connection(ws, server)` | server-side per-client handle |
| `src/index.hml` | re-exports all four | convenience |

It sits on `@stdlib/websocket` (libwebsockets, compiled into the Hemlock binary as `__lws_*`
builtins; requires `make stdlib` at Hemlock build time).

### 1.1 The wire format

```
frame (one WebSocket binary message) := packet+          <-- N packets may share one frame
packet := [u16 LE size][u16 LE net_id][element*]
          size = payload length = 2 (net_id) + sum(element sizes)
element := [u8 type_id][payload]
```

Type ids: `0 u8, 1 u16, 2 u32, 3 s8, 4 s16, 5 s32, 6 f16, 7 f32, 8 f64, 9 string, 10 buffer, 11 undefined`.

- **integers**: `determine_type` picks the *narrowest* type that fits the **value**. `255` → u8,
  `256` → u16, `70000` → u32. Wire width is **value-dependent, not schema-dependent**.
- **floats**: any float with `|v| <= 16777216` is encoded **f32** — i.e. **all gameplay floats are
  silently truncated to single precision on the wire**.
- **string**: `[u16 len][utf8 bytes][NUL]`, `len` includes the NUL. Max 65534 payload bytes.
- **buffer**: `[u8 len][bytes]` — **maximum 255 bytes per buffer element.**
- **undefined/null**: a bare type byte, no payload.

---

## 2. Recon: the verified API

### 2.1 Packet

```hemlock
let p = Packet(net_id);
p.add(value);          // value | array of values (arrays are flattened, NOT nested)
p.get(i);              // -> element i
p.data                 // the raw array of decoded elements (public)
p.net_id               // u16
p.build();             // -> buffer, includes the 2-byte size prefix
p.load(payload);       // payload = bytes AFTER the 2-byte size prefix
```

`Packet.load` expects the buffer *without* the size prefix. Both `Server` and `Client` strip it
for you inside their private `parse_packets`.

### 2.2 Server

```hemlock
let s = Server();
s.on("ready", fn() {});
s.on("connect", fn(conn) {});
s.on("packet", fn(conn, packet) {});
s.on("disconnect", fn(conn) {});
s.on("error", fn(err) {});
s.listen(port);                 // BLOCKS FOREVER — this is the server's main loop
s.broadcast(packet_or_buffer, exclude_conn);
s.close();
s._connections                  // array of live Connection objects (public in practice)
```

### 2.3 Connection

```hemlock
conn.send(packet_or_raw_buffer);   // raw buffer path is how you batch
conn.broadcast(packet);            // to everyone except conn
conn.kick();
conn.ws                            // underlying websocket handle
```

### 2.4 Client

```hemlock
let c = Client();
c.on("connect"|"packet"|"disconnect"|"error", cb);
c.connect(addr, port);          // non-blocking; spawns a recv task
c.send(packet);                 // packet.build() then ws.send_binary
c.recv_packet();                // BLOCKING, and LOSSY — see 3.3
c.run();                        // BLOCKING dispatch loop
c.disconnect(); c.is_connected();
c._event_ch                     // the internal channel — our escape hatch, see 4.1
c._ws                           // raw websocket handle — our batching escape hatch
```

---

## 3. Recon: the limits. **These are hard constraints on the protocol design.**

Every item here was measured. The probe scripts are reproducible from the snippets given.

### 3.1 **[VERIFIED] Booleans cannot be serialized. At all.**

```
typeid(true) == TYPEID_BOOL (10)
determine_type(true)  -> THROWS "Binary operation requires numeric operands"
Packet.add(true); Packet.build() -> THROWS
```

`gm_convert.determine_type` lists `TYPEID_BOOL` in its integer branch and then evaluates
`data >= 0`, which Hemlock rejects for bools. **Every wire flag must be an integer `0`/`1`.**
This propagates upward: our `InputCommand` struct must store button state as an **integer
bitfield**, never as bool fields. Doing it any other way means a conversion pass at the
serialization boundary, which is exactly the kind of "we'll fix it when we add multiplayer"
that this document exists to prevent.

### 3.2 **[VERIFIED] A `null` element silently truncates the rest of the packet.**

```
p.add(1); p.add(null); p.add(3);   ->  wire = 9 bytes, decoded element count = 1
```

`parse_data_from_buffer` returns `{data:null,size:0}` for `TYPE_UNDEFINED`, and `Packet.load`'s
loop treats that as end-of-packet. **Never put `null` in a packet.** Optional fields must be
expressed by a presence bitmask + omission, never by a null placeholder.

### 3.3 **[VERIFIED] `client.recv_packet()` silently drops packets.**

If one WebSocket frame contains three packets, `recv_packet()` returns the first and
**discards the other two** (it calls `parse_packets(...)` and returns `packets[0]`). Measured:
3 packets sent in one frame → `recv_packet()` returned 1, subsequent drain returned 0.

**`recv_packet()` is banned in Nightshade.** So is `client.run()` (it blocks forever, which is
incompatible with a render loop).

### 3.4 **[VERIFIED] `spawn()` deep-copies the Server object.**

```hemlock
spawn(run_server, server, PORT);
// on the main thread, afterwards:
server._ws_server == null           // true
server._event_ch  == null           // true
server._connections.length == 0     // true, even with a client connected
server.broadcast(p, null)           // no-op: iterates an empty array
server.close()                      // no-op: _ws_server is null on the copy
```

The gn.hml examples and tests only *appear* to work because the process exits afterwards.

**Consequence — this is the single most important structural fact in this document:**
the authoritative simulation **must live entirely inside the server's event-loop thread**,
i.e. inside the `on("connect")` / `on("packet")` / `on("tick")` callbacks. There is no
"main thread drives the server" option. Cross-thread communication is possible **only**
through `channel()` objects created *before* the `spawn` and passed as arguments (channels are
retained, not copied — this is how gn.hml's own accept/recv loops work).

### 3.5 **[BY INSPECTION + VERIFIED] The Server has no clock.**

`listen()` blocks on `self._event_ch.recv()` with no timeout. With no client traffic, the server
never wakes. A dedicated server therefore cannot run a fixed tick without a change. See §4.2 for
the 12-line patch, which is **verified working**.

### 3.6 **[VERIFIED] Element-per-field packets are 2× the bytes and 7× the CPU.**

32 entities, 7 fields each (id, x, y, z, yaw, state, hp):

| layout | wire bytes | build+load+read (interpreted) | (compiled `hemlockc`) |
|---|---|---|---|
| A: one `p.add()` per field | **777 B** | 1.049 ms | 0.184 ms |
| B: fixed-stride blobs in `buffer` elements | **397 B** | 0.165 ms | **0.026 ms** |

Layout A costs ~1.1% of a 60 fps frame *compiled*, and 6% *interpreted*. Layout B costs 0.16%.
**All bulk state uses Layout B (packed fixed-stride blobs).** See §11.

### 3.7 Hard numeric caps

| limit | value | source |
|---|---|---|
| packet payload | 65535 bytes (incl. the 2-byte net_id) | u16 size field, `build()` throws above it |
| **buffer element** | **255 bytes** | u8 length field, throws at 256 — **verified** |
| string element | 65534 UTF-8 bytes | u16 length field |
| net_id | 0..65535 | verified working at 60000 |
| float precision on the wire | **f32** | `123.456789` → `123.456787` — verified |

The 255-byte buffer cap is the one that shapes the protocol: **a snapshot is a sequence of
≤255-byte blobs**, not one big blob. At the 20-byte entity stride of §11.3 that is 12 entities
per **240-byte** blob.

### 3.8 Transport characteristics

- **TCP only.** WebSocket over TCP. There is **no unreliable/unordered channel** and no way to
  add one without leaving gn.hml. Consequences:
  - Packet loss becomes *latency* (head-of-line blocking), not *gaps*. A dropped snapshot
    delays every later snapshot rather than disappearing.
  - "Send state unreliably at high rate, let old ones drop" — the standard FPS approach — is
    **not available**. We compensate with a lower snapshot rate, small snapshots, delta
    compression, and a larger interpolation buffer (§9.4).
  - Never send a snapshot larger than necessary; a burst directly becomes a latency spike.
- **No built-in ping/RTT, sequence numbers, or ack mechanism.** We build those in our own
  protocol layer (§10, §11).
- **[VERIFIED] Multiple packets may be concatenated into one frame.** `conn.send(rawBuffer)`
  with three concatenated `build()` outputs was correctly split into 3 packets on the client.
  This is our batching mechanism — one frame per tick per client, not one frame per packet.
- **[VERIFIED] Ingest throughput is not a concern.** 2000 5-element packets ingested by the
  server event loop in **65 ms interpreted** (~30k packets/s). An 8-player game at 60 Hz input
  is 480 packets/s — 1.6% of that.

### 3.9 Minor codec notes

- Type `6` (f16) is never *produced* by `determine_type`, but `parse_data_from_buffer` decodes it
  as an f32 read with a 2-byte advance — a corrupting mismatch. Ignore; just never emit it. If we
  ever accept packets from a non-gn.hml peer, validate `type_id != 6`.
- `data_size()` returns `1` for f16, inconsistent with the parser. Same conclusion.
- Strings are NUL-terminated and the parser strips a trailing zero byte. **Do not use string
  elements as binary carriers** — a payload ending in `0x00` loses its last byte. Use `buffer`.
- `parse_packets` (in both server.hml and client.hml) is **module-private**, not exported. We must
  reimplement its 12 lines in our transport shim (§4.1). It's stable; copy it verbatim.

---

## 4. Required changes to our dependencies

We may modify Wobbleweed. gn.hml is an external package, so we prefer **adapting around it** and
keep the required upstream delta to exactly one small patch.

### 4.1 Nightshade-side: a transport shim (no upstream change)

`src/net/transport.hml` wraps gn.hml and provides the two things a game loop needs:
**non-blocking receive** and **batched send**. Both are proven to work.

```hemlock
// NON-BLOCKING DRAIN — verified working from the main (render) thread.
// select([ch], 0) returns null on empty, else { index, value }.
fn poll_packets(cl) {
    let out = [];
    while (true) {
        let sel = select([cl._event_ch], 0);
        if (sel == null) { break; }
        let ev = sel.value;
        if (ev == null) { break; }
        if (ev.type == "data") {
            let ps = parse_packets(ev.binary);      // our copy of the private fn
            let i = 0;
            while (i < ps.length) { out.push(ps[i]); i = i + 1; }
        } else if (ev.type == "disconnect") { cl._connected = false; break; }
    }
    return out;
}
```

Measured: 3 packets picked up in 2 frames of a 60 fps loop with zero blocking. Note it reaches
into `cl._event_ch`, an underscore-prefixed field. That is a deliberate, documented coupling; it
is confined to this one file so a gn.hml upgrade touches exactly one place.

Batched send is the mirror image: concatenate several `pkt.build()` buffers and call
`cl._ws.send_binary(frame)` once (client side) or `conn.send(frame)` once (server side, which
already accepts a raw buffer).

### 4.2 gn.hml-side: the server tick patch (the one upstream change)

Without a clock the dedicated server cannot tick (§3.5). The patch is 12 lines, additive, and
**verified working** (20 Hz measured at 50.2 ms/tick, authoritative broadcasts reaching a client):

```hemlock
// server.hml — add above accept_loop
async fn tick_loop(event_ch, period_ms, stop_ch) {
    let tick = 0;
    while (true) {
        let stop = select([stop_ch], period_ms);   // doubles as the sleep
        if (stop != null) { break; }
        tick = tick + 1;
        try { event_ch.send({ type: "tick", tick: tick }); } catch (e) { break; }
    }
}

// Server() fields:  _on_tick: null,  _tick_hz: 0,  _tick_stop_ch: null,
// on():             else if (event == "tick") { self._on_tick = callback; }
// listen(), after spawning accept_loop:
//   if (self._tick_hz > 0) {
//       self._tick_stop_ch = channel(2);
//       spawn(tick_loop, self._event_ch, i32(1000 / self._tick_hz), self._tick_stop_ch);
//   }
// event loop:       if (event.type == "tick") { if (self._on_tick != null) { self._on_tick(self, event.tick); } } else if ...
```

`self` is passed to the tick callback so the callback can reach `srv._connections` — remember
that on the *server thread* those fields are populated (§3.4).

**Fallback if we must not patch gn.hml:** spawn a local "heartbeat client" that connects to the
server and sends a 6-byte packet every 50 ms. It works (client traffic wakes the event loop) but
it is strictly worse: an extra socket, an extra connection to filter out of broadcasts, and a
clock that dies if that client dies. Prefer the patch.

**None of this is v1 work.** It is recorded here so that when multiplayer starts, nobody has to
re-derive it.

---

## 5. Topology: one code path, two deployments

The rule that makes multiplayer a layer instead of a rewrite:

> **v1 single-player is a client and a server in one process, talking over an in-memory
> transport. The gameplay code never learns which one it is running under.**

```
                    ┌──────────────────────────────────────────────┐
  V1  (shipping)    │ nightshade process                           │
                    │  ┌─────────┐  LoopbackTransport  ┌─────────┐ │
                    │  │ CLIENT  │◄───────────────────►│ SERVER  │ │
                    │  │ render  │  cmds ──►  ◄── snap │ authsim │ │
                    │  └─────────┘                     └─────────┘ │
                    └──────────────────────────────────────────────┘

                    ┌──────────────┐        ws://        ┌──────────────────┐
  V2  (multiplayer) │ nightshade   │◄──────────────────► │ nightshade-server│
                    │ CLIENT       │  NetTransport       │ SERVER (headless)│
                    └──────────────┘  (gn.hml)           └──────────────────┘
```

**LoopbackTransport** is ~60 lines: `send_command(cmd)` pushes onto an array the server reads on
its next tick; `push_snapshot(snap)` pushes onto an array the client reads on its next frame.
It must, from day one:

1. Deliver commands and snapshots **only at tick boundaries**, never instantaneously.
2. Round-trip everything through the **real serializer** in a debug mode
   (`NS_LOOPBACK_SERIALIZE=1`) so that a field that cannot be encoded (a bool, a null, a
   float outside f32 range) fails *in single-player development*, not six months later.
3. Support an artificial-latency knob (`NS_FAKE_LATENCY_MS`, `NS_FAKE_JITTER_MS`). Prediction
   and reconciliation code is only correct if it is *exercised*; in v1 the only way to exercise
   it is to fake the latency. **A dev who has never run the game at 120 ms fake latency has not
   tested their feature.**

Transport interface — the only thing gameplay code sees:

```hemlock
// src/net/transport.hml
// Transport := {
//     is_authority: i32,          // 1 on the server side
//     send_command: fn(cmd),      // client -> server
//     poll_commands: fn(): array, // server:  drain pending commands (with player ids)
//     send_snapshot: fn(pid, snap_buffer),
//     poll_snapshots: fn(): array // client: drain pending snapshots
// }
```

`LoopbackTransport()` and (later) `NetTransport(client)` / `NetServerTransport(server)` implement
it. Nothing else in the codebase imports gn.hml. **Ever.**

---

## 6. The simulation / render split

### 6.1 Fixed timestep, always

```hemlock
let TICK_HZ  = 60;
let TICK_MS  = 16.666666666666668;   // 1000/60
let TICK_DT  = 0.016666666666666666; // seconds — a CONSTANT, never a measured delta

let acc = 0.0;
let prev_ms = ticks();               // wobbleweed sdl.ticks(), monotonic since SDL_Init
let tick = 0;

while (running) {
    let now = ticks();
    let frame_ms = now - prev_ms;
    prev_ms = now;
    if (frame_ms > 250) { frame_ms = 250; }   // spiral-of-death clamp
    acc = acc + frame_ms;

    input_sample(in_state);          // OS input -> raw state (cheap, every frame)

    while (acc >= TICK_MS) {
        let cmd = input_make_command(in_state, tick);   // §8
        client_predict(world, cmd);                     // §9
        transport.send_command(cmd);
        acc = acc - TICK_MS;
        tick = tick + 1;
    }

    let alpha = acc / TICK_MS;       // 0..1, render interpolation factor
    snapshot_build(render_snap, world, alpha);          // §6.3
    render(render_snap);             // reads ONLY render_snap
}
```

Rules, non-negotiable:

- **`TICK_DT` is a compile-time constant.** No gameplay function may ever see a variable dt.
  The server runs the *same* constant. Variable-dt physics is not reproducible on two machines,
  and prediction is a reproduction problem.
- **The sim loop may run 0, 1, or N times per frame.** Any code that assumes "one sim step per
  rendered frame" is broken (it will be wrong the first time someone alt-tabs).
- **`ticks()` is the only clock.** Not `time_ms()`. Not frame counts. Never wall-clock time in
  gameplay logic.
- **Render never mutates sim state.** Not "shouldn't" — *cannot*: see 6.2.

### 6.2 The wall between sim and render

Directory layout enforces it (§15):

- `src/sim/**` — the simulation. **May not import** anything under `src/render/**`, `src/net/**`,
  or `wobbleweed/src/sdl.hml`. No SDL, no window, no textures, no audio, no `print` in hot paths.
- `src/render/**` — reads a snapshot, draws. **May not write** to any sim structure.
- `src/game/**` — the glue: the loop above, transport wiring, scene assembly.

A CI check greps for forbidden imports. It is crude and it will catch the mistake every time.

The practical test: **`src/sim` must run headless.** `hemlock tools/simtest.hml` runs 10 000
ticks of the world with scripted input and no SDL at all. If that binary can't build, the wall
is broken. This is also the harness that later runs the dedicated server.

### 6.3 Rendering reads a snapshot, not the world

The renderer is handed a **RenderSnapshot**: a flat, read-only-by-convention buffer of exactly
what is drawn this frame, already interpolated.

```
RenderSnapshot (SoA, preallocated, reused every frame — zero allocation in the loop)
  count            : i32
  id[]             : i32          stable entity id (for debug + name tags)
  x[], y[], z[]    : f64          INTERPOLATED position
  yaw[], pitch[]   : f64          INTERPOLATED angles
  model[]          : i32          model/mesh index
  frame[]          : i32          animation frame
  tint[]           : i32          packed RGB
  flags[]          : i32          bitfield: visible, muzzleflash, hit, ...
  cam_x/y/z, cam_yaw, cam_pitch, cam_roll   : f64  (roll = view kick, client-only)
  fx_*             : client-only cosmetic layers (particles, shake, decals)
```

Why this shape, specifically:

1. **Interpolation is mandatory anyway.** At 60 Hz sim / 60 Hz render, alpha blending between
   the previous and current tick removes judder when the frame rate dips below 60 — which it
   will, given the 2000–3000 tri budget. Building this in v1 costs almost nothing.
2. **In multiplayer, remote entities are interpolated from *snapshots that arrive at 20 Hz*.**
   If the renderer already consumes "a position that was blended from two states", swapping the
   source from "local sim prev/current" to "network snapshot N-1/N" is a one-function change
   (§9.4). If the renderer instead reads `entity.pos` directly, every remote entity teleports
   20 times a second and you rewrite the renderer.
3. **SoA + preallocated** keeps us inside budget. Every `{x:..,y:..,z:..}` literal is a heap
   object in Hemlock; Wobbleweed's `vec.hml` allocates one per vector op. That is acceptable in
   the *renderer's* per-vertex math (it's already measured at 283 fps) but it is **not**
   acceptable in per-entity sim state. Store entity state as parallel `array<f64>`, convert to
   `v3` only at the call boundary into Wobbleweed.

---

## 7. Entity model

### 7.1 Stable ids

```
entity id := i32,  1 .. 2_000_000     (0 = NONE / invalid)
```

- **Server-allocated in multiplayer; monotonically increasing; never reused within a session.**
  In v1, the local server allocates them from the same counter. Ids are dense enough to index
  arrays and small enough to fit a u32 wire field.
- Ids are **assigned by the authority only.** No client-side code may mint an id for a
  replicated entity. Client-only cosmetic objects (particles, decals, shells) use a **separate
  negative-id space** (`-1 .. -N`) so a mistake is instantly visible in a debugger and can never
  collide.
- **Id → slot lookup is an explicit map**, not `array[id]`. Slots compact on despawn; ids do not.
  `sparse[]` (id → slot) + `dense[]` (slot → id) is the standard sparse-set; use it.
- Reserve **id ranges by kind** for cheap classification and for debugging packet dumps:

| range | kind |
|---|---|
| `1 .. 64` | players (index = player slot; player N always has id N) |
| `1_000 ..` | AI / NPCs |
| `500_000 ..` | projectiles |
| `1_000_000 ..` | pickups / loot / world-interactables |
| `< 0` | client-local cosmetics — **never replicated** |

Player id == player slot is deliberate: it makes "which entity is my local player" a constant
lookup and makes the local-player check in the snapshot decoder trivial.

### 7.2 Component layout: SoA, replication-grouped

Do **not** write `entities = [ {id:.., pos:.., hp:..}, ... ]`. Write parallel arrays, grouped
**by how often they replicate**, because that grouping *is* the packet layout:

```
// src/sim/world.hml  — the authoritative world
World := {
  // ---- identity (never changes after spawn) ----
  count, cap,
  id[], kind[], owner[],              // owner = player slot that controls it, 0 = server

  // ---- TRANSFORM: replicated EVERY snapshot (20 Hz), delta-compressed ----
  px[], py[], pz[],                   // f64 position
  vx[], vy[], vz[],                   // f64 velocity  (needed for extrapolation + prediction)
  yaw[], pitch[],                     // f64 radians

  // ---- STATE: replicated on change (event-ish, cheap) ----
  hp[], armor[], anim[], anim_t[], team[], flags[],

  // ---- INVENTORY / PROGRESSION: replicated to the owner only ----
  weapon[], ammo_mag[], ammo_reserve[], ...

  // ---- SERVER-ONLY: never replicated ----
  ai_state[], ai_target[], ai_timer[], loot_seed[], last_damage_by[], ...

  // ---- CLIENT-ONLY: never replicated, never authoritative ----
  // (lives in a separate ClientFx struct, not in World at all)
}
```

Four rules:

1. **A field belongs to exactly one of those four groups, and the group is written in a comment
   next to it.** If you can't say which group a new field is in, you don't understand the field
   yet.
2. **Server-only fields must never influence a replicated field in a way the client also
   computes.** If AI aim jitter uses `ai_timer`, and the client predicts AI motion, the client
   diverges. Either replicate the input or don't predict that entity. (v1 policy: **clients do
   not predict anything they do not own.** §9.1)
3. **Nothing about an entity may live in a closure.** No `spawn_zombie()` returning a tick
   function that captures its own state. Closures cannot be snapshotted, serialized, rewound for
   lag compensation, or delta-compressed. This is the most tempting mistake in a scripting
   language and the most expensive one to undo.
4. **Growth is by `reserve` + index, never by pushing objects.** `world_spawn(w, kind)` returns a
   slot; `world_despawn(w, slot)` swaps with the last and decrements `count`, fixing `sparse[]`.

### 7.3 Historical transform ring buffer (build the hook in v1)

Server-side lag compensation (§13) requires rewinding entity transforms to a past tick. Reserve
the shape now even if v1 never fills it:

```
History := {
  ticks: 32,                              // ~0.5 s at 60 Hz, or 32 snapshots at 20 Hz
  head: i32,
  tick_of[32]: i32,
  px[32][cap], py[32][cap], pz[32][cap],  // flat: px[(slot * 32) + ring]
  yaw[32][cap], pitch[32][cap]
}
```

This is cheap **only** because transforms are SoA f64 arrays. If transforms are objects, a
history buffer is 32 × N heap objects per tick and lag compensation becomes unaffordable. This
is the concrete reason §7.2 rule 1 is not stylistic.

v1 requirement: `world_capture_history(w)` exists and is called once per tick, even if the
buffer depth is 2. Prove the copy cost fits the budget while the world is still small.

---

## 8. Input as a serializable command

**The command struct is the contract between the player and the simulation.** In v1 it goes into
a function call; in v2 it goes into a socket. It must be identical.

### 8.1 The struct

```hemlock
// src/sim/command.hml  — the ONLY way input reaches the simulation
InputCommand := {
    tick:      i32,   // client tick this command belongs to (monotonic, u32 on the wire)
    dt_ms:     i32,   // always TICK_MS; present so a variable-rate client is detectable/rejectable
    move_x:    i32,   // -127..127  strafe   (quantized: i32(axis * 127))
    move_y:    i32,   // -127..127  forward
    yaw_q:     i32,   // 0..65535   absolute view yaw   (u16: radians * 65536 / TAU)
    pitch_q:   i32,   // 0..65535   absolute view pitch
    buttons:   i32,   // BITFIELD — see below. INTEGER, NEVER BOOLS (§3.1)
    weapon_sel:i32,   // 0..15 requested weapon slot
    seq:       i32    // per-client sequence number, == tick in v1; kept separate on purpose
}

// buttons bits
BTN_FIRE      = 1;      BTN_ADS       = 2;     BTN_JUMP    = 4;    BTN_CROUCH  = 8;
BTN_SPRINT    = 16;     BTN_RELOAD    = 32;    BTN_USE     = 64;   BTN_MELEE   = 128;
BTN_GRENADE   = 256;    BTN_SWITCH    = 512;   BTN_BUILD   = 1024; BTN_INV     = 2048;
```

### 8.2 Rules

- **Absolute view angles, not deltas.** The client owns its aim; sending `yaw` absolute means a
  lost/late command doesn't rotate the player by the wrong amount, and the server can clamp
  turn rate for anti-cheat by comparing consecutive commands.
- **Quantize at construction, not at send.** `yaw_q` is a u16 *in the struct*. The simulation
  dequantizes it (`yaw_q * TAU / 65536.0`) and uses the dequantized value. Therefore the local
  prediction uses **exactly the same angle the server will use**, bit for bit. If you keep a
  full-precision yaw locally and quantize only on send, prediction disagrees with the server on
  every single tick and you will chase ghosts.
- **Every field is an integer.** No bools (§3.1), no floats (f32 truncation, §3.7), no strings,
  no nulls (§3.2). The whole struct is 9 integers = **9 elements / ~30 bytes** as loose elements,
  or **20 bytes** as a packed blob (§11.2).
- **The simulation's only entry point is:**
  ```hemlock
  fn sim_apply_command(world, slot, cmd);       // deterministic given (world, slot, cmd)
  fn sim_step(world, tick);                     // everything not driven by a command
  ```
  Nothing else may read the keyboard, the mouse, or SDL. Not "mostly" — *nothing*. Menu and
  HUD input is fine outside this path because it is not simulated; anything that moves a body,
  fires a weapon, opens a chest, or places a block goes through `InputCommand`.
- **Chat/text and other rare, variable-length actions are NOT part of InputCommand.** They are
  separate reliable messages (§10.3). Keeping the command fixed-size is what makes redundancy
  (§9.5) and packing cheap.
- **Input sampling is decoupled from command construction.** `input_sample()` runs every frame
  and accumulates (e.g. mouse delta sums, "fire was pressed at some point this frame" latches);
  `input_make_command()` runs once per *tick* and drains the accumulator. Otherwise, at 120 fps
  with a 60 Hz tick, half your mouse motion and some of your clicks vanish.

---

## 9. Client-side prediction and server reconciliation

Not implemented in v1. **Its shape is mandatory in v1**, because the shape is the expensive part.

### 9.1 What is predicted

| entity | v1 | v2 |
|---|---|---|
| local player movement | "prediction" is just the sim | predicted, reconciled |
| local player weapon (recoil, muzzle, sound, animation) | immediate | immediate, client-side, cosmetic (§12) |
| local player *damage taken* | authoritative | authoritative, **never predicted** |
| remote players | n/a | **interpolated only, never predicted** |
| AI / NPCs | local sim | **interpolated only** |
| projectiles | local sim | fired cosmetically instantly on the client; the authoritative projectile is a separate server entity (§12.3) |
| loot / pickups / block placement | local sim | **authoritative, with an optimistic local preview that is reverted on server denial** |

v1 policy stated plainly: **only the local player is ever predicted.** This keeps the
reconciliation surface to one entity and about six floats, which is the difference between a
week of work and a quarter.

### 9.2 The ring buffer of pending commands

```
PendingCommands := {
  cap: 128,                     // ~2.1 s at 60 Hz — more than any playable RTT
  head: i32,
  cmd[128]:   InputCommand,     // the command as sent
  state[128]: PredictedState    // world state AFTER applying cmd[i]
}

PredictedState := { px, py, pz, vx, vy, vz, on_ground, crouch_t, ... }
```

Every tick: build cmd → apply to the local player → **store both** → send.

### 9.3 Reconciliation

When a snapshot arrives carrying `(last_acked_seq, authoritative_state_of_my_player)`:

```
1. discard pending entries with seq <= last_acked_seq
2. compare state[last_acked_seq] with the authoritative state
3. if |error| < POS_EPSILON (≈ 0.02 m) and velocity agrees: done, nothing happened
4. otherwise:
     a. snap the local player to the authoritative state
     b. REPLAY every remaining pending command in order through sim_apply_command()
     c. the result is the new predicted present
     d. record the correction magnitude into a smoothing offset (§9.6)
```

Structural requirements that must be true **in v1** for step 4b to be possible:

- `sim_apply_command(world, slot, cmd)` is **pure with respect to the world** — no globals, no
  RNG that isn't seeded from replicated state, no `ticks()`, no SDL, no audio, no particle
  spawning. If applying a command plays a sound, replaying 8 commands plays 8 sounds.
  **Cosmetic side effects must be emitted by a separate `sim_effects()` pass** that runs once per
  tick and is *skipped during replay* (`world.replaying == 1`).
- The local player's simulated state must be **fully captured** by `PredictedState`. If some
  movement behaviour hides in a variable outside that struct (a coyote-time timer, a slide
  counter, a bhop grace window), replay diverges. Every such variable goes in the struct.
  Enforce it: `predicted_capture(world, slot)` / `predicted_restore(world, slot, st)` live next
  to the movement code and are updated in the same commit that adds any movement variable.
- Movement code must not consult anything non-replicated (§7.2 rule 2).

### 9.4 Interpolation of everything else

Remote entities render at `render_time = latest_snapshot_time - INTERP_DELAY_MS`.

```
INTERP_DELAY_MS = 100      // = 2 snapshot intervals at 20 Hz, plus headroom for TCP jitter
```

TCP head-of-line blocking (§3.8) makes jitter worse than a UDP game's, so 100 ms is a floor, not
a target; make it adaptive later (track snapshot inter-arrival variance, clamp to 80–200 ms).

The client keeps a small ring of the last 4 snapshots and interpolates between the two that
straddle `render_time`, extrapolating with velocity for at most ~120 ms before freezing.

**In v1**, `render_snapshot_build()` interpolates between the previous and current *local* tick
using `alpha`. In v2 the same function interpolates between two *network* snapshots. Same
signature, same output, different source. That is the whole point of §6.3.

### 9.5 Command redundancy

TCP already guarantees delivery, so redundancy is not for loss — it is for **batching**: send the
last 3 commands in one packet at 20 Hz rather than 1 command at 60 Hz. That is 3× fewer frames,
3× fewer syscalls, and it degrades gracefully into a UDP transport later if we ever leave
gn.hml. Design the command packet as a **count-prefixed array of commands** from day one (§11.2).

### 9.6 Error smoothing (juice-critical)

Never teleport the camera on reconciliation. Keep a `view_offset` vector: on correction, set
`view_offset = old_predicted_pos - corrected_pos`, then decay it toward zero over ~200 ms and
add it to the **render** camera position only. The player sees the world drift back over 12
frames rather than snap. This lives in `src/render/`, touches nothing in `src/sim/`, and it is
the difference between "networked" and "AAA-feeling".

---

## 10. Protocol: message catalogue

`net_id` is a u16. Reserve blocks so a dumped packet is instantly identifiable:

| range | direction | class |
|---|---|---|
| `1–99` | C→S | control / handshake |
| `100–199` | C→S | gameplay input |
| `200–299` | C→S | reliable actions (chat, build, trade, inventory) |
| `1000–1099` | S→C | control / handshake |
| `1100–1199` | S→C | snapshots |
| `1200–1299` | S→C | events (reliable, non-tick-bound) |
| `1300–1399` | S→C | world streaming (chunks) |

### 10.1 Assigned ids (v2; reserve them now, don't use them)

| id | name | dir | payload |
|---|---|---|---|
| 1 | `C_HELLO` | C→S | protocol_version u16, client_build u32, name string |
| 2 | `C_PING` | C→S | client_time_ms u32 |
| 3 | `C_READY` | C→S | — |
| 100 | `C_INPUT` | C→S | n u8, then n × packed command blob (§11.2) |
| 200 | `C_CHAT` | C→S | text string |
| 201 | `C_ACTION` | C→S | action u8, target_id u32, arg u32 (build/place/use/trade) |
| 1000 | `S_WELCOME` | S→C | your_player_id u16, your_entity_id u32, tick u32, world_seed u32, tick_hz u8, snapshot_hz u8 |
| 1001 | `S_PONG` | S→C | client_time_ms u32, server_time_ms u32, server_tick u32 |
| 1002 | `S_DISCONNECT` | S→C | reason u8, message string |
| 1100 | `S_SNAPSHOT` | S→C | §11.3 |
| 1101 | `S_SNAPSHOT_DELTA` | S→C | §11.4 |
| 1200 | `S_EVENT` | S→C | packed event blobs (§11.5) |
| 1201 | `S_PLAYER_JOIN` | S→C | player_id u16, entity_id u32, name string |
| 1202 | `S_PLAYER_LEAVE` | S→C | player_id u16, reason u8 |
| 1300 | `S_CHUNK` | S→C | chunk_x s16, chunk_z s16, n_blobs u8, blobs… |

### 10.2 Frame batching

One WebSocket frame per client per tick, containing every packet queued for that client
(verified working, §3.8). The server's tick callback does:

```
for each connection:
    frame = concat(snapshot.build(), event0.build(), event1.build(), ...)
    conn.send(frame)            // ONE raw-buffer send
```

Keep the frame under ~1200 bytes when possible; anything larger becomes a latency spike on a
head-of-line-blocked TCP stream.

### 10.3 Reliability classes

Everything is reliable (TCP), but not everything should be *tick-bound*:

- **Tick-bound, lossy-tolerant**: snapshots. Newer supersedes older. Never queue more than one.
- **Reliable, ordered**: joins/leaves, chat, inventory results, block placements, loot grants.
  These carry their own sequence and must be applied in order.
- **Never send**: anything the client can compute from what it already has. Particle spawns,
  screen shake, footstep sounds, shell casings, muzzle flashes, hit-marker animation. See §12.

---

## 11. Packet layout on gn.hml `Packet`

### 11.1 The packing convention

Because of §3.6 (2× bytes, 7× CPU) and §3.7 (255-byte buffer cap), **bulk state is packed by
hand into fixed-stride `buffer` elements**. Loose `p.add()` elements are used only for small
headers where self-description costs nothing.

Two helper modules, written in v1 (they cost an afternoon and they are the thing that makes the
v2 packet code boring):

```hemlock
// src/net/quantize.hml
POS_SCALE   = 256.0;                                 // 1/256 m ≈ 3.9 mm, ±8388 km in i32
ANG_SCALE   = 10430.378350470453;                    // 65536 / TAU
fn q_pos(v):    i32 { return i32(round(v * POS_SCALE)); }
fn dq_pos(q):   f64 { return q / POS_SCALE; }
fn q_ang(a):    i32 { ... wrap to [0,TAU) ... return i32(a * ANG_SCALE) & 65535; }
fn dq_ang(q):   f64 { return q / ANG_SCALE; }
fn q_vel(v):    i32 { return i32(round(v * 128.0)); } // 1/128 m/s, i16 covers ±256 m/s
```

**Quantization is not a networking detail. It is a simulation detail.** The authoritative
position that the client compares against is the *dequantized* one; if the server keeps
full-precision f64 and sends a quantized value, every client sees a permanent ~2 mm disagreement
and reconciliation fires forever. Policy: **the server quantizes its own transform state to the
wire grid once per snapshot** (`px = dq_pos(q_pos(px))`), so client and server agree exactly.
This must be true in v1's local server too, or the epsilon comparison in §9.3 is untestable.

Never rely on gn.hml's f32 auto-encoding for gameplay state (§3.7). Quantize explicitly to
integers; you get exact reproducibility and fewer bytes.

### 11.2 `C_INPUT` (net_id 100) — 20 bytes per command

```
element 0 : u8   n          number of commands in this packet (1..8)
element 1 : buffer          n * 20 bytes, oldest first   (max 160 B, under the 255 cap)

command stride (20 bytes, little-endian):
  +0   u32  tick
  +4   u32  seq
  +8   i8   move_x           (-127..127)
  +9   i8   move_y
  +10  u16  yaw_q
  +12  u16  pitch_q
  +14  u32  buttons
  +18  u8   weapon_sel
  +19  u8   dt_ms            (16 or 17; a variable-rate client is visible here)
```

At 20 Hz with n=3: 20 packets/s × (4 + 2 + 60) ≈ **1.3 KB/s upstream per client**.

### 11.3 `S_SNAPSHOT` (net_id 1100) — full state

```
element 0 : u32  server_tick
element 1 : u32  last_acked_seq        (this client's last processed command seq)
element 2 : u16  server_time_ms & 0xFFFF
element 3 : u16  entity_count
element 4 : buffer   <= 240 B    entity blob 0   (12 entities x 20 B = 240)
element 5 : buffer   <= 240 B    entity blob 1
...                              ceil(count / 12) blobs
last      : buffer               local-player authoritative state (24 B), see below

entity stride (20 bytes, little-endian) — 12 entities per 240-byte blob:
  +0   u32  entity_id
  +4   i32  px_q
  +8   i32  pz_q               (horizontal axes get full i32 range)
  +12  i16  py_q               (vertical: 1/256 m, ±128 m — clamp world height accordingly)
  +14  u16  yaw_q
  +16  u8   pitch_q            (u8 is plenty for non-local entities: 1.4 deg)
  +17  u8   anim               (animation state id)
  +18  u8   hp_pct             (0..100; exact hp is owner-only)
  +19  u8   flags              (team<<0 | crouch<<2 | ads<<3 | firing<<4 | dead<<5 ...)

local-player authoritative block (24 bytes) — sent to its owner only:
  +0   i32  px_q  +4 i32 py_q  +8 i32 pz_q
  +12  i16  vx_q  +14 i16 vy_q  +16 i16 vz_q     (1/128 m/s)
  +18  u8   hp    +19 u8 armor
  +20  u8   move_state   +21 u8 weapon  +22 u16 ammo_mag
```

Budget: 12 players + 20 nearby entities = 32 entities → 3 blobs = 640 B + 24 B + header ≈ **690 B**.
At 20 Hz that is **13.8 KB/s down per client**; 8 players ≈ 110 KB/s at the server. Fine.

### 11.4 `S_SNAPSHOT_DELTA` (net_id 1101) — the optimization, later

Same header, then:

```
element 3 : u16   changed_count
element 4 : buffer  changed-entity bitmask (1 bit per entity in the client's known set)
element 5+: buffers  packed entries for changed entities only, same 20-byte stride
```

Deltas require the server to track **per-client acknowledged baselines**, which requires the
client to ack snapshots (add `C_ACK_SNAPSHOT`, net_id 4). **Do not build this in v1.** Build the
*hook*: the snapshot writer takes a `baseline` argument that v1 always passes as `null`, and the
per-connection state struct (§14.2) has an unused `last_acked_snapshot` field.

### 11.5 `S_EVENT` (net_id 1200) — discrete authoritative facts

Events are what make an authoritative game feel responsive: they are the server saying "this
definitely happened", and the client turns them into juice.

```
element 0 : u32  server_tick
element 1 : u8   n_events
element 2 : buffer   n * 16 bytes  (max 15 events per blob, chain more blobs as needed)

event stride (16 bytes):
  +0   u8   type
  +1   u8   sub               (weapon id / damage type / loot rarity ...)
  +2   u32  actor_id
  +6   u32  target_id
  +10  i16  x_q  (1/16 m, relative to the receiving player — impact points, ±2048 m)
  +12  i16  y_q
  +14  i16  z_q
```

Event types (reserve now): `EV_HIT`, `EV_KILL`, `EV_DAMAGE_TAKEN`, `EV_SPAWN`, `EV_DESPAWN`,
`EV_PICKUP`, `EV_RELOAD_DONE`, `EV_WEAPON_SWITCH`, `EV_DOOR`, `EV_BLOCK_PLACED`,
`EV_BLOCK_BROKEN`, `EV_XP`, `EV_LEVELUP`, `EV_SOUND`.

**In v1 the local server emits these events into the loopback transport and the client reacts to
them.** This is the single highest-leverage v1 constraint after the sim/render split: it forces
"the thing that shows the hitmarker" to be downstream of "the thing that decided a hit
happened", and it means the multiplayer version changes nothing about the feel.

---

## 12. Authority matrix

The rule: **anything that changes what is true must be decided by the server; anything that only
changes what it looks or sounds like is decided by the client, immediately.**

### 12.1 Server-authoritative (MUST)

| system | why |
|---|---|
| **Hit registration** | trivially exploitable otherwise; also the sole source of hitmarkers |
| **Damage numbers, armor, damage falloff, headshot multipliers** | must match across all clients |
| **Death, respawn, spawn point selection** | |
| **Health, armor, shields** | never predicted; predicted health causes phantom deaths |
| **Ammo counts (the truth)** | client shows a predicted count; server's value wins |
| **Loot drops and their contents (RNG)** | server-seeded RNG only, or clients desync/exploit |
| **Pickups / who got the item** | two players, one item: exactly one wins, server decides |
| **Inventory contents, crafting results, trades** | |
| **Block placement / destruction** | client shows an optimistic ghost; server confirms or reverts |
| **XP, level, unlocks, challenge progress, currency** | progression is the thing worth cheating for |
| **Doors, switches, objective state, capture progress** | |
| **AI decisions, AI targeting, AI spawning** | |
| **Projectile flight and impact (the authoritative one)** | |
| **World seed, chunk generation parameters, time of day** | |
| **Weapon fire *rate*, reload *completion*, recoil *pattern seed*** | timing gates are cheat surfaces |

### 12.2 Client-cosmetic (MUST be local and immediate — never wait for the server)

| system | notes |
|---|---|
| Muzzle flash, tracer, shell ejection | fire the instant the button is pressed |
| Weapon sway, bob, ADS transition, recoil *camera* kick | pure view-space; must not affect the sent `yaw_q`/`pitch_q`... |
| Screen shake, hit flash, damage vignette, chromatic wobble | |
| Particles: sparks, blood, dust, muzzle smoke, impact decals | negative-id space (§7.1) |
| Footstep/gunshot **audio** (local), audio positioning | server may *also* send `EV_SOUND` for out-of-view sources |
| HUD animations, hitmarker animation, kill-feed animation | the *facts* come from `EV_*`; the *animation* is local |
| Crosshair spread visual, reload animation | animation is local; the reload *completing* is `EV_RELOAD_DONE` |
| First-person viewmodel entirely | it is never an entity, never replicated |
| Interpolation, extrapolation, error smoothing | §9 |
| Level-of-detail, culling, dithering, the PS1 vertex snap | |

**...with one critical exception noted above:** recoil that *moves the player's aim* (as opposed
to only the camera) must be applied to the value that goes into `InputCommand.yaw_q/pitch_q`, so
the server sees the same aim direction the player saw. Split recoil into `recoil_aim` (goes into
the command; server-verifiable against the weapon's recoil pattern) and `recoil_view` (pure
render kick, never leaves the client). Get this split right in v1; retrofitting it means
re-tuning every weapon.

### 12.3 The "instant feedback, authoritative truth" pattern

For every action, three layers:

1. **Client, frame 0:** play the cosmetic response immediately (muzzle flash, sound, animation,
   predicted ammo decrement, optimistic block ghost).
2. **Server, tick T:** decide the truth. Emit `EV_*`.
3. **Client, T+RTT:** apply the truth. If it agrees with the prediction (>95% of the time),
   nothing visible happens. If it disagrees, correct — and **make the correction legible**
   (the block ghost dissolves, the ammo count corrects with a tick, the hitmarker never appeared
   because the hit didn't happen).

**Never make the cosmetic layer wait for the truth layer.** A gun that fires 80 ms after the
click is a broken gun, and no amount of art fixes it.

---

## 13. Lag compensation and hit registration

The design v2 will use, stated now because §7.3 exists to support it:

1. Client fires at its `render_time` (= `server_time - INTERP_DELAY - rtt/2`, §9.4) and sends
   `BTN_FIRE` in the command for tick `T_c`. It also sends its `yaw_q/pitch_q` for that tick.
2. Server receives it at server tick `T_s`, computes the client's view time
   `T_view = T_s - (rtt/2 + INTERP_DELAY) / TICK_MS`, clamped to the history depth.
3. Server **rewinds** all other entities' transforms to `T_view` from the history ring (§7.3),
   raycasts from the shooter's authoritative eye position along the *client-supplied* aim
   direction, restores the present, and emits `EV_HIT`/`EV_KILL`.
4. Anti-cheat guards: clamp `T_view` to ≤ 250 ms in the past; validate that consecutive
   commands' aim deltas are within the weapon's maximum turn rate; validate fire rate against
   the weapon's cooldown; validate that the shooter's own position matches the server's within
   the reconciliation epsilon.

v1 obligations, all cheap:

- **The raycast lives in `src/sim/`, takes the world and an explicit `(origin, dir, tick)`, and
  returns a hit record.** It must not read the camera, the renderer, or anything about "now".
  A hit test that implicitly means "against the current visual state" cannot be rewound.
- **Weapons are data.** `{ fire_rate_ms, damage, falloff_curve, spread, recoil_pattern[],
  mag_size, reload_ms, pellet_count, range }` in a table indexed by weapon id. The server must
  be able to evaluate the whole weapon without any client asset. No weapon behaviour inside a
  render function, ever.
- **Aim direction is derived from `cmd.yaw_q/cmd.pitch_q`, not from the camera matrix.** The
  camera is a *consumer* of the aim, not its source.

---

## 14. World streaming, chunks, and interest management

The open-world/Minecraft axis interacts with networking in exactly two places.

### 14.1 Chunks

- **`CHUNK_SIZE = 32.0` m** horizontally; vertical is a single column (keeps chunk ids 2D and
  the packet layout simple).
- **Chunk id = `(cx & 0xFFFF) << 16 | (cz & 0xFFFF)`**, a u32 — directly usable as a wire field
  and as a map key.
- **World generation is a pure function of `(world_seed, cx, cz)`.** No exceptions. If chunk
  content depends on generation order, on player history, or on an unseeded RNG, then the server
  must transmit every chunk instead of ~200 bytes of modifications, and streaming an open world
  over TCP stops being feasible.
- **Player edits are a sparse overlay** on top of generated content: `(chunk_id, local_index,
  block_id)` triples. That overlay is what `S_CHUNK` transmits. A chunk with no edits transmits
  as a single u32.
- v1 must therefore keep generation and modification **separate data structures**, even though
  in single-player it would be simpler to bake edits into the generated array. This is a real
  cost in v1 and it is worth paying.

### 14.2 Interest management (per-connection state)

Reserve the struct now; fill it in v2:

```
PlayerConn := {
    conn,                       // gn.hml Connection (server side only)
    player_id, entity_id,
    last_acked_seq: i32,        // §9.3
    last_acked_snapshot: i32,   // §11.4 — unused in v1
    rtt_ms: i32, jitter_ms: i32,
    known_chunks: [],           // chunk ids already sent
    interest_radius: 3,         // chunks
    known_entities: [],         // for delta baselines + spawn/despawn events
    cmd_queue: [],              // buffered input commands awaiting their tick
    over_budget_strikes: i32    // anti-cheat / flood control
}
```

The server sends an entity to a client only if it is within `interest_radius` chunks (plus a
hysteresis band so entities on the boundary don't flicker in and out). Entities leaving
interest generate `EV_DESPAWN`, not silence — a client that never hears "gone" leaves a corpse
standing forever.

**v1 obligation:** the snapshot builder takes a `(world, viewer_slot)` pair and *already*
filters by distance, even though in single-player the filter passes everything within the
render distance. If the snapshot builder has no concept of a viewer, adding one later means
touching every call site.

---

## 15. Prescribed module layout

```
nightshade/
  src/
    sim/                    ← NO SDL, NO render, NO net. Runs headless.
      world.hml             World struct, SoA arrays, spawn/despawn, sparse-set ids
      command.hml           InputCommand, button bits, quantize/dequantize of the command
      movement.hml          sim_apply_command: the movement model (the predicted code path)
      combat.hml            raycast(world, origin, dir, tick), damage application
      weapons.hml           weapon data table (pure data + pure functions)
      ai.hml                AI stepping (server-only fields)
      projectiles.hml
      world_gen.hml         pure f(seed, cx, cz) -> chunk
      chunk.hml             chunk storage + the sparse edit overlay
      rng.hml               explicit seeded PRNG (§18) — NEVER @stdlib/random in sim
      sim.hml               sim_step(world, tick); the tick order (§18.2)
      history.hml           transform ring buffer (§7.3)
      snapshot.hml          snapshot_write(world, viewer_slot, baseline) / snapshot_read
    net/
      transport.hml         Transport interface + LoopbackTransport (v1) + NetTransport (v2)
      protocol.hml          net_id constants, packet builders/parsers, blob strides
      quantize.hml          q_pos/dq_pos/q_ang/dq_ang/q_vel  (§11.1)
      packing.hml           blob writer/reader helpers respecting the 255-byte cap
    render/
      render_snapshot.hml   RenderSnapshot struct + build-from-sim / build-from-network
      view.hml              camera, view offset/smoothing (§9.6), recoil_view
      hud.hml               reads RenderSnapshot + event log; writes nothing
      fx.hml                particles, decals, shake — negative-id space, client-only
      world_render.hml      wobbleweed batch assembly
    game/
      main.hml              the loop of §6.1
      client.hml            client-side: input -> command -> transport, snapshot -> render
      server.hml            authoritative sim host; in v1 runs in-process on the loopback
      config.hml            constants: TICK_HZ, SNAPSHOT_HZ, INTERP_DELAY_MS, budgets
  tools/
    simtest.hml             headless sim runner (§6.2) — CI gate
    replay.hml              record/replay of command streams (§19)
    packetdump.hml          hexdump + decode of a captured frame
  docs/recon/NETWORKING.md  this file
```

Import rules, enforced by a grep in CI:

- `src/sim/**` may import: `@stdlib/math`, other `src/sim/**`. **Nothing else.**
- `src/net/**` may import: `src/sim/**` (for struct field names), gn.hml, `@stdlib/*`.
- `src/render/**` may import: `wobbleweed/**`, `src/render/**`, and *read-only structs* from
  `src/sim/**`. It may not import `src/net/**`.
- Only `src/game/**` imports across all three.

---

## 16. ANTI-PATTERNS — do not do these in v1

Each of these is individually cheap to avoid now and expensive to undo later. The "cost later"
column is the honest estimate of the rewrite.

| # | Anti-pattern | Why it blocks multiplayer | Cost later |
|---|---|---|---|
| 1 | **Variable delta time in gameplay** (`update(dt)` with a measured dt) | prediction replays cannot reproduce the server; two machines diverge on frame 1 | rewrite every gameplay system |
| 2 | **Reading input anywhere except `input_make_command()`** | input that isn't in the command struct cannot be sent; the server can't reproduce the action | audit + rewrite every system that "just checks a key" |
| 3 | **Bools in any struct destined for the wire** | gn.hml **throws** on bool (§3.1) | mechanical but touches everything |
| 4 | **`null` as an "optional field" in wire data** | truncates the packet silently (§3.2) | protocol redesign |
| 5 | **Entity state inside closures / per-entity update lambdas** | cannot serialize, snapshot, rewind, or delta-compress | rewrite the entity system |
| 6 | **Arrays of objects for entity state** (`ents = [{...}]`) | history buffers and snapshots become allocation storms; blows the 2 ms sim budget | rewrite the entity system |
| 7 | **The renderer reading `world.*` directly** | remote entities arrive at 20 Hz and will judder; no place to insert interpolation | rewrite the renderer's data access |
| 8 | **Client deciding a hit, a kill, a pickup, a loot roll, or XP** | trivially cheatable; disagreement between clients | rewrite combat + progression |
| 9 | **Gameplay side effects inside `sim_apply_command`** (sounds, particles, camera shake) | replay during reconciliation fires them N times | untangle every ability |
| 10 | **Unseeded / global RNG in the simulation** (`@stdlib/random` in `src/sim`) | server and client roll different numbers; loot and spread desync | thread a seed through everything |
| 11 | **Wall-clock time in gameplay** (`time_ms()`, `now()`, date) | not reproducible; not tick-aligned | audit every timer |
| 12 | **Ids assigned by the client, or ids reused after despawn** | id collisions across peers; stale references resolve to the wrong entity | rewrite id allocation + all references |
| 13 | **Storing an entity *reference* instead of an id** (`target: <entity object>`) | references can't cross the wire and dangle after despawn | rewrite every reference site |
| 14 | **World generation that isn't a pure `f(seed, cx, cz)`** | server must ship the whole world instead of the edits | rewrite the generator |
| 15 | **Baking player edits into the generated chunk array** | can't transmit or persist the diff | rewrite chunk storage |
| 16 | **Snapshot/serialization code that knows about the renderer** | the dedicated server has no renderer and won't link | untangle |
| 17 | **`client.recv_packet()` or `client.run()`** | drops packets (§3.3) / blocks the render loop | — (just never use them) |
| 18 | **Importing gn.hml anywhere except `src/net/`** | couples gameplay to the transport; kills the loopback | audit every import |
| 19 | **Assuming one sim step per rendered frame** | breaks on any frame-rate deviation, which is guaranteed at a PS1 tri budget | audit every system |
| 20 | **A "player" that is special-cased rather than an entity** | remote players are entities; a special-cased local player has no remote counterpart | rewrite the player |
| 21 | **Full-precision floats compared against the server's quantized values** | permanent tiny disagreement → reconciliation fires every tick → constant micro-stutter | re-tune the whole movement model |
| 22 | **Snapshot builder with no viewer parameter** | no place to add interest management | touch every call site |
| 23 | **Aim direction derived from the camera matrix rather than from the command** | server can't reproduce the shot; lag compensation is impossible | rewrite combat |
| 24 | **Mutating sim state from HUD/menu/UI code** | UI runs on the client; the server never sees it | audit the UI |
| 25 | **Movement variables outside `PredictedState`** (coyote time, slide timer, bhop window) | replay diverges; the player rubber-bands only in specific movement states — a brutal bug to find | audit the movement model |

---

## 17. Budgets

### 17.1 CPU (the binding constraint)

Compiled baseline: 283 fps for ~530 triangles ⇒ **3.5 ms/frame of render at 530 tris**. At the
target 2000–3000 tris the render alone will consume most of a 16.6 ms frame. Therefore:

| budget | per frame @60 fps |
|---|---|
| render (wobbleweed) | ~12 ms |
| **simulation** | **≤ 2.0 ms** |
| **networking (encode + decode + transport)** | **≤ 0.3 ms** |
| input, audio, HUD | ~1 ms |
| slack | ~1.3 ms |

Measured against that: a 32-entity packed snapshot costs **0.026 ms** compiled to build + parse +
read (§3.6). Even at 4× the entity count and both directions, networking lands around 0.15 ms —
comfortably inside 0.3 ms. **The element-per-field layout would cost 0.18 ms for one snapshot
alone**, i.e. 60% of the whole networking budget for one message. This is why §11.1 is a rule and
not a suggestion.

The sim budget is the tight one. At 2 ms/frame compiled (≈ 5.4× the interpreted cost, so ~11 ms
interpreted — the interpreter is for tooling only), a few hundred entities of SoA float math is
achievable; a few hundred entities of object allocation is not.

### 17.2 Bandwidth (not a constraint, but keep it honest)

| stream | rate | per client |
|---|---|---|
| `C_INPUT` (3 commands @ 20 Hz) | 20 pkt/s × 66 B | **1.3 KB/s up** |
| `S_SNAPSHOT` (32 entities @ 20 Hz) | 20 × 690 B | **13.8 KB/s down** |
| `S_EVENT` (bursty) | ~2 KB/s peak | |
| chunk streaming | bursty, ~2 KB/chunk with edits | |
| **8-player server total** | | **~130 KB/s = ~1 Mbit/s** |

Comfortable. The reason to keep snapshots small is **latency under TCP head-of-line blocking**
(§3.8), not bandwidth.

### 17.3 Rates

```
TICK_HZ          = 60      // simulation + input
SNAPSHOT_HZ      = 20      // server -> client state
COMMAND_SEND_HZ  = 20      // client -> server, 3 commands per packet
INTERP_DELAY_MS  = 100     // = 2 snapshot intervals + TCP jitter headroom
HISTORY_TICKS    = 32      // lag compensation depth (~0.53 s)
MAX_REWIND_MS    = 250
PENDING_CMD_CAP  = 128
POS_EPSILON      = 0.02    // m — reconciliation trigger
```

---

## 18. Determinism policy

We are **not** building lockstep. We do not need bit-exact cross-platform floating point, and we
should not pretend to: Hemlock's math goes through libm, whose `sin`/`cos` results are not
guaranteed identical across platforms.

What we *do* need is **same-code, same-order, same-inputs reproduction on the same binary**, so
that prediction error stays in the noise and reconciliation is rare. That requires:

1. **Constant `TICK_DT`.** (§6.1)
2. **A fixed system order per tick.** Written down, in one place:
   ```
   sim_step(world, tick):
     1. apply queued commands (in player-slot order, then seq order)
     2. movement integration + collision
     3. weapons (fire, reload, cooldowns)
     4. projectiles
     5. AI
     6. damage resolution + death
     7. pickups / interactions / block edits
     8. world/chunk streaming decisions
     9. history capture (§7.3)
    10. effects pass (skipped when world.replaying == 1)
   ```
   Reordering these changes outcomes. Treat the order as API.
3. **Explicit, seeded, per-stream RNG.** `src/sim/rng.hml` implements a small deterministic
   PRNG (xorshift128 or PCG32) with **separate streams**: `rng_loot`, `rng_spread`, `rng_ai`,
   `rng_worldgen`. Each stream is seeded from `(world_seed, stream_id, tick, entity_id)` so a
   roll is reproducible without carrying state. **`@stdlib/random` is banned inside `src/sim`**
   (it uses a process-global seed — anti-pattern #10).
4. **Iteration order is by slot index, never by map key order or insertion accident.**
5. **Quantize the authority's own transform state to the wire grid** (§11.1) so client and
   server compare identical numbers.
6. **No `try`/`catch` control flow in the sim.** An exception path that only triggers on one
   machine is a divergence.

Test: `tools/replay.hml` records a command stream and the resulting per-tick position hash;
replaying it must reproduce the hash exactly on the same binary. Wire that into CI in v1. It is
the cheapest possible early-warning system for anti-patterns #1, #9, #10, #11, and #25.

---

## 19. Verification checklist (v1 exit criteria)

Multiplayer readiness is *testable in single-player*. All of these must pass before v1 ships:

1. `hemlock tools/simtest.hml` runs 10 000 ticks with no SDL linked. **(§6.2 wall intact)**
2. `tools/replay.hml` reproduces a recorded 10 000-tick position hash bit-for-bit.
   **(§18 determinism)**
3. `NS_LOOPBACK_SERIALIZE=1` runs the whole game with every command and snapshot round-tripped
   through the real `Packet` codec. Zero throws, zero field loss. **(§3.1, §3.2 caught early)**
4. `NS_FAKE_LATENCY_MS=120 NS_FAKE_JITTER_MS=30` is playable: no rubber-banding, no
   double-firing, no lost inputs, no camera snapping. **(§9 shape is correct)**
5. `NS_FAKE_LATENCY_MS=250` still fires the weapon on frame 0 with full cosmetic feedback.
   **(§12.3 layering is correct)**
6. Toggling `world.replaying = 1` and re-applying 8 commands produces zero sounds, zero
   particles, zero screen shake. **(§9.3 purity)**
7. A packet dump of one tick of `S_SNAPSHOT` decodes cleanly in `tools/packetdump.hml`, and
   every field's byte offset matches §11.3. **(protocol is real, not aspirational)**
8. No file under `src/sim/` imports SDL, wobbleweed, gn.hml, or `@stdlib/random`. **(CI grep)**
9. Every entity reference in the codebase is an `i32` id. **(CI grep for `.target =` patterns
   assigning objects — imperfect, but it catches the common case)**
10. Sim cost measured at ≤ 2.0 ms/frame compiled with the v1 entity count, with headroom
    reported. **(§17.1)**

---

## 20. Phasing (for when multiplayer starts)

| phase | work | risk |
|---|---|---|
| **P0** (v1) | everything in this document that is a *shape*: sim/render split, ids, commands, loopback, event bus, quantization, replay test | none — it's just how v1 is built |
| **P1** | `NetTransport` over gn.hml; the tick patch (§4.2); handshake; `S_WELCOME`; two clients seeing each other move; **no prediction, no interpolation** — deliberately ugly | low |
| **P2** | interpolation buffer + `INTERP_DELAY_MS`; remote entities smooth | low |
| **P3** | prediction + reconciliation for the local player; error smoothing | **medium — the hard one.** All of §9's v1 obligations exist to shrink this |
| **P4** | server-authoritative combat + lag compensation using the history ring | medium |
| **P5** | interest management, chunk streaming, delta snapshots | medium |
| **P6** | anti-cheat validation, flood control, reconnect, persistence | ongoing |

If P0 is done properly, P1 is a weekend and P3 is the only phase that requires thought.

---

## Appendix A — gn.hml constraint quick card

Pin this above the desk of whoever writes `src/net/`:

```
NEVER put a bool in a Packet.           -> determine_type THROWS
NEVER put a null in a Packet.           -> silently truncates the rest of the packet
NEVER call client.recv_packet().        -> drops every packet but the first in a frame
NEVER call client.run().                -> blocks forever
NEVER touch a Server from the thread     -> spawn() deep-copies it; you get a dead husk
      that spawned listen().                (_connections is empty, close() is a no-op)
buffer element max                       -> 255 bytes.   Blob stride 20 B -> 12 per blob.
packet payload max                       -> 65535 bytes
string element                           -> NUL-terminated; NOT a binary carrier
all floats on the wire                   -> truncated to f32. Quantize to ints instead.
integer wire width                       -> depends on the VALUE, not on the schema
one frame may hold many packets          -> batch: concat build() outputs, one send
select([ch], 0) -> null | { value }      -> the only non-blocking receive we have
```

## Appendix B — reproducing the measurements

Probes used for this document (Hemlock 2.8.1, gn.hml `22f937c`), all runnable with
`hemlock <file>` from `/home/nbeerbower/Projects/gn.hml`:

- **bool / null / cap probe** — `Packet.add` of `true`, of `null`, of a 256-byte buffer;
  round-trip via `build()` → strip 2-byte prefix → `load()`.
- **layout probe** — 32 entities encoded both ways, 2000 iterations of build+load+read, timed
  with `@stdlib/time.time_ms`, run interpreted and via `hemlockc`.
- **poll probe** — server replies with 3 packets concatenated into one frame; client drains
  `select([c._event_ch], 0)` from the main thread inside a 60 fps loop, then repeats using
  `recv_packet()` to demonstrate the loss.
- **spawn probe** — inspects `server._ws_server`, `_event_ch`, `_connections` on the main thread
  after `spawn(run_server, server, port)`.
- **tick probe** — patched `server.hml` with `tick_loop`; measured 20 ticks in 1004 ms and
  confirmed authoritative broadcasts from the tick callback reach a polling client.
- **conn probe** — attached `conn.player_id` in `on("connect")` and read it back in
  `on("packet")`; ingested 2000 packets in 65 ms interpreted.
