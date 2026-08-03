# ADR-019: Durable Matter authority handoff

## Status

Candidate, MW9.

## Decision

Store the complete regional authority directory and append-only transfer journal in one checksummed atomic checkpoint. Treat `COMMIT_DECIDED` as the irreversible commit point. Use exact logical-tick leases and full fencing-token equality for every write.

## Recovery rule

- complete a durable commit decision;
- complete a durable abort decision;
- abort any transfer that crashed before a decision;
- reconcile MW8 runtime state from the durable checkpoint idempotently.

## Representation data

RL1 summary manifests may travel with a handoff package as rebuildable cache hints. They never become authority or canonical Matter state.

## Rejected alternatives

- relying on MW8 in-memory `PREPARING` state;
- accepting a token checksum without validating the full token;
- using wall-clock lease expiry in canonical contracts;
- considering a pending file committed;
- choosing commit after restart when no durable commit decision exists;
- rolling back an already durable commit decision.

## Consequences

The local authority-directory service survives process crashes without split-brain. Multi-node consensus and cross-region atomic mutation remain separate milestones.
