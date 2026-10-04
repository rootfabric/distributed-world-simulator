# FABRIC R5.2 / T16 — NO_SAFE_BAKE

Статус: IMPLEMENTER CANDIDATE; exact evidence публикуется отдельно с HEAD/TREE. Fresh independent Reviewer и Verifier обязательны; этот документ не является independent acceptance.

База: T15 merge `d53352bca414f806a1096633ea683ba21b955083`, tree `ce5c0faa0e67e847cb1a4557059790eb22024754`. Это research lineage после #732, не production/main integration. Work Order: [T16 R1](FABRIC_R5_2_T16_WORK_ORDER_RU.md).

## Контракт

Попытка BAKE не имеет права уничтожить неизвестное внутреннее состояние или скрыть событие. Новый `r5_t16_no_safe_bake_runtime_v1.gd` выполняет bounded negotiation и ровно один выбранный physical step:

```text
canonical source + caller-owned FULL state + boundary/event requirements
    ↓ provenance / source / authority checks
    ↓ disposable candidate preparation
    ↓ exact reconstruction + observability + events + error/step certificate
    ↓ native artifact validation against current live source
BAKE_READY → один COMPACT step
NO_SAFE_BAKE → один FULL step, без публикации declined artifact
```

У gate нет registry, owner, revision counter или собственных физических законов. Adapter — trusted in-process код, а не граница безопасности для произвольного плагина. Он получает копии входов. Выполняемые ядра — неизменённые T4 compiler/runtime/full reference; T1 отдельно проверяет singular reduction. T1–T15 и общий physical core не изменены.

`success=true` у negotiation-result означает валидный отчёт о решении, а не успешный физический шаг. Потребитель обязан читать `status`, `execution`, `execution_error`:

| execution | Смысл |
|---|---|
| COMPACT | Принят artifact, выполнен один compact шаг. |
| FULL | BAKE отклонён, detailed источник реально продолжил эволюцию. |
| CANONICAL_HANDOFF_REQUIRED | Нет допустимого source/authority; ни один executor не запущен. |
| FULL_STEP_REFUSED | Detailed state/solver не допускает шаг; не генерировать значения вместо неизвестных. |
| COMPACT_STEP_REFUSED | Ошибка выбранного compact шага; artifact не выдаётся, автоматического второго FULL шага нет. |

В этих research executors шаги являются caller-owned/pure. Для будущих executors с внешними side effects понадобится отдельный транзакционный handoff; T16 не утверждает, что уже решает этот integration contract.

## Исполняемый physical falsifier

8 слоёв × 16 независимых lanes = 128 source cell temperatures. Успешная редукция хранит 8 layer temperatures. Это bounded вариант существующего T4; исходный T4 8×64 и его тесты не переписаны.

Hidden-mode case задаёт 304 K и 296 K в двух lanes с тем же средним 300 K. Compact mean не содержит это состояние, поэтому BAKE должен отказать. Отдельный case с разницей 1e-9 K проходит старую tolerance-проекцию T4, но T16 требует exact binary reconstruction и не позволяет тихо стереть даже эту разницу.

При FULL используется настоящий source-cell solver. Проверяются exact next-state/event equality с прямым вызовом неизменённого Full reference, сохранение всех 128 scalar states и восемь следующих detailed ticks. Это независимый путь orchestration над общим ядром, **не второй независимо разработанный physics solver**. Threshold crossings наблюдаются на конкретных cells и входят в trace hash.

## Сертификат одного шага

Для каждой cell вычисляется rate `r_i = sum(G_ij) / C_i`. Проверяется margin `1 - dt * max(r_i)` относительно caller requirement. Near-critical case — приближение к границе монотонности явного теплового шага; это **не доказательство поведения произвольных нелинейных/хаотических систем**.

FULL при необходимости использует `ceil(dt * max(r_i) / 0.5)` substeps с неизменённым суммарным dt. Лимит 4096 и проверка finite выполняются до преобразования к int. Превышение work budget даёт явный отказ, не пропущенную эволюцию.

