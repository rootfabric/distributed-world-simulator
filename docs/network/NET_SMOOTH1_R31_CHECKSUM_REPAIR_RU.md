# NET-SMOOTH1 R4.1-P1 r31 — исправление двуслойного checksum при reconnect

Статус: `IMPLEMENTER_REPAIR_LINUX_PASS / WINDOWS_EXACT_PENDING / NO_MERGE`.

## Exact исходный дефект

Windows verifier на R4.1-P1 F1/F2 HEAD `e501cd764da7451fe36392e0f3a6008338f62f68` сообщил `r31-reconnect-roundtrip` **0/3 FAIL** из-за `COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH` на клиенте B после A-crossing/reconnect (базовый PR #755: 3/3 PASS). Не объявлять причинную связь F1/F2 доказанной, пока парные точные GUI-прогоны не завершены.

В каноническом Linux Godot `4.7.1.stable.double.custom_build.a13da4feb` код контрактов взят из исходного ZIP CHAR2; `git hash-object` исходного `compact_gameplay_snapshot.gd` совпадает с тем, что опубликован на PR #756 (blob `83837ddfedcb80ddfcf20c7320b99af87ee46491`). Воспроизведение независимо от серверного ACK-gate:

- Двойное числовое преобразование JSON: `-0.028065409691605588` → `-0.02806540969160558` (разница 1 ULP). SHA-256 исходного Dictionary != SHA-256 восстановленного JSON.
- При `server_tick=1956` на неизменённом контракте проходит source-валидация, но после реального Protocol Frame V2 encode/decode отклоняется и `COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH`, и вложенный `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` у full snapshot.
- Новый тест `test_net_smooth1_r31_compact_wire_checksum.gd` **RED 119 проверок / 2 ошибки** на оригинальном коде; **GREEN 121/121** на исправленном; проверяет два игрока, frame checksum, обе вложенные SHA, отсутствие мутации исходного authoritative Dictionary и отбрасывание фальсифицированных данных.

## Узкое решение (нет отключения checksum)

1. `player_state_snapshot.gd`: нормализовать только числовые поля сетевого DTO (position/velocity/orientation) к точной числовой фиксированной точке JSON парсера Godot (до четырёх scalar-roundtrip попыток); симуляционное состояние не изменяется. Все остальные поля, checksum-алгоритм SHA-256 и schema сохраняются.
2. `compact_gameplay_snapshot.gd`: использовать ту же scalar wire-нормализацию при создании массивов и yaw. Если она реально изменила представление относительно корректного source snapshot, пересчитать вложенный full checksum `c` из того же wire-visible player-state, затем компактный hash `h`. В обычном случае `c` остаётся исходным, без дополнительного копирования всей структуры.
3. Клиент по-прежнему обязан выполнять обе независимые проверки: `Compact.validate` и `FullSnapshot.validate`. Любая подмена значения или checksum строго отклоняется. Wire-схема и каналы не изменены.
4. Код `M3`, `M6`, `USER1`, ACK gate, Construction и перенос checkpoint не менялись.

## Реальные Linux доказательства (не Windows GUI)

- Exact Godot double, новый frame-level falsifier `121/121 PASS`.
- Scalar parser fixed-point: `18000/18000 PASS` для движений/углов.
- Full/compact 2× JSON round-trip fuzz: `2000/2000 PASS` (detached source и два peer), до исправления первый сбой при tick 1956.
- NX2 realtime: `131/0`; NX3: `6188/0`; NX4: `706/0`; NX5 interpolation: `6104/0`; NX5 integration: `49/0`; LIVE2 reliability: `2571/0`; USER1 seam bridge: `57/0`.
- M6 recovery contracts `126/0`, exit=0, в Linux host есть ранее известные teardown warnings про ObjectDB/resources; для strict Windows gate это не PASS, нужен exact Windows.
- Отдельный локальный headless synthetic microbenchmark (200 samples) исходный Full+Compact median ~1.15 ms, после scalar stabilization ~1.5 ms; **не использовать** как GUI performance acceptance. Измеренный p99 без Quaternius/Windows не сравнивать.

## Приёмка / falsifier на Windows

1. Exact HEAD/TREE этой repair-ветки и Godot SHA256, `cold import`, analyzer 20/20, **23 focused suites** (старые 22 + новый test) включая M6 crash/recovery, CHAR2, USER1, NX3/4/5. Строго: не исправлять путём отключения checksum или падения частоты рассылки.
2. `r31-reconnect-roundtrip` три независимых GUI LOCAL прогона по 120 s + 30 s warmup, реальный server+2 клиента Quaternius, A primary→secondary→primary, B reconnect при удалённом A, ownership epochs и authority counters, **0 checksum reject**. Отдельный clean `local` / `durable-commands` и negative 250 ms server/client stall.
3. Если возможно — exact paired e501cd baseline + repaired HEAD в непересекающихся worktrees со сходной нагрузкой хоста. Сравнить p99 кадров, компакт-снапшотные rejects, message/persistence tail. Production performance пока FAIL из-за синхронного M6 checkpoint; это не отдельный PASS.
4. Точные evidence SHA, screenshot, manifest, trace, `focused.json` path-diagnostics, Product Control `--candidate` error / `CANDIDATE_MAIN_DRIFT` отдельно.
5. Merge=false, VERIFIED=false до независимого Windows Reviewer/Verifier. Если все 3 roundtrip всё ещё FAIL — сохранить raw payload hashes и рассмотреть другой путь изменения транспорта, а не «исправлять» hash comparison.
