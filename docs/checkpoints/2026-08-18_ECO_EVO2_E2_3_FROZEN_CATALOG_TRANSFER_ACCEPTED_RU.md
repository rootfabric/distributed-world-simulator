# ECO.EVO2 / E2.3 Frozen-Catalog Transfer — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Scope: `RESEARCH_ONLY_EVO2`

## Решение

`E2.3 Frozen-Catalog Transfer` принят по разрешённому для этого checkpoint human-directed exact-attached-Godot equivalent fresh behavioral execution gate.

Это **не** independent Reviewer/Verifier PASS: fresh process и clean exact carrier доказывают свежесть исполнения, но не независимость actor/session.

Следующий research step: `E2.4 Environment Generalization Matrix` — `AUTHORIZED_NOT_STARTED`.

## Exact code under test

```text
c7ee41371807ed7dbb75e7e1eae1587105873a26
```

Implementation:

```text
scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd
a886d179fe32a2bb531956923fd0cc59bbbb28c6
```

Acceptance test:

```text
tests/research/ecology/eco_evo2_e2_3_frozen_catalog_transfer_acceptance.gd
80e0d6ee5b6626af961f54f4d34678680126041e
```

Runner:

```text
RUN_ECO_EVO2_E2_3_TESTS.ps1
6a906d5a553e58388d43190f646594e94f69edfa
```

## Parent pins

```text
E2.2 aggregate  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
E2.2 bake       45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
E2.2 catalog    5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
P2.6 aggregate  3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
```

## Canonical executable closure gate

До behavioral execution был построен полный transitive preload/execution closure. Все 17 файлов совпали с exact Git blob identities: `17/17 PASS`.

Это закрывает важный класс ложной верификации: top-level implementation/test могут быть exact, но transitive dependency может оказаться stub/substitute. Для canonical behavioral evidence это теперь считается fail-closed condition.

## Exact Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Parser/preload:

```text
PASS
exit 0
ERROR lines 0
log SHA-256 d2c35978c69afc01dc5a1c78c7365f9bd704023eed36dcdaaa5ee66bbaab95b3
```

Fresh behavioral execution:

```text
process A exit 0
process B exit 0
59 / 59 assertions PASS
logs byte-identical
log SHA-256 7b2f89965bac13dc1238b053ecfd7b3544948eb6fa9941f3ca56d66ca79cad7b
```

## Frozen outputs

```text
aggregate
82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8

reachable target
1ddf0ee37869c7af7e1ebac393f9426b5d8163e89878af5ab84b834ae17d6fd1
reachable result
dc2e5b1c8a6c62fcfc7504a01f624cf635f43aa17160588696b0ddf159eb70a8
reachable final state
7d2035bd633e9df8ec67393cf8432fa21e764df027a4a0ce67559f554aa1af01
first colonization year
1

isolated target
70a1fbd963a0bb75856c0da2865c24ad04a22cb377314a102dc327862777a267
isolated result
dca9ae0b0e0fe7918b05e243b3164ca4de044921dc67f0471932352e4ffba4b6
isolated final state
3d9fa8f2dee0b6aa0186667568e318b99a50c410b1c810beff64652fd72af974
isolated status
VALID_NO_COLONIZATION
```

## Verification repair found by behavioral gate

Initial fresh execution failed deterministically on:

`shared-resource competition can alter composition after co-establishment`

Root cause: source-port environment was not neutral; its moisture value `0.58` gave one frozen strategy a negative resource balance, so only beta emitted propagules. The target and accepted parents were not at fault.

Repair:

```text
source-port soil moisture 0.58 -> 0.40
repair commit c7ee41371807ed7dbb75e7e1eae1587105873a26
implementation blob a886d179fe32a2bb531956923fd0cc59bbbb28c6
```

The source port remains target-independent; the repair only makes it capable of forwarding both already-frozen strategies into the causal transfer experiment. Full exact closure + fresh process verification was rerun after repair.

## Accepted research claims

E2.3 now proves within its synthetic E2.2 contract fixture that:

- the exact frozen catalog is transferred without mutation/evolution;
- target population starts empty;
- target identity/environment was absent from bake evidence;
- accepted P2.6 dispersal/establishment/turnover path is reused directly;
- equal suitability does not fabricate population truth;
- reachability changes the causal colonization outcome;
- reachable target colonizes and exhibits changing composition after co-establishment;
- isolated target completes validly without colonization;
- same input gives exact same history/result across fresh processes;
- no global RNG is consumed;
- frozen bake/catalog and target are not mutated.

## Boundaries

Not claimed:

- real multi-lineage evolution bake producer integration;
- canonical biological taxonomy;
- production authority;
- independent Reviewer PASS;
- independent Verifier PASS;
- PowerShell branch runner execution in this Linux carrier.

The equivalent execution reproduced the branch runner's parent, parser, fresh-process, PASS-marker and output predicates on the exact attached Godot and additionally enforced exact transitive closure identity.
