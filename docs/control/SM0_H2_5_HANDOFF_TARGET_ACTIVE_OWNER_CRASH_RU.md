# SM0-H2.5 — CRASH OF HANDOFF-ACQUIRED ACTIVE OWNER

Status: implementation/validation gate

Base evidence:

- H2.2: target crash after durable handoff commit — PASS;
- H2.3: source crash after durable retirement — PASS;
- H2.4: initial active owner crash after durable MOVE before ACK — FINAL PASS.

## Goal

Prove that active-owner recovery is symmetric across the authority boundary.

H2.4 crashes authority A while A is the initial owner. H2.5 must first complete a real A -> B handoff, allow B to become the normal active writer, persist a later client MOVE on B, kill B before that successful MOVE ACK reaches the client, restart B, and continue the same client through further handoffs.

This closes the gap where recovery could accidentally work only for the initial authority/process lifecycle.

## Required ordering

1. A and B start with active-owner recovery enabled.
2. Client joins A.
3. A -> B handoff completes.
4. Directory owner is B and authority epoch is at least 2.
5. Client sends a normal movement command to B after activation.
6. B applies the MOVE canonically.
7. B persists an `ACTIVE_OWNER` snapshot containing that exact movement boundary.
8. The successful MOVE ACK is suppressed by the deterministic crash layer.
9. The external PowerShell supervisor force-kills B.
10. A remains alive.
11. A new B process starts on the same gameplay/control ports and recovery directory.
12. B restores the exact active-owner generation.
13. The client retries the outstanding exact input.
14. B rebinds the transport session with a single ownership-epoch increment.
15. The duplicate durable input is not applied twice.
16. Client continues normally and completes the requested total handoff count.

## Fail-closed assertions

The gate fails if any of these occur:

- crash point occurs before one completed A -> B crossing;
- crash snapshot is not owned by authority B;
- crash snapshot directory authority epoch is below 2;
- durable player identity is not `player/a`;
- durable sequence/position differs from the crash event;
- successful MOVE ACK was delivered before the crash boundary;
- B survives the forced process kill;
- restart uses the same PID;
- exact recovery generation is not restored;
- client retry is not classified as `duplicate_durable_input=true`;
- recovered position changes because of the duplicate retry;
- ownership epoch does not increment exactly once on session rebind;
- A exits while B is being recovered;
- an invariant violation is emitted;
- identity changes are non-zero;
- requested handoffs do not complete.

## Scope

No new canonical persistence format is introduced. H2.5 must reuse the H2.4 `ACTIVE_OWNER` snapshot and replay semantics. The only new production-level behavior allowed is a narrowly required repair if the symmetric B path exposes a real defect.

This remains an SM0 bounded-lab gate and is not a declaration of global V0/main acceptance.
