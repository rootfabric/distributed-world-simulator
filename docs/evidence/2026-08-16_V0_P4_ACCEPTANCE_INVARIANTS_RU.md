# V0-P4 acceptance invariants

The implementation candidate must prove all of these simultaneously:

```text
ONE_LIVE_M4_ITEM_GRAPH
REAL_P3_ORE_INPUT
SERVER_DERIVED_ALLOCATION
DETERMINISTIC_MULTI_STACK_SELECTION
EXACT_CONSUME_DELETES_STACK
INSUFFICIENT_REJECTS_BEFORE_MUTATION
FOREIGN_OWNERSHIP_REJECTED
ITEM_GRAPH_PLUS_CONSTRUCTION_ATOMIC
DUPLICATE_ACCEPTED_OPERATION_EXACT_ONCE
OPERATION_ID_PAYLOAD_CONFLICT_REJECTED
POST_COMMIT_REPLICATION_FALLBACK_SAFE
RECONNECT_CONVERGENCE
NO_NEW_PERSISTENCE_OWNER
NO_PR_117_IMPLICIT_INTEGRATION
```

A candidate that builds correctly but keeps a fixture/shadow material store is a FAIL. A candidate that consumes ore but does so as a separate Item command before/after Construction is a FAIL. A candidate that cannot roll back both domains together is a FAIL.
