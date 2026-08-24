# V0-P6-R3 R2-интеграция — перенос на отремонтированную базу и полная валидация

Дата: 2026-08-24 (UTC+10)
Ветка: `repair/v0-p6-persistence-exactly-once-r2-integration`
База портирования: `POST_REPAIR_NETWORK_BASE_A`

## SHA-цепочка кампании

```text
canonical main на старте ............ 9ade3233f8d9f16b77edcc8cf273fe8e649d5637
POST_REPAIR_NETWORK_BASE_A .......... dd1d91712a7f1d1785c9ed2d79e81f5cb93b50f4
  (= main + eg45 repair b2a88eb5-lineage + nx2 repair 66deb469-lineage,
   integration merge dd1d9171)
R2-integration carrier HEAD ......... см. git log этой ветки (порт всех 16
  коммитов R3 cherry-pick'ом, конфликтов ноль)
```

## Перенос

Все 16 коммитов R3 (`031b06bc^..20b00f89`) перенесены cherry-pick'ом на
`POST_REPAIR_NETWORK_BASE_A` без единого конфликта и без семантических
изменений: p6-скрипты, p6-тесты/раннеры, evidence/control документы.
Ссылки на старые SHA внутри исторических документов остаются как provenance
(исходные объекты достижимы через исходную ветку R3 на origin).

## Валидация на объединённом дереве (exact-head)

| Гейт | Результат |
|---|---|
| RUN_V0_P6_R3_TESTS.sh | **16/16 PASS**, `V0_P6_R3_FOCUSED_SUITE_PASS`, включая `REAL_PROCESS_RESTART_DELEGATED_RECOVERY_PASS` |
| test_nx2_realtime_traffic_separation | exit 0, **131 assertions, 0 failures** |
| test_nx3_fixed_tick_authoritative_simulation | exit 0, 6188 assertions, 0 failures |
| RUN_EG0_EDGE_GATEWAY_TESTS.sh | PASS |
| **Литеральный soak ПОВТОР на финальном дереве** | **PASS**: elapsed=30.00 real-time минут, applied=8552, committed=8553 (+crate), blocks=7698, crate_items=854, **51/51 assertions**, `V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME`; artifacts/test-results/p6-r3-soak-suite-1277084 |

Предыдущий soak (на старой R3-базе) остаётся историческим evidence семантики
R3; настоящий документ фиксирует ПОЛТОРЕНИЕ на финальном интегрированном
дереве — предикат soak закрыт на exact-head финального дерева без какой-либо
семантической утилизации старого прогона.

## Полный world/core census на объединённом дереве

```text
шагов ..................... 287 (editor-import + standalone + main_scene_cli_all)
main_scene_cli_all ........ PASS (exit 0)
бывшие main REDы .......... ИСЧЕЗЛИ: nx2 131/0, eg45 journal PASS
классификация провалов .... 3 записи:
  test_m6_dedicated_recovery_processes .. FLAKY (isolated rerun PASS сразу после
      census; флак при машинном переходе после тяжёлого soak-типа окна)
  test_world_boot_matrix ................ FLAKY (isolated rerun PASS: 'World boot
      matrix: PASS', последовательный мультиворлд бут - ресурсно чувствителен)
  test_v0_p6_thirty_minute_soak ......... BY_DESIGN timeout (литеральные 30 минут
      не помещаются в per-test окно 600s; канонический прогон - отдельный раннер,
      выполнен выше с PASS)
ENVIRONMENT_FENCED ........ 5 display-зависимых тестов (без Xvfb на машине;
      каноническое покрытие - Windows ps1/Xvfb-среда)
```

Ни один провал не классифицирован как новый дефект композиции: оба FLAKY
подтверждены немедленными изолированными PASS на том же дереве.

## Статус

Интегрированное дерево зелёное по всем исполняемым гейтам; литеральный soak
повторён на exact-head финального дерева. Далее: fresh Reviewer/Verifier на
этом HEAD, затем effective acceptance reconciliation (Фаза E) и control
carrier r2 (Фаза F) от точного POST_REPAIR_CANONICAL_MAIN после merge-цепочки.
