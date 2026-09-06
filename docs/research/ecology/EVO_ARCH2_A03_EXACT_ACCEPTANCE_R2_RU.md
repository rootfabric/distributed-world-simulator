# EVO ARCH2 A0–A3 — EXACT RESEARCH SOURCE ACCEPTANCE R2

Дата: 2026-09-06

## Verdict

```text
A0 Architecture Reconciliation              ACCEPTED
A1 Genome / Program / Body / Phenotype       ACCEPTED
A2 Bounded Modular Development               ACCEPTED
A3 Safe Structural Mutation + Lab V2         ACCEPTED

Overall: RESEARCH_SOURCE_ACCEPTED
```

Это принятие исследовательского source subject. Оно не является merge в main, production promotion, A4 activation или передачей architecture/foundation ownership.

## Exact immutable subject

```text
implementation branch:
feature/eco-evo-arch2-a0-a3-r1

HEAD:
6f7e267f287eae978d8dac8d54a1b730c4afbfd4

TREE:
d192f70952cbdeedb2ad58669542b5f8b5224067

immutable acceptance ref:
acceptance/eco-evo-arch2-a0-a3-r1
    -> 6f7e267f287eae978d8dac8d54a1b730c4afbfd4
```

После принятия runtime branch не двигался дополнительным documentation commit. Поэтому reviewed/tested runtime subject остаётся exact.

## Publication closure

Внешняя write-блокировка, ранее мешавшая A2/A3, больше не является blocker. A2/A3 опубликованы в Git. Первый полный source commit: `096723ec6162892b49c11839e07f8824d0d2c45d`.

Дальнейший repair train выполнялся обычными scoped GitHub/Git writes. Force-push/history rewrite не использовались. GitHub Actions не использовался как Git transport.

## Independent Reviewer

Первый Codex review exact subject `83da390463ff1c8dfcdcb4af62ee2bacc85ee4a8` нашёл три P1:

1. BOM-fix не имел отдельного durable write fence.
2. `BUDGET_BLOCKED` мог ошибочно считаться завершённым tick.
3. Import genome сохранял несвязанную lineage/family/gallery provenance.

Все три проблемы были занесены в Repair Map R1 и исправлены.

Fresh `@codex review` был запрошен явно для repaired HEAD `6f7e267f287eae978d8dac8d54a1b730c4afbfd4`. После завершения Codex не создал новых blocking findings и поставил `+1` на PR в `2026-09-06T02:27:43Z`.

Все три исторических P1 threads имеют repair reply и resolved.

```text
Reviewer verdict:
PASS / NO BLOCKING FINDINGS
```

## Fresh exact Verifier

Verifier checkout был создан отдельно от implementer workspace из:

```text
immutable VIS5 source baseline
+
content-addressed Git blobs exact remote subject
```

Проверено:

```text
remote Git blobs:        20 / 20 MATCH
mismatches:               0
manifest SHA-256:
9b031bd5c336b797bb6775669d1fe6aecdea2796e99957636bb4685a614660b9
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

### Exact focused acceptance

```text
EVO_ARCH2_A03_EXACT
86 / 86 PASS
```

Выполнено два fresh-process run. Логи побайтно одинаковы:

```text
SHA-256:
a03186ef32b7e3cf705ec70ddcdcab08388c8ed193acd9247ce88a7e3f2c363c
```

### Cold import

Fresh checkout с пустым `.godot`:

```text
PASS
Script Error = 0
Parse Error  = 0
ERROR        = 0
```

### Preserved VIS5 regression

```text
VIS5.0   87 / 87   PASS
VIS5.1   70 / 70   PASS
VIS5.2   57 / 57   PASS
VIS5.3  101 / 101  PASS
VIS5.4   92 / 92   PASS
VIS5.5  114 / 114  PASS
---------------------------
TOTAL   521 / 521  PASS
```

### Morphology Lab V2 graphical gate

```text
OpenGL Compatibility
Xvfb
llvmpipe
RC=0
Script/Parse/ERROR = 0
```

Log SHA-256:

```text
3dbf639373761c47019e3426406edcbaf6e25049fa6bf176e58e7de0cbff8ea2
```

Verifier в процессе отдельно обнаружил две ошибки — неверную test-fixture предпосылку capacity-block и Godot parser inference в новом UI label. Они были исправлены до финального прогона; финальный gate выполнен после fixes.

```text
Verifier verdict:
PASS
```

## Reviewer repairs

### RM-01 — BOM write fence

Создан bounded repair Work Order `EVO-ARCH2-A03-REPAIR-COLD-IMPORT-R2`, разрешающий ровно три legacy scene path и только удаление начального BOM.

### RM-02 — BUDGET_BLOCKED

Теперь:

```text
BUDGET_BLOCKED != TICK_COMPLETE
```

Blocked state сохраняет open `frame` и прежний tick. После explicit capacity resize тот же tick продолжается. Blocked preview/gallery candidate не принимается как завершённый phenotype.

### RM-03 — import provenance

Import создаёт новый diagnostic lineage root:

```text
family = IMPORTED
generation = 0
lineage = [imported biological hash]
gallery = empty
```

Следующий child обязан ссылаться на imported hash как parent.

## Project Control

Exact Project Control run:

```text
34006294208
HEAD = 6f7e267f287eae978d8dac8d54a1b730c4afbfd4
conclusion = FAILURE
```

Failure не переименован в GREEN. Причина — существующий global dependency drift:

```text
G:   critical Matter dependency drift
ECO: critical registry/Matter dependency drift
```

ARCH2-specific owner/scope violation этим run не показан.

Work Order A0–A3 изначально фиксирует:

```text
global_pc0_green_inferred = false
production_promotion      = false
merge_requires_human      = true
```

Поэтому global PC0 RED остаётся отдельным integration debt и не отменяет research source acceptance, но блокирует любую попытку выдать этот результат за production/main acceptance.

## What is accepted

- A0: архитектурная reconciliation и сохранение выводов аудита.
- A1: versioned genome / developmental program / body / organism state / phenotype contracts.
- A2: bounded modular development, persistent growth state, resource-paid operations, explicit block/resume semantics.
- A3: parameter/regulatory/structural mutations, bounded structural safety, Morphology Lab V2 с source-bound phenotype rendering.
- repair findings Reviewer-а.
- exact focused + preserved VIS5 regression + real graphical Lab gate.

## What is NOT accepted

- A4 environmental/world fields.
- canonical resource authority.
- production survival/reproduction.
- main integration.
- distributed ECO ownership.
- production persistence of V2 organism+fields.
- runtime feature merge.

## Next

```text
A0-A3 = FROZEN ACCEPTED RESEARCH SOURCE
A4    = NOT STARTED
```

Перед A4 нужен новый bounded Work Order от актуального main/dependency state. Не продолжать A4 как неявный commit поверх accepted A0-A3 subject.
