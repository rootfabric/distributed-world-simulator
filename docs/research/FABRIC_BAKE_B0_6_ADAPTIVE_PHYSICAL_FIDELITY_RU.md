# B0.6 — Adaptive Physical Fidelity

## Design Brief / ограниченный research work order

База: `1e8e74d6afafad294ddf10d68cb37efacc3ef3a1`, canonical main:
`5b4152958624be4e9cc40f2369ce32c4964f65c3` (registry generation 80).
Разрешение: COMPLEX2 RESEARCH CLOSED и явный bounded user work order A–E.
Риск: HIGH для локальной recovery/lifecycle границы; production authority не меняется.

B0.6 не создаёт solver, новый canonical owner, world scheduler или visual LOD.
CONSTRUCTION/MATTER продолжают владеть identity, matter, topology, damage,
connections, source revision, authority epoch и canonical physical inputs.
Выбор исполнения FABRIC остаётся derived, noncanonical, discardable.

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

## Известные начальные проблемы, требующие проверки

A принимал rehashed противоречивые report rows и не проверял тип fidelity до String.
Fresh import завершился exit 0, но обнаружил шесть унаследованных ECO `.tscn` с
UTF-8 BOM (line 1 Expected '['). Это не warnings и не B0.6 runtime failure:
причина установлена, ECO не меняется в этом work order. Focused FABRIC loads
проверяются отдельно на любые script/parse/runtime ошибки.
BRIDGE-2 closure ссылается на отсутствующий SYNC4 runner: восстановить точный
исторический runner/test без переписывания evidence и повторить regression.
