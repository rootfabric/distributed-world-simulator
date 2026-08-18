# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.8 AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1 SpeciesCatalog Contract;
- E2.2 Deterministic Evolution Bake Export;
- E2.3 Frozen-Catalog Transfer;
- E2.4 Environment Generalization Matrix;
- E2.5 Ecological Sorting vs Continued Adaptation;
- E2.6 Replicated Causal Experiments;
- E2.7 Cross-Seed Robustness — `docs/checkpoints/2026-08-18_ECO_EVO2_E2_7_CROSS_SEED_ROBUSTNESS_ACCEPTED_RU.md`.

## 1. Accepted research frontier

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
ECO.EVO2 / E2.1..E2.7     ACCEPTED
```

Frozen identities:

```text
E2.2 bake      45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
E2.2 catalog   5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
E2.3           82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
E2.4           ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
E2.5           942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
E2.6           1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd
E2.7           eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
```

## 2. Что теперь доказано EVO2

```text
frozen evolved catalog
        ↓
hidden target transfer                 E2.3
        ↓
environment generalization             E2.4
        ↓
sorting separated from adaptation      E2.5
        ↓
paired causal replication              E2.6
        ↓
cross-seed robustness                  E2.7
```

Это уже сильнее демонстрации одного удачного мира или одного seed: один frozen research catalog переносится в unseen environments, реагирует через causal ecology, continued adaptation отделена от простого sorting, а знак эффекта сохраняется на отдельном bounded seed ensemble.

## 3. E2.7 — Cross-Seed Robustness — ACCEPTED

Exact code-under-test:

`52f31ca58a77296d63b1642954659edcbd12b8fe`

Executable artifacts:

```text
orchestrator  f980a6132835cd2c483d5210615579ddccf7e618
protocol      8d28fb09ac6e3f8b46594b39f76db69c2b6f9b17
evidence      940ed657b7aa85758ac33088634d1ce5fdc4e673
test          334a833acd1d0bc32ee03f0977d764ff5e517196
runner        6da8290ec1944d704a778e3b1ce8910260e5b5cb
```

Frozen E2.7 protocol:

```text
cells                 DRY / WET
seed ensemble         S01..S10
positive threshold    >= 8/10 per cell
home threshold        >= 8/10 per cell
full-seed threshold   >= 7/10
q25                    > 0
median                 > 0
leave-one-out mean     > 0 after removing any seed
```

Observed evidence:

```text
exact executable closure  9 / 9 PASS
parser/preload             PASS
fresh process A            PASS
fresh process B            PASS
assertions                 290 / 290 PASS
logs                       byte-identical
log SHA-256                51c421e5e3f909cc265bd8180fa1bd9a56f1f5e3a1e727a5010a5667d40156a9
seed ensemble              a49ce9d6856e08e1e0a61f060a8019de61685cdc63b25229b3761c9e7c9d792f
aggregate                  eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
```

Result distribution:

```text
DRY  positive 10/10, null 0, reversal 0, home 10/10
     mean 0.229458431680, median 0.227109019511, q25 0.218691252321
     leave-one-out minimum mean 0.223908029973

WET  positive 10/10, null 0, reversal 0, home 10/10
     mean 0.386587470375, median 0.388500039215, q25 0.368469916498
     leave-one-out minimum mean 0.382313108540
```

10/10 — observed result, а не post-hoc acceptance criterion. Thresholds были зафиксированы заранее как 8/10 и 7/10.

E2.7 запрещает cherry-picking: seed нельзя удалить или переставить даже с пересчётом hash chain; semantic effect tamper отвергается повторным выводом ecological summaries/cross-environment contrasts из сохранённых final populations.

### Граница claim

E2.7 доказывает **bounded cross-seed robustness одного frozen catalog/protocol**.

Он не доказывает:

- formal statistical significance;
- robustness между independently evolved catalogs/bakes;
- production runtime authority;
- canonical species taxonomy.

PowerShell runner существует, но в Linux carrier нет `pwsh/powershell`; acceptance — `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 4. Current research route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ACCEPTED
    ↓
E2.4 Environment Generalization Matrix               ACCEPTED
    ↓
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
    ↓
E2.6 Replicated Causal Experiments                   ACCEPTED
    ↓
E2.7 Cross-Seed Robustness                           ACCEPTED
    ↓
E2.8 Catalog Persistence & Provenance                ← AUTHORIZED / NEXT
    ↓
EVO2 FINAL — Unseen World Challenge                  BLOCKED UNTIL E2.8 ACCEPTED
```

## 5. E2.8 — Catalog Persistence & Provenance

Следующий вопрос — не новая экология, а переносимость самого research artifact через durable boundary.

Минимальный E2.8 contract:

```text
accepted E2.2 SpeciesCatalog + accepted EVO2 provenance
        ↓
canonical typed serialization
        ↓
bytes / content hash / schema / version
        ↓
persist
        ↓
restore in fresh process
        ↓
exact semantic identity + provenance validation
```

E2.8 должен доказать:

1. deterministic canonical bytes для одинакового artifact;
2. exact content hash и typed schema/version;
3. restore без изменения `research_species_id`, lineage/genome identity и parent hashes;
4. provenance chain минимум E2.2 → E2.3 → E2.4 → E2.5 → E2.6 → E2.7;
5. fail-closed malformed/unknown/newer-incompatible schema policy;
6. byte tamper и semantic tamper rejection, включая пересчитанный outer hash;
7. fresh-process persist/restore determinism;
8. отсутствие promotion в production persistence authority — это research artifact persistence proof.

EVO2 FINAL нельзя открывать до accepted E2.8.

## 6. Production P4 — отдельная governance-линия

P4 branch lifecycle завершён, но это не global/main acceptance и не runtime merge. Нужны independent review/verifier freshness и main-owned promotion decision. EVO2 не получает production authority из P4.

## 7. Неподвижные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
adapted descendant != automatic canonical species
research persistence != production persistence authority
population truth != planet-wide individual entity truth
representation != ecology truth
```

Главный runtime principle остаётся:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 8. Current resolver

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.8 CATALOG PERSISTENCE & PROVENANCE
```
