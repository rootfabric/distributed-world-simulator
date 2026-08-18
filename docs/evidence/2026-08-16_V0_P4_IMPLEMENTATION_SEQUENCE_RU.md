# V0-P4 implementation sequence

After the canonical runtime gate is explicitly cleared, execute P4 in this order:

1. **P4.1 Exact-consume repair**
   - allow exact BuildPlan exhaustion (`>` rejects, `==` is valid);
   - partial material debit stays UPDATE;
   - exact debit becomes DELETE;
   - narrowly allow `DELETE + CONSUME_MATERIAL`;
   - prove membership removal and no zero-quantity projection.
2. **P4.2 Deterministic server allocator**
   - trusted server logical player identity;
   - `item/ore` only for R1;
   - requesting player's inventory only;
   - stable `(slot_index, item_id)` ordering;
   - multi-stack support;
   - insufficient/foreign/missing inventory rejection.
3. **P4.3 Live M4 Construction transaction port**
   - reference the same canonical M4 instance used by P3 mining;
   - no copied mutable ItemRegistry truth;
   - current-state preconditions / TOCTOU rejection;
   - atomic ItemGraph + Construction result.
4. **P4.4 Composition ordering**
   - create canonical gameplay/M4 owner first;
   - bind Construction transaction dependency before accepting clients;
   - prove M4 object identity shared by mining and construction.
5. **P4.5 M3 publication**
   - publish ItemGraph delta/full fallback after successful Construction transaction;
   - publish Construction event/snapshot from the same accepted operation;
   - never turn a committed operation into rejection because delta construction failed.
6. **P4.6 Exact-once**
   - replay lookup before allocation;
   - accepted duplicate returns same result;
   - same operation id/different payload conflicts;
   - no second debit or stage advance.
7. **P4.7 Atomic rollback**
   - injected failures around both domain commits;
   - no partial ore/stage/revision/checksum state.
8. **P4.8 Ownership isolation**
   - another player's ore cannot satisfy request;
   - client item nomination is ignored/rejected as authority input.
9. **P4.9 Live two-client + reconnect**
   - mine real P3 ore;
   - build using that ore;
   - observe on B;
   - duplicate operation no-op;
   - reconnect exact convergence.

Do not reorder P4.3 before P4.1/P4.2: otherwise the live adapter would be implemented against material semantics that are already known to be wrong.
