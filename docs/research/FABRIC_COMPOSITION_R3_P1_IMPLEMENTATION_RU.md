# COMPOSITION-R3 — P1 repair / implementer evidence map

Статус: IMPLEMENTED / FRESH_INDEPENDENT_ACCEPTANCE_PENDING. Risk: HIGH.
Work Order: FABRIC-COMPOSITION-R3-WO-001 / P1-REPAIR-001.
Pre-repair subject: ddf2b2c51d76d0afe3331cfaf17a6d4e7fb86054.
Repair Map: FABRIC_COMPOSITION_R3_P1_REPAIR_MAP_RU.md.

## Изменённые поверхности и владельцы

Новый stateless R3 event-bracketing adapter; оба R3 callers (обычный advance и post-guard FULL remainder) используют его. Существующий FABRIC0 RK4/algebraic/event kernel сохранён byte-for-byte. Construction/Matter canonical truth, authority и revision contracts не менялись. Compiler max_step_s НЕ уменьшен, capacities НЕ изменены ради PASS, прежние tests НЕ ослаблены. R3 runner дополнен отдельным regression suite.

## Алгоритм и предел доказательства

Affine R3 flow даёт degree-four RK4 trial polynomial effort по доле шага. Stationary points изолируются по производным, включая повторные корни; поиск не зависит от регулярной сетки substeps. Между stationary points bracket локализуется фактическими пробами прежнего DAE integrator. После каждого mode event поиск остатка начинается заново. Candidate изолирован до успешного возврата; nonfinite, polynomial/probe mismatch, неразрешимое касание и event-budget failure не публикуют состояние.

Это гарантия event bracketing для численной RK4 trajectory в зафиксированной линейной грамматике R3 с явными tolerances, НЕ точное решение произвольной continuous/nonlinear physics. Discretization error остаётся наблюдаемой и проверяется уменьшением шага; near-tangent event time более чувствителен, чем обычный crossing. Floating uncertainty около threshold вызывает fail-closed, а не silent no-event. Нет claim об ускорении, state-count reduction, nonlinear/3D/thermal/scale/holdout или certification других исторических DAE consumers.

## Red → green

На исходном exact-tree архиве P1 воспроизведён в 4 вариантах: ±voltage × FULL/BAKE, dt=0.015 s, capacity=4.0280 N. До fix: 254 assertions / 4 failures, proposal отсутствует.

После fix: transient suite 611 assertions / 0 failures. Проверены исходный и более узкий пик capacity=4.02837 N, шаги 0.014/0.015/0.016 s, отрицательный знак, guard-only пик без failure, peak ниже capacity без ложного failure, guard/failure в одном внешнем шаге, actual FULL remainder, отказ/дубликат canonical commit и cold reconstruction proposal/event ID. Root isolator отдельно проверен с тремя и повторным корнем и коэффициентами порядка 1e-180/1e180.

Для исходного случая independent closed-form first crossing: 0.603748955145611 s. Runtime: 0.603745961857373 s (ошибка ≈3 microseconds при h=0.015 s). t≈0.6080218368 s — максимум, не момент первого отказа. Более узкий пик имеет большую измеренную timing sensitivity; тест явно допускает 60 microseconds, не переносит tolerance на прочность.

Сохранены original R3 187/0, observer PASS, отдельные writer/reader processes PASS, pending/committed replay PASS, R2 analytical/contract/metamorphic PASS, R1 integrity 42/0. Это локальные implementer checks; exact remote CI нового HEAD и независимые verdict проверяются отдельно.

Local pre-fix log SHA256: 5e4c7e7e7d84c4a92c9582579ff1fb5a9fb886226cb72cbf11b3052ac3293a80.
Local expanded regression log SHA256: a23875844366378566d427d6e12fc144d83e66552de4ca226ea7de87e7f9c831.
Engine: 4.7.1.stable.double.custom_build.a13da4feb; SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.

## Bounded post-build critique

NO_MATERIAL_REFACTOR_REQUIRED в текущем repair scope. Generic integrator не скопирован: новый код только ограничивает event brackets, локализует их пробами и вызывает прежний transition engine. R3-specific affine assumption явно отделена от более широкого FABRIC0. Оба runtime callers заменены, old acceptance не переписан. Stateless polynomial work bounded (degree ≤3 derivative isolation, ≤32 supports, bounded event iterations). Remaining integration risk: использование внутренних API прежнего DAE; при его будущем изменении потребуется revalidation adapter.

## Следующий gate

Заморозить Git HEAD/TREE этого runtime, проверить новый exact CI и manifest, получить fresh independent Reviewer PASS и Verifier VERIFIED на нём. Старый review не переносится. Итоговые verdict должны храниться отдельно от frozen runtime. Main/production acceptance не заявляются; PR #581 не merge-ить в frozen R2 или main; HOLDOUT-R4 до независимого решения не активировать.
