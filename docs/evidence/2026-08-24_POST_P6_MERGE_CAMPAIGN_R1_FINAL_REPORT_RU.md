# POST-P6 REPAIR MERGE CAMPAIGN R1 — финальный отчёт

Дата: 2026-08-24 (UTC+10)
Директива: владелец («реализуй оба» + инструкция POST-P6 REPAIR MERGE CAMPAIGN R1)

## 1. Канонический main на старте миссии

```text
9ade3233f8d9f16b77edcc8cf273fe8e649d5637  (Merge PR #212, P6 implementation)
```

## 2. Финальные головы ремонтных веток

```text
repair/eg45-synthetic-journal-r1 ............ c2aab89d (fix 866a44ec + provenance 0001..0005)
repair/nx2-realtime-traffic-separation-r1 ... 93d41392 (fix b7292748/66deb469 + provenance 0001..0004)
repair/v0-p6-persistence-exactly-once-r2-integration 371a43f9 (порт всех 16 R3-коммитов,
                                              конфликтов ноль)
control/post-p6-acceptance-addendum-r1 ...... 3533d19e (аддендум приёмки, Вариант A)
```

## 3. Головы Reviewer/Verifier

```text
EG45: Reviewer PASS 8d5fec53 / Verifier VERIFIED f53cfec2
NX2:  Reviewer PASS 59991a45 / Verifier VERIFIED 85adabc6
P6-R3 (исходная база): Reviewer PASS d7bf17ca / Verifier VERIFIED 3730747f
R2-integration carrier: Verifier VERIFIED 6273bae6
```

## 4. Изменённые runtime-файлы (сводно по кампании)

```text
tools/network/eg45_synthetic_effect_journal.gd          (verbatim prior-result replay)
scripts/network/gateway/runtime/eg45_interaction_router.gd (envelope duplicate classification)
scripts/network/realtime/realtime_channel_policy.gd     (restore pinned RAW_ENET mapping)
scripts/runtime/networked_gameplay/p6/*.gd              (7 файлов R3 hardening)
tests/network/test_eg45_interaction_router.gd           (усилен: envelope + byte-equality)
tests/network/test_nx2_realtime_traffic_separation.gd   (chain-loader binding)
tests/runtime/test_v0_p6_*.gd, support/p6_r3_*.gd       (R3 набор + soak gate)
scripts/harness/acceptance_state.py                     (NEW: effective acceptance resolver)
tests/harness/test_v0_p6_acceptance_effective_state.py  (NEW: 4 обязательных свойства)
```

## 5. Оставшиеся открытые предикаты

```text
V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS ... environment-blocked (HA-001: операторская
    Windows MCP-сессия или Xvfb+MCP среда)
FULL_WORLD_CORE_REGRESSION_PASS ......... частично: 5 display-fenced тестов требуют
    канонического Windows/Xvfb прогона; всё исполняемое на этой машине - зелёное
ECO CRITICAL_DEPENDENCY_DRIFT по registry - маршрутизировано в ECO-lane
    (таргетная ревалидация/rebase потребителя после продвижения main)
test_h0_control_harness cluster (5E+1F) . PRE-EXISTING на canonical main
    (доказано прогоном на чистом 72684bc9): неизменяемая эпоха H0-1-R8 gen=77
    против advanced registry gen=80; отдельный control-infra ремонт
architecture-compat passport mode FAIL .. PRE-EXISTING на canonical main (аналогично)
```

## 6. Полный regression census (объединённое дерево)

287 шагов: оба бывших main-REDа исчезли (nx2 131/0, eg45 PASS); m6 и
world_boot_matrix — FLAKY (немедленные изолированные PASS); soak-timeout — by
design; main_scene_cli_all PASS; 5 display-fenced. Полная таблица —
docs/evidence/2026-08-24_V0_P6_R3_R2_INTEGRATION_VALIDATION_RU.md.

## 7. Display/MCP evidence

