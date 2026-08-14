# ECO P4.6 — Interest + Client Read Model — PRE-ACCEPTANCE CANDIDATE

Статус: `CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_P4_5_ACCEPTANCE_AND_FULL_CHAIN_INTEGRATION_PENDING`.

Parent P4.5 frozen aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.

P4.6 создаёт только server-authoritative **read projection**. Он не передаёт canonical ecology ownership клиенту и не добавляет RPC/write API.

## Реализовано

- bounded `RegionSummary` из валидированного P4.5 ownership;
- lineage biomass aggregation и deterministic dominant-lineage selection;
- явные `ecology_generation`, processed/observed time и catch-up debt;
- canonical interest projection по sorted unique region ids;
- explicit missing regions;
- duplicate authoritative region states fail-closed;
- monotonic client cache update policy по ownership epoch → generation → observed horizon;
- stale/replayed/rollback read updates reject;
- detached dictionaries: изменение read model не мутирует P4.5 ownership;
- deterministic summary/interest hashes;
- no RNG, no wall clock, no network transport.

## Targeted exact-Godot evidence

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Adapter probe с exact P4.5 kernel: `PASS (35 assertions) x3`, byte-identical.

```text
log_sha256=456b85e506d75cab4e957dcf9a1e31371a7bd8e8aa021cef2311100e9e4ed343
aggregate_hash=861e1e7d9f6b14cd33ffdfeb382cd6b6a5340fb19438767d4cf2de5a60ebf459
summary_hash=bbc6391ec84061bf62b26c1c06cf7fdcc61eb0633d33d1a19cdfb37614a1459b
interest_hash=da44554dc20c29a3266c454b3af6a29b2f1963d805b29d3b816f4fba03865298
```

Committed unit contract: `PASS (24 assertions) x3`, byte-identical.

```text
aggregate_hash=88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2
summary_hash=9b3270edcb178dcb681de63223c0d5f5c8c851d90856f94d660e76c125b4521f
interest_hash=875fce66118cc2810755549e3663d92575b4942e8a42dd00bd710c2acdc57864
```

## Gate boundary

P4.6 is not accepted. P4.5 must first pass its committed full-chain gate and lifecycle acceptance. After that, P4.6 runner executes direct P4.5 regression plus P4.6 A/B. A final real-P4.5 ownership→read-model integration probe is required before P4.6 lifecycle acceptance.
