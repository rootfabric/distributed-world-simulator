# [DRAFT] ENGINE48 Linux R1 — 7 guard-коммитов Ubuntu (Godot 4.8 beta1 double)

**FROM:** `feature/engine48-linux-r1` → **TO:** `feature/engine48-beta1-double-migration-r1` (НЕ main)

Готовится к открытию API-авторизованным executor'ом (локальный PAT Ubuntu — read-only;
ветка уже опубликована через SSH-ключ `rootfabric` этой машины).

## Идентичность

| величина | значение |
|---|---|
| BASE | `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` |
| BASE_TREE | `3c0a04c78eca918717e8e836b1c1bf2836cb5596` |
| HEAD (издан, подтверждён GitHub) | `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` |
| TREE (HEAD^{tree}) | `0d49082be99b0bb125d26c28f45ac19840426f0d` |
| коммитов поверх BASE | ровно 7 |

## Семь коммитов

1. `29d2e4af4678745d59e2dbc7a4f8902121851702` fix(engine48): pin Linux runner guards to Godot 4.8 beta1 double build
2. `231b3e9b2b7f7d7810c6729dd59b4a1db3ed075d` chore(engine48): adopt Godot 4.8 generated import metadata and script UIDs
3. `24fc10ee1dedfe5b49d8b819fe7ef6591f5c0750` fix(engine48): pin Linux graphical integration engine to 4.8 beta1 double
4. `c1d3070fec0cd2cb87d002bb8bd3205bd0d7a4ca` fix(engine48): allow Xvfb location override in Linux SM1 graphical gates
5. `5f71900ff2668f32b42588581b80eaa89e1c876e` fix(engine48): resolve Xvfb via XVFB_BIN in Linux graphical process gates
6. `841cf13e2c3435a04da30a65062a722ed6f704c2` fix(engine48): align P7.1 gate summary pins with 88-assertion current test
7. `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` fix(engine48): align MW10 suite marker pins with current assertion counts

## Исправленные guards (без ослабления проверок)

- Пины точной строки версии `4.7.1.stable.double.custom_build.a13da4feb` → `4.8.beta1.double.custom_build.4d10419ca` в 15 `.sh`-раннерах — строгие проверки сохранены (exit при несовпадении).
- `PINNED_ENGINES["linux"]` → SHA256 редактора 4.8 `4d72a93e…` (`EXACT_DOUBLE_ENGINE_REQUIRED` сохранён).
- `XVFB_BIN` override в 3 `.sh` и 13 `.gd` графических гейтах (rootless Xvfb; fallback `/usr/bin/Xvfb`).
- Пины счётчиков assertions обновлены **только вверх**: MW10 184→201 и 51→53; P7.1 83→88. Дрейф заранее присутствовал идентично на 4.7.1 (paired-проверка); строгий exit-on-mismatch сохранён.
- 4.8-адаптация импорта: 13 `*.png.import` + 296 `*.uid` (детерминировано, byte-identично при двух независимых импортах).
- Продуктовый код `scripts/` не изменялся (только новые `.uid`-сателлиты); ни один порог/таймаут/assert не ослаблен.

## Движок и проверки

- Godot `4.8.beta1.double.custom_build.4d10419ca`, собран из исходников (`4d10419cacd6…`, tarball SHA256 `6d49c02e…`), precision=double, arch=x86_64.
- Editor SHA256 `4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f`; template_debug `af1e29d1…`; template_release `fffb8f53…` (полная таблица `artifacts/engine48/linux/build/binary-sha256.txt`).
- Headless (R1, PASS): 8-тестовая Linux-матрица, MW0 (2011), MW4 (187), MW10 (201+53), SM1 L0/fault-matrix/graphical/authority-recovery/gateway-restart, P7.2/P7.3/P7.4/P7.5, PLAYABLE_SEAMLESS, C22 (75 assertions).
- M7 live: dedicated server + 2 графических клиента, профили LOCAL и BAD_MOBILE, reconnect без дублирования identity, server-restart mid-session с восстановлением — PASS.
- Paired PERF 3+3 (4.8 vs локально собранный 4.7.1): регрессий 4.8 нет; worst server stage −7.7% в пользу 4.8, CPU parity, RSS +2.9% стабильно, FPS p50 16/16 (llvmpipe-bound).
- Pre-existing Linux findings (не регрессии 4.8, paired 4.7.1 = идентично): MVP4/MVP5 gateway init `MVP3_BACKEND_DISCONNECTED`; earth product-seam `M3_CLIENT_CONNECT_TIMEOUT` (см. #804).

## Ограничения

- GUI/перф: **llvmpipe software GL под Xvfb** — GUI-доказательство техническое; REAL_GPU_EVIDENCE = INSUFFICIENT_EVIDENCE. Аппаратная GPU-верификация — отдельный шаг независимого Verifier.
- NET-SMOOTH1 p99 ≤ 25 ms на этом снимке неизмеряем (инструментирование net_smooth1 не смержено) — фиксируется как INSUFFICIENT_EVIDENCE, не как PASS.

## Evidence

- Полный отчёт R1: `artifacts/engine48/linux/ENGINE48_UBUNTU_REPORT.md` (в дереве НЕ закоммичен; публикуется в evidence-ветке `diag/engine48-linux-r2-report` и архиве).
- R2-аддендум идентичности (TREE vs файловые SHA256): `ENGINE48_UBUNTU_R2_PUBLICATION_ADDENDUM.md`.
- Независимая верификация R2: `artifacts/engine48/linux/verification/INDEPENDENT_VERIFIER_REPORT_R2.md` (свежий Verifier, отдельная сессия).
- Дефект #804 `M3_CLIENT_CONNECT_TIMEOUT`: paired на обоих движках; исправление — вне ENGINE48-миграции.

Merge-гейт: этот PR не просит слияния; интеграция с Windows #806/#810 и решение о merge — отдельные human gates.
