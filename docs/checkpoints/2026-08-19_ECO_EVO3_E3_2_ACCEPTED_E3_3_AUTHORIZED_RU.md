# ECO.EVO3 / E3.2 — ACCEPTED; E3.3 — AUTHORIZED

Дата: 2026-08-19

Статус: **E3.2 ACCEPTED / E3.3 AUTHORIZED_NOT_STARTED / RESEARCH ONLY**.

## Принятый E3.2 target

- PR: `#155 — ECO EVO3 E3.2: ecological opportunity field — Repair R1`
- reviewed HEAD: `578981af36c2fe101925db024e6b7747c99806ab`
- executable freeze: `f276a5b29a39a00ae15c866a310b20f3ad9fe9c8`
- merge commit: `83f35d7abe2ebdea3e5afe175833817ad631c5e6`
- Project Control: `32214348326 / #997 — SUCCESS`
- Repair R1 aggregate: `ef0ed137bf8d2862f4c9cfacee0792dba8079e539daa4bfb7322d7d5da8afc9c`

Fresh independent reviewer verdict:

`PASS — SAFE FOR E3.2 MERGE/ACCEPTANCE AND SUBSEQUENT E3.3 AUTHORIZATION`

Durable review relay: PR #155 comment `#5340082691`.

## Закрытые findings Repair R1

1. Published Draft 2020-12 schema теперь реально описывает generated field и сохраняет fail-closed `additionalProperties=false`.
2. Canonical runner реально применяет `Draft202012Validator` к in-memory и fresh serialized field.
3. Negative matrix включает duplicate sample, snapshot/output `canonical_binding_resolved=true` и фактическую raw-fixture artifact попытку через accepted-snapshot loader.

## Accepted scientific identities

```text
contract hash
bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d

source E3.1 snapshot
2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00

field provenance
9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4

opportunity field
acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c

field artifact SHA-256
59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff

runner log SHA-256
b75830bb535830aac62825a54ceefc6e8b94fdbb64f9966c824fa74bb9681195
```

Accepted tests: `47/47`.

Scientific formulas and generated field are unchanged from the superseded candidate; Repair R1 repaired schema/evidence boundaries only.

## E3.3 authorization

Следующий разрешённый stage:

**ECO.EVO3 / E3.3 Research Ecology Decomposition**.

E3.3 MUST:

- consume the **accepted E3.2 opportunity field** as its ecological field input;
- produce deterministic `research_ecology_regions` / patch graph;
- use research-namespaced derived region/patch IDs;
- retain source E3.2 field provenance;
- remain `RESEARCH_DERIVED_NON_AUTHORITATIVE`;
- preserve deterministic ordering and fresh-process reproducibility.

E3.3 MUST NOT:

- bypass E3.2 by consuming E3.1/raw fixture as ecological-field truth;
- create or mutate canonical SD domains;
- use species identity as a partition/decomposition key;
- infer biome→species mapping;
- create population truth;
- claim production persistence/network/transaction/authority ownership.

Architecture source of truth remains `config/ecology/eco-evo3-planetary-ecology-compiler.v1.json`, stage `ECOLOGY_DECOMPOSITION`.

## Production boundary

`XFER1` remains `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`.

This acceptance authorizes only the next ECO research stage. It does not authorize production ecology binding, canonical SD ownership, or production runtime activation.