По-прежнему заблокированы на этой машине (нет дисплея/Xvfb/Breakpoint MCP host).
Требуется операторское Windows-окружение (HA-001).

## 8–10. Канонический main после ремонта и контроль r2

```text
POST_REPAIR_CANONICAL_MAIN = 72684bc9f243d7a458f4dbc6d460efc1c65d825e (запушен в main)
control/post-p6-sm1-activation-r2 = e8f83997 (запушен; от точного 72684bc9)
Все successor-base пины обновлены на 72684bc9: SM1 activation record
(main_declared_exact_successor_base/main_control_base), SM1 WO base_sha,
SM1 epoch base_sha, scheduler accepted_predecessor_base, work map
authored_against_main/product_base, train policy execution_base/
accepted_predecessor_base, registry programs.V0.branch -> r2 carrier.
Историческая P6-provenance (accepted_product_lineage_head,
accepted_p6_product_base, acceptance_main_merge, architecture_train запись)
сохранена verbatim как provenance приёмки.
Эффективная семантика приёмки машина-читаема: scripts/harness/acceptance_state.py
(ORIGINAL verbatim + PARTIALLY_RETRACTED reconciliation + successor gate),
тесты 4 свойств зелёные; старый all_required_predicates_complete=true не может
сам по себе авторизовать successor runtime.
```

## 11. SM1 runtime authorization

**НЕ авторизован.** Effective state: successor.runtime_mutation_authorized=false;
activation_gate=MAIN_OWNED_CONTROL_UPDATE_REQUIRED_AFTER_EFFECTIVE_RECONCILIATION;
sm1_eligibility() возвращает непустой список гейтов, включая явный EG5-гейт.
Director DISPATCH для SM1 не создавался; ветка feature/v0-sm1-* не создавалась;
lease не ротировался.

## 12. Статус EG5

**REPAIRED_ON_MAIN (по состоянию 72684bc9) — ожидает подтверждения владельца.**
Инструкция называла 3 кандидатных дефекта; canonical main уже содержит PR #215
(fb9b84f8 fix fresh hysteresis + тесты fe7327e3/891ada44):
1. нелинейный `probe_failures += int(probe_failures)` — паттерн отсутствует в
   eg5_edge_locator.gd на 72684bc9;
2. hysteresis против исторического скора — исправлена (fresh gateway scores,
   fb9b84f8);
3. смешение score/health metadata — покрыто телеметрийными изменениями PR #215;
   выделенный тест test_eg5_correctness_repair.gd зелёный на
   POST_REPAIR_CANONICAL_MAIN (проверено в этой сессии).
EG5 остаётся явным гейтом в sm1_eligibility() до подтверждения закрытия владельцем.

## 13. Финальная рекомендация

**READY_FOR_POST_REPAIR_CONTROL_REVIEW** — с двумя параллельными owner-действиями:

```text
1. Review & merge цепочки в canonical main (порядок значимости):
   control/post-p6-sm1-activation-r2 (e8f83997)  ← финальный control truth
   [уже в main] integration compose dd1d9171 + R2 port 07d9bca4→5787997f/6edbd706
   [уже в main через integration] eg45/nx2 repairs
2. HA-001: назначить операторскую Windows MCP-сессию (или Xvfb+MCP среду)
   для закрытия V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS и display-fenced пятерки.
Отдельные маршрутизированные линии (не блокируют SM1 напрямую):
   ECO-lane revalidation после продвижения main;
   control-infra repair для исторических epoch-vs-registry generation тестов;
   NX lane parse-blocker (test_nx_owner_movement_authority.gd) на её носителе.
```

Формальный PC0 на canonical main честно RED (registry-declared V0/ECO состояния +
pre-existing harness test debt) — это корректный fail-closed сигнал до merge
control r2 владельцем; ни один пункт не вызван данной кампанией (все доказаны
pre-existing либо являются прямой целью кампании).
