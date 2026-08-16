# V0-P4 branch boundary

This branch is intentionally stacked on:

`ef3ad5f0afc433802d639171d938e4720b3a46ec`

from:

`repair/v0-p3-visual-interaction-r1`

It exists to preserve P4 pre-build evidence and RED contracts while canonical main runtime activation is unresolved.

## Included

- P4 Design / Risk / Repair Map;
- exact-consume RED behavioral contract;
- exact-head focused runner;
- blocked checkpoint evidence.

## Explicitly not included

- PR #117 network repair;
- production/runtime P4 mutation before canonical activation;
- a second Item Graph;
- new persistence ownership;
- network authority changes;
- P3.1 acceptance claims.

Any future production commit on this branch must record the exact canonical activation/main audit that authorized continuation, or record an explicit refresh/rebase/transplant decision if this stacked line is no longer the valid implementation base.
