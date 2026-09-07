# HOLDOUT-R4 G1 — Repair Map измерительного стенда

Work Order: `FABRIC-HOLDOUT-R4-WO-001 / MEASUREMENT-P1-001`. Risk HIGH. Это поправка измерителя, не изменение физического subject, входных holdout-данных или допусков.

## Основание

Fresh review `5133712108`, finding `3951168046` для harness `9bb354c31d65600eccd6df713118e11a1f26f548`: evaluator вычисляет независимые токи каждого ребра/порта, но сравнивает только общий ток. Гипотетическая ошибочная реализация, сворачивающая bridge в эквивалентный R, могла бы пройти такую проверку. На фактическом frozen R3 все эти topology уже отвергаются; существующие capability FAIL не исчезают и не превращаются в PASS.

## Корень и границы

Owner дефекта — новый R4 evaluator `scripts/research/fabric_holdout_r4/holdout.py`, не canonical Construction/Matter и не существующий FABRIC0 solver. Probe уже сохраняет полные фактические `bridge.inspect()` snapshots без фильтрации. Missing field должен оставаться missing, нельзя производить якобы наблюдаемые branch currents из oracle или подставлять expected values.

R3 kernel `fd6e83b35301d7a15e92c55939654f1f95729730`, tree `314330d717db059cd9b9db32c5d6150097e1f2c3`, исходные 5477 файлов и все авторские G1 bytes заморожены. Это не G2, не kernel tuning и не свидетельство успешного R4.

## Исправление и тесты

Для графов с ветвлением, контуром, несколькими компонентами или более чем двумя boundary ports требуется фактический nodal/edge readback. Его отсутствие — FAIL измеримости, а не PASS по общему R. Для простой связной последовательной цепи с двумя концевыми ports единственный измеренный current_a определяет все branch flows; эта уже ограниченная scalar-проверка сохраняется. Если подробный readback представлен даже для series, он тоже полностью проверяется.

Явный измерительный contract: `electrical_observables` в фактическом snapshot содержит maps `edge_currents_a`, `port_currents_a`, `potentials_v`, с canonical `bond/` и `part/` IDs. Положительный ток ребра направлен по исходным a→b; port current — внутрь сети. Сравниваются все keys и конечные значения, каждый ток/потенциал с независимым Kirchhoff reference, KCL для каждого узла и баланс мощности. Для двухпортового power-coupled slider reference учитывает фактическую скорость и противо-ЭДС. Непредставленные независимые multiport inputs всё ещё fail-closed по контракту frozen R3.

Обязательные self-authored protocol falsifiers: missing readback; совпадающий общий ток при неверном bridge flow; потерянное ребро; неверный port current; неверный potential; корректный полный readback; scalar разрешён только для действительной простой series, не для path с внутренним boundary port. Эти проверки — calibration, не дополнительные независимые holdout cases.

Соседняя обнаруженная проблема runner: `.git/info/exclude` не существует как каталог у linked worktree. Использовать существующий `git rev-parse --git-path info/exclude`; проверить обычный checkout и fresh linked worktree. Это не изменение physics/replay semantics.

## Evidence и повторная проверка

Предыдущие exact observations на 9bb и raw logs остаются историческими. После поправки заморозить новый harness HEAD/TREE, повторить protocol + те же неизменные G1 cases + R3/R2/R1; явно различать успешное выполнение измерителя и физический FAIL. Сверить source/data hashes, опубликовать полный отрицательный результат и запросить fresh review. Нельзя закрыть HOLDOUT-R4 или открыть SCALE-R5 при capability/replay FAIL.
