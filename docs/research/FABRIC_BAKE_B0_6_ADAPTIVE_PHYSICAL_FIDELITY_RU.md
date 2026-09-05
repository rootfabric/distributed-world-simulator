# B0.6 — Adaptive Physical Fidelity

## Статус: RESEARCH EXACT CLOSED

A–E реализованы и проверены дважды из новых чистых checkout на `2254b450b4d31832a6c143fc85096372679c6bc6`,
TREE `82532abb755b6b652b84a96ff5d92a8225cd8dba`. В каждом запуске: 26 suites, 47084 опубликованных assertion
executions с повторными predecessors, exit 0; fresh import fatal 0.
Closure hash: `892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584`.
Полное evidence: `validation/FABRIC_B0_6_CLOSURE.md`; machine replay:
`validation/fabric_b0_6/exact-replay.v1.json`.

## Design Brief / ограниченный research work order

База: `1e8e74d6afafad294ddf10d68cb37efacc3ef3a1`, canonical main:
`5b4152958624be4e9cc40f2369ce32c4964f65c3` (registry generation 80).
Разрешение: COMPLEX2 RESEARCH CLOSED и явный bounded user work order A–E.
Риск: HIGH для локальной recovery/lifecycle границы; production authority не меняется.

B0.6 не создаёт solver, новый canonical owner, world scheduler или visual LOD.
CONSTRUCTION/MATTER продолжают владеть identity, matter, topology, damage,
connections, source revision, authority epoch и canonical physical inputs.
Выбор исполнения FABRIC остаётся derived, noncanonical, discardable.

## Назначение и physical fidelity

B0.6 определяет, какое допустимое физическое представление следует исполнять
для объекта на authoritative evaluation tick. Опасность требует немедленно
вернуться к более полной модели; доказанная устойчивость разрешает постепенно
снижать стоимость исполнения. Дешевизна сама по себе не является доказательством safety.

Physical fidelity меняет активное физическое представление и его lifecycle,
а не число полигонов, текстуру или детализацию картинки. Камера, клиентский FPS
и wall clock не управляют canonical physics. В текущем selector policy цена явная
и может использоваться только после A; будущие visual/scheduler hints не смогут
расширить safe set. Server-authoritative tick задаётся внешним canonical owner.
DORMANT означает неисполняемое представление, но не отсутствие причинной связи.

## Выбранная архитектура

A — единственный safety evaluator: FULL_FABRIC → STRUCTURAL_BAKE → DYNAMIC_ROM →
HYBRID_BAKE → DORMANT. Первый unsafe уровень закрывает все более дешёвые.
Envelope сохраняет проверяемые safety witnesses отдельно от estimated_cost.
Хэши проверяют целостность DTO, но не доказывают истинность входного физического
сертификата: сертификаты обязан поставлять существующий physical owner.

B — детерминированный selector внутри safe prefix. SAFEST выбирает FULL;
HOLD_IF_SAFE сохраняет current, иначе ближайший более полный safe уровень.
CHEAPEST_SAFE минимизирует declared estimated_cost среди safe уровней, при равенстве
использует фиксированный порядок FULL→DORMANT. `minimum_safe_fidelity` обозначает
предел разрешённого упрощения, а не минимум произвольной функции стоимости:
при обычной монотонно убывающей цене эти два результата совпадают. Это разрешает
противоречие между «всегда minimum_safe_fidelity» и «стоимость может менять target»
без нарушения safety. Cost не влияет на safety_hash.

C — чистый reducer плюс единственный локальный execution slot: danger немедленно
повышает fidelity; demotion только на один уровень после consecutive-safe window
и cooldown. Измерение — authoritative evaluation ticks, не время компьютера.
Transition receipt содержит source binding, epoch, from/to, reason и hash.
BRIDGE-2 ownership contract переиспользуется для активного владельца; DORMANT
паркует HYBRID execution, но сохраняет единственную ответственность за causal wake.

D — recovery заново проверяет canonical RepresentationSourceRevision и A.
Runtime capsule не является world persistence и не сохраняет physical authority.
Устаревший, повреждённый или unsafe capsule отбрасывается. Cold restart начинает
с безопасного FULL и заново накапливает доказательство demotion. Warm restart
сохраняет counters только при точном binding. Незавершённая подготовка не считается
опубликованным transition; reducer не мутирует входные данные.

E — индексированный research runtime: полный проход O(N) при пяти уровнях;
локальные authoritative stimuli адресуют только соответствующие source IDs.
Campaign: 500/1000/2000, noise, sustained-safe demotion, safety promotion,
causal wake, deterministic work counters. Wall time — только наблюдение.

Альтернативы отклонены: камера/FPS как authority; случайный tie-break; wall-clock
hysteresis; глобальный rebake; сохранение physics_mode в canonical entity;
расширение BRIDGE-2 на новый solver; новый source revision/authority protocol.

## Проверки и границы

A–E focused runners, два fresh-process closure runs, BRIDGE-2, COMPLEX1B,
COMPLEX2 A–E/PERF/CLOSE и B0.4/B0.5 predecessors. Exact attached double Godot.
Предварительный PC0 и directional PC0: NON_RED (локальные отчёты в artifacts).
B0.6 отсутствует в main-owned product checkpoint catalog: product lease и
main acceptance не присваиваются исследовательской работе. Research exact closure
не означает production acceptance или IMPLEMENTER self-accept main checkpoint.
BRIDGE-3, COMPLEX3, FABRIC0.19, P8/P9 integration и merge в main вне scope.

## Исправленные исходные проблемы

A теперь проверяет типы и согласованность safety witnesses/report rows даже после
повторного хеширования изменённого envelope. D нормализует validated integer counters
после JSON disk roundtrip; canonical source не изменяется. SYNC4 runner/test восстановлены
byte-exact из historical 07b3bf9d, а не заменены пропуском regression.

Шесть inherited ECO .tscn имели UTF-8 BOM. Перенесён существующий минимальный repair
8758f3ede130e953461b27fff1df1aee27cd7e06: удалены только первые три bytes в шести headers.
ECO scripts/generation и physics semantics не менялись. Fresh import теперь полностью
чистый; отдельный load/instantiate smoke проверяет все шесть scenes.
Общий runner также отклоняет ошибку сохранения лога tee, ненулевой Godot exit, fatal
marker и отсутствие PASS sentinel. Все семь веток fail-closed plumbing протестированы.

## Как воспроизвести

Использовать только приложенный Godot 4.7.1.stable.double.custom_build.a13da4feb,
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.
Перед запуском экспортировать GODOT_BIN с фактическим путём к этому бинарнику,
сделать fresh import и проверить его strict validator; затем выполнить
`bash ./RUN_FABRIC_B0_6_CLOSE_TESTS.sh` дважды с разными B06_LOG_DIR.
`manifest.json` в каждом log directory содержит exact HEAD/TREE, hashes, counters,
assertion counts, exit codes и hardware-dependent wall times. Только deterministic
поля входят в closure hash. Исходные журналы приложены отдельным архивом с SHA-256
в checked-in machine evidence. Queued CI не выдаётся за runtime PASS.

## Что именно доказал масштаб

Количество 500/1000/2000 относится к локальным субъектам fidelity controller и
реальным BRIDGE-2 execution slots. Это не заявление о 2000 полностью интегрируемых
COMPLEX2 numerical machines. Численная динамика остаётся в predecessor solver tests;
COMPLEX2 A–E, PERF и aggregate CLOSE входят в оба полных прогона.

Следующий foundation этап — BRIDGE-3 FULL → BAKE → UNBAKE → FULL. Он не начат.
