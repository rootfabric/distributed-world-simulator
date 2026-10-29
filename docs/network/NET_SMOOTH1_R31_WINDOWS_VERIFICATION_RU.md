# NET-SMOOTH1 R3.1 — Windows exact verification (PR #753)

Статус: верификация и свежий Reviewer/Verifier поводок для
`repair/net-smooth1-r31-remote-owner-reconnect-r1`.

## Exact heads

| Предмет | SHA | Tree |
| --- | --- | --- |
| PR head до расширения (focused 20/20 r3) | `c8469f1a1c8acd5bc4957613399498d118430dd9` | `0db5d49071a793f452f8af26dc5c9d37aa507bfe` |
| Финальный evidence head (все прогоны ниже) | `797a21bf0` (ветка `repair/net-smooth1-r31-remote-owner-reconnect-r1`) | см. `git rev-parse HEAD^{tree}` |

Расширение сверх `c8469f1a1` — только orchestrator (tools) + аддитивные
automation-поля (`earth_mvp_app.gd`), без изменения канонической правды и
владельцев. Коммиты: `a114d96bd`, `1f272ffe9`, `797a21bf0`.

## Focused suite

- `artifacts/net-smooth1/r31-focused-final2` — 20/20 PASS на exact head
  `797a21bf0`, включая:
  - `test_net_smooth1_remote_owner_reconnect.gd` — PASS 37/37;
  - `test_v0_user1_product_seam_bridge.gd` — PASS 57/57;
  - `test_char2_network_avatar_client_presentation.gd` — PASS 28/28;
  - все 4 process-теста (M6/M7 recovery, NX2 physical channel).
- История прогонов: `r31-focused` (19/20 — артефакт порядка копирования
  Quaternius-ассетов после cold import, сам тест PASS 28/28), `r31-focused-r3`
  20/20 на `c8469f1a1`, `r31-focused-final` 19/20 с environment-flake
  `M6 A observed dedicated crash` (чужие зависшие Godot-процессы; после их
  удаления повтор `test_m6_dedicated_recovery_processes` — PASS 128/128).

## GUI: настоящий сервер + два клиента Quaternius

Все GUI-прогоны: `-Mode gui`, renderer opengl3, 900x600, asserts
`avatar/quaternius` + `QUATERNIUS_RETARGET` + `legacy_capsule_visible=false`
пройдены orchestrator'ом до фаз движения.

1. `-Scenario seam-stress` (`r31-gui-seam-stress`): функционально завершён,
   reconnect B поднял ownership epoch, ошибок инфраструктуры нет; FAIL по
   перф-порогам (server frame p99 122 ms) — консистентно с опубликованным
   R3-отчётом «FAIL perf, PASS functional».
2. Критический сценарий `-Scenario r31-reconnect-roundtrip`
   (`r31-gui-roundtrip-r4`, exact head `797a21bf0`):

| Стадия | Результат (server-pushed authoritative product seam state) |
| --- | --- |
| baseline | A: `region/user1/a`, authority_epoch=1, ownership_epoch=1, crossings=0, roundtrips=0 |
| A → secondary (только movement input, sprint +x) | `region/user1/b`, authority_epoch=2, crossings=1, movement продолжается (проверен дрейф позиции >0.5 m) |
| B disconnect/reconnect | B ownership epoch 1→2; A: region/epoch/crossings/ownership НЕ изменены — чужого handback нет |
| A → primary (movement -x) | `region/user1/a`, authority_epoch=3, roundtrips=1, ownership_epoch=1 (не менялся) |

Кроссинг/roundtrip подтверждены по авторитетным счётчикам, которые сервер
пушит клиенту (`m3_dedicated_server_runtime_p2._send_product_seam_state` →
`m3_graphical_client_runtime._accept_product_seam_state`), а не по локальной
позиции клиента. Отсутствие crossing = timeout = FAIL (fail-closed), ложный
PASS невозможен.

## Вердикты

- Функциональная часть R3.1 (reconnect + remote-owner authority): **PASS**.
- Перф-пороги LOCAL-профиля (frame p99 ≤25 ms и т.д.): **FAIL** на этой
  машине — server frame p99 110 ms в r4; класс evidence остаётся
  `GUI_LOCAL_CANDIDATE`, `independent_acceptance=false`. Разрыв CONNECTED у B
  в окне измерения — сам намеренный reconnect.
- Изменение orchestrator'а адресное: новый сценарий
  `r31-reconnect-roundtrip` (только `movement.set`, никакого телепорта),
  полный перф-цикл сохранён после roundtrip-стадий.

## Project Control CI

`CONTROL_DEVELOPMENT.ps1 -CheckConsistency`: `ok=true`,
`PROJECT_CONSISTENCY_ERRORS` отсутствуют. Три WARNING
`BRANCH_ADVANCED_SINCE_SNAPSHOT` (`ECO/integration`, `ECO/visual_repair`,
`FABRIC/bake`) — наблюдения устаревших snapshot'ов параллельных research-веток,
family-local, к NET-SMOOTH1/MVP отношения не имеют, не блокируют.

## Merge

Не выполнялся и не запрашивался (human gate). Перф-FAIL и
`independent_acceptance=false` исключают PASS-трактовку GUI-приёмки.
