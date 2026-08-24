# V0-I1 movement recovery

Date: 2026-08-14

## Observed real-runtime failure

After the V0-I1 inventory convergence patch, the graphical client reached `CLIENT_READY` and received the canonical Item Graph, but ordinary movement did not mutate server state.

Observed client evidence:

- the client joined successfully;
- `input_batches_sent` and `messages_sent` grew continuously;
- the client later received `PEER_DISCONNECTED`;
- `M3_CLIENT_CONNECT_TIMEOUT` was emitted only after the disconnect and is therefore a secondary diagnostic, not the initial failure.

Observed server evidence:

- the peer joined successfully;
- `messages_received` stayed at the handshake/join level;
- `moves == 0`;
- `movement_commands_since_checkpoint == 0`.

This isolates the immediate V0 failure to the NX4 `PLAYER_INPUT_BATCH`/unreliable INPUT delivery path rather than keyboard capture or inventory UI state.

## Bounded V0 recovery decision

Do not rewrite NX transport inside V0-I1.

For the playable V0 integration checkpoint, Earth MVP temporarily uses the already-existing reliable M3 `MOVE` command at the historical 20 Hz movement cadence. Server authority and authoritative snapshots are preserved. The unreliable NX4 INPUT problem remains tracked as `V0-NET-001` and can be repaired independently.

## Camera-relative movement

EarthExplorer already exposes `get_surface_relative_yaw()` and the server tangent-plane convention is `+X` right and `-Z` forward at yaw 0.

The V0 adapter converts camera-local WASD to the server plane:

```text
W @   0 deg -> -Z
W @ +90 deg -> +X
D @   0 deg -> +X
```

Thus forward movement follows the horizontal direction in which the local camera is looking.

## Patch

```text
patches/v0-i1-movement-reliable-camera-relative.patch
```

Patch SHA-256:

```text
628932f2e9cf1ec46adb4c03b8129a0adf3fe68f9fc0351840dc54eb45059589
```

Expected application base: the local working tree after both the original V0-S1 MVP patch and `v0-i1-inventory-convergence.patch` have been applied.

## Validation completed before publication

Godot identity:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Checks:

```text
git apply --check                     PASS
git diff --check                      PASS
V0-I1 fake runtime                    PASS
inventory-open movement suppression   PASS
W yaw=0 -> server -Z                  PASS
W yaw=+90deg -> server +X             PASS
NX4 prediction path not used by V0    PASS
M3 reliable MOVE path used            PASS
```

## Real graphical acceptance

Restart server and all clients after applying the patch.

Expected server health while holding W:

```text
messages_received increases
moves increases
movement_commands_since_checkpoint increases
```

Expected gameplay:

- W moves forward according to camera yaw;
- S moves backward;
- A/D strafe relative to camera yaw;
- Tab still opens inventory and suppresses movement while open;
- closing Tab restores movement;
- server remains canonical authority.

If a real `PEER_DISCONNECTED` still occurs after this fallback, capture the server log around the disconnect. That is then a separate transport/lifecycle defect and should not be confused with the client-side secondary `M3_CLIENT_CONNECT_TIMEOUT` message.