Boundary-error bound состоит из расхождения реально полученных full/lumped коэффициентов stencil на текущем bounded input/state и roundoff envelope `gamma_(lanes+64) * scale` для double. Проверяются положительность/finite, budget, actual compact-vs-FULL output error. Это bounded one-step discrete-model certificate, не global trajectory certificate и не оценка ошибки непрерывной физики. Adapter отвечает за обоснование сертификата; gate не доказывает математические свойства произвольного adapter.

## Негативная матрица

20 cases: hidden mode; lossy reconstruction; missing reconstruction; insufficient observability; hidden event; unsafe error budget; nonfinite error certificate; near-critical step; unsupported symmetry/topology; stale frontier; mutated source with stale capsule; corrupt capsule; physically stale artifact; cross-authority; authority epoch mismatch; canonical source mismatch; missing detailed state; invalid physical state; compact-step failure; singular elimination.

Последний case напрямую вызывает существующий T1 Schur reducer, требует `NO_SAFE_BAKE / RANK_DEFICIENCY` и пустой artifact. Сингулярная сеть не объявляется успешно решённой: disposition `FULL_SOLVER_DIAGNOSTIC_REQUIRED`. Остальные 19 проходят новый negotiation gate. Authority cases не обходятся через FULL; недостающий state не восстанавливается нулями.

Положительный gate: восемь различных uniform-layer начальных состояний, команд и dt. Они обязаны реально принять capsule, выполнить один compact step без source-cell execution и уложиться в вычисленный certificate при сравнении с FULL. Gate поэтому не может пройти тесты стратегией «всегда отказывать».

## Evidence contract

Acceptance содержит 533 assertions; expected case matrix зафиксирована в collector. Три отдельных процесса должны дать одинаковый RESULT payload, включающий SHA256 физических continuation traces/events и положительной trace. Measurement Harness R5.0 измеряет стадии отдельно; timing/RSS не входят в deterministic identity и не объявляются performance budgets.

Collector fail-closed проверяет точный набор cases, причины/execution, фактические executor/compile counts, source work, state preservation, event/trace hashes, finite numerical bounds, три RESULT, fatal markers, exact regression markers и неизменность HEAD/TREE/engine до и после. Повторяющиеся JSON keys, NaN/Infinity и неполная матрица не принимаются.

Ожидаемый bounded campaign: 13 FULL cases, 104 continuation ticks, 1792 source-cell updates на первоначальных FULL steps; counters у каждой попытки проверяются отдельно. 223 cell-threshold observations относятся к нескольким независимым сценариям, не к одному игровому миру.

## Запуск

Linux, dedicated clean checkout:

```bash
GODOT_BIN=/absolute/path/to/canonical-double-godot \
T16_EVIDENCE_DIR=/absolute/empty/evidence-dir \
bash RUN_FABRIC_R5_2_T16_TESTS.sh
```

Windows, PowerShell 7, dedicated clean exact-subject checkout:

```powershell
./RUN_FABRIC_R5_2_T16_TESTS.ps1 -GodotBin $PinnedGodotPath `
  -ExpectedHead $FrozenHead -ExpectedTree $FrozenTree `
  -ExpectedHash $LinuxResultHash -EvidenceDir $EmptyEvidenceDirectory
```

Runners: fresh import; check-only; 3 T16 processes; неизменённые T15/T14/T13.5/T13/T12; Python evidence tests; exact identity before/after. Новый Windows carrier должен checkout именно product, а не control HEAD. Чужие Godot/runner процессы не завершать. Source CI доказывает только additive scope и Python contracts, не runtime PASS.

## Границы и следующий gate

Это negotiation + one-step checkpoint, **не** компиляция на каждом steady tick. После принятия capsule существующий compact runtime остаётся steady executor; дальнейшая интеграция держателя model и re-negotiation trigger — R5.3/R6. Автоматический перенос всех nested instances, production scheduler, persistence/restart, network authority handoff, collision/fracture, универсальный reducer и SHIP-LAB не реализуются в T16.

Далее: implementer exact Linux/Windows → fresh independent Reviewer → fresh independent Verifier → explicit human merge. Затем R5.3 Recursive Hierarchical Execution; roadmap upstream не переписывается из candidate-ветки.
