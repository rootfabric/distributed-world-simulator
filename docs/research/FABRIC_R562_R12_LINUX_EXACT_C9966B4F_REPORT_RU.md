# FABRIC R5.6.2 R1.2 — опубликованный HEAD: implementer Linux exact PASS

PRODUCT_HEAD: `c9966b4f51dd623ddc6ec335b67452ccf96f7090`.
PRODUCT_TREE: `5a8db3a3ba25f1ecd86636b8461af7e8bf68cce3`.
Родитель: `d3e3d3b29c9ef068937048ef14aa6c7114700904`.
Эта evidence-ветка не изменяет product HEAD, main или PR #784.

## Причина Windows FAIL и проверенный ремонт

Старый `RunGodot([string]$Name,[string[]]$Args)` терял stage flags из-за имени
автоматической переменной PowerShell. В ProcessStartInfo оставались только
`--headless --path <project>`; игра запускалась вместо импорта. Новый runner
использует обязательный именованный GateArgs, проверяет точный argv десяти стадий
до Start, пишет argv/process receipts и сохраняет stdout/stderr до TIMEOUT throw.

[Отдельный diagnostic 39681246805](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39681246805)
воспроизвёл original RED и rename GREEN в PowerShell 7.6.7 на Windows и Ubuntu,
без запуска Godot. На опубликованном product HEAD
[CI 39682620061](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39682620061):
source-contracts SUCCESS; hosted Windows launcher-contract **75/0**,
PowerShell 7.6.7, Windows build26100; Python tamper matrix **19/19**.
Windows artifact 12384892601, SHA256
`b6717b23817f0916eefd57db243c6deb054771c0f889b5906f7a9ed2144ad234`.
Это тест запускателя, **не WINDOWS_GODOT_EXACT_PASS**.

## Настоящий локальный Linux exact

Source carrier artifact **12385625201** из CI 39682620061, ZIP SHA256
`ba7c27dd61808b0dcf013dce1b4aeed9f42f1e6d5d7c1f7b15abd91c1a36cf99`.
Обе внутренние SHA256SUMS строки проверены; клонирован настоящий **Git bundle**.
Detached HEAD/TREE совпали, tracked clean. Это не синтетическая identity исходного tar.
Канонический Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA256
`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
Неизменённый `RUN_FABRIC_R5_6_2_R1_TESTS.sh`: **EXIT 0**.

| Проверка | Результат |
| --- | --- |
| Fresh recovery import + обычный import | PASS, без игрового мира |
| Parse lifecycle | PASS |
| Lifecycle | 3 × 616/0, сырые логи побайтово одинаковы |
| Состав сценария | 10 owner commits, 30 reconstructed sessions, 42 binary receipts |
| Физические проверки | 14 независимых FULL oracle queries, 72 негативных случая |
| R2 regression | 626/0 |
| COM Recovery | 18/0 |
| R1 regression | 203/0 |
| BRIDGE-4 | 49 assertions PASS |
| Collector v2 | PASS |
| Identity before/after | Побайтовое совпадение |
| Исходный SHA256SUMS | 13/13 MATCH |
| Tracked status / diff --check | CLEAN |

Hash RESULT:
`9d41965820ce13967a5850fcbfca29b0acc41203cc4086f4952cd313e7a62cd0`.
SHA256 каждого полного lifecycle log:
`f5a211e8a2b5759f340da167989dc7140f2aae6fe54398fe3cc26c9b89efe140`.
Collector JSON: [evidence](evidence/FABRIC_R562_R12_LINUX_EXACT_C9966B4F.json).
Исходный manifest: [SHA256SUMS](evidence/FABRIC_R562_R12_LINUX_EXACT_C9966B4F_SHA256SUMS).

Полный архив в сессии: `FABRIC_R562_R12_EVIDENCE_c9966b4f.zip`, 3,407,542 байта,
SHA256 `90252c1fc6acffa8cbc2d59b7f2de77b75afffbc47f472812adb56266e3a81ea`.
Содержит все raw stage logs, 42 binary receipts, identity, collector, оба Windows
artifact ZIP, host console, handoff; 72 файла включены во внешний manifest.

## Оговорки и оставшиеся gates

В stdout/stderr оболочки есть посторонний traceback предустановленного
artifact_tool spreadsheet warmup при старте Python; он не изменил exit code.
Все Godot-stage logs без fatal/error/leak/gameplay markers. Повтор неизменённого
collector через `/usr/bin/python3 -S` дал exit0 и пустой stderr; evidence.json
побайтово не изменился. Полный исходный console не очищался и включён в ZIP.
Предыдущий host-timeout 120s и ошибка прав подготовительного запуска не являются
принятым прогоном; успешный fresh run — `r12-linux-exact-complete`.

**IMPLEMENTER_LINUX_EXACT_PASS**, а не отдельное независимое агентское заключение.
Self-hosted Linux job на момент проверки ещё QUEUED; он не объявлен SUCCESS.
Полный Windows Godot exact нового HEAD, fresh Reviewer/Verifier, PC0/directional
при необходимости и human merge gate остаются открыты. MERGE_READY=false.
Прямой Windows CLI repro с доказанно доставленными flags требует отдельного
повторения; issue #808 не закрыт. Физический runtime и engine pins не изменены.
