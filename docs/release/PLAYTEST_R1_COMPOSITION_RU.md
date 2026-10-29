# PLAYTEST R1: единая Earth Host/Join база, кандидат

База main: `8b504a2d854e891baa4688c6a8f25e9dc8c956d7`.
Сетевой донор: `38d62f5bc6143b6d5f4e0b95ff91adbb7e0a13a4`, Windows functional cap60 из PR #859.
CHAR2: #875 `d4ab242415c8b5cb3a48baf5f569b0b5c5e060b1`; recovery fix: #876 `a5be22a6d909f8ef6bc0db2cb9e94bf1c312234d`.

В прежней сборке #875 сеть main ошибочно представлялась как вся последняя NET-SMOOTH1: это неверно. Новая композиция переносит cumulative NET-SMOOTH1 исходники и включает проверенные canary-опции в нормальном Host/Join. Никаких изменений main-owned ECO/FABRIC/Harness policies. Конкретный состав проверяется SHA256 lock, а не старым запретом на любые runtime файлы.

R31 cap120 с checksum failures и F64-v2 не включены. #815 остаётся открытым; старые PERF_FAIL не становятся PASS. Основной пользовательский вход START.cmd, двухклиентный START_TWO_CLIENTS.cmd использует тот же профиль PLAYTEST_R1_SAFE60. M7 playground остаётся лабораторным исходником, не входом в поставку.

Сохранены совместимые postrestore tick resync + trusted port rebind. Перенос не является утверждением об их Windows приёмке. Исторические тесты #876 остаются, отдельного production merge нет.

Новые presentation/launch изменения: разные профили сервер/клиенты, явный source fingerprint; ограничение60FPS; ожидание world-ready перед клиентом Host; Join предлагает другое имя при живом локальном Host; direction/distance HUD подсказывает, где другой игрок, без teleport/yaw mutation. Свежий двухклиентный smoke использует уникальный slot; Continue/явный -Slot восстанавливают прежнее состояние.

Настоящие Linux Double focused + real ENet3-process результаты публикуются отдельно. Windows full ZIP требует реальных CC0 model+UAL1. Headless avatar provider fallback не является графическим доказательством. До финального Windows GUI READY_FOR_MERGE=false. Уже принятое main не меняется.
