# FABRIC HOLDOUT-R4 G2 — Repair R2 после fresh review

Статус: **AUTHORIZED / IN_PROGRESS**.  
Risk: **HIGH** (исправляется публично наблюдаемая physical sign semantics; architecture ownership не меняется).  
Parent subject: `989ed83c10d861f151423b4e7dae6952c7177b68` / tree `aefd109b76a5ebc5ee98f35e730bb07a895f59fe`.  
Fresh review: completed 2026-09-12, два актуальных P2.

## Finding R2-A — signed axial effort

Affected module:
`scripts/research/fabric_bake0/fabric_composition_r3_general_system_v1.gd`.

Canonical research contract в `FABRIC_HOLDOUT_R4_G2_WORK_ORDER_RU.md`:

```text
per-element effort = k*(q_a-q_b) + c*(v_a-v_b)
```

Текущий implementation вычисляет противоположный знак:

```text
k*(q_b-q_a) + c*(v_b-v_a)
```

и использует это же значение для generalized guard/failure expressions и readback. Проверка обоих знаков скрывает проблему для порога разрушения, но `mechanical_observables.efforts_n` систематически меняет semantic sign. Простое инвертирование readback было бы symptom patch: internal force assembly и event effort должны использовать один и тот же объявленный signed effort.

Canonical fix location: `fabric_composition_r3_general_system_v1.gd`.

Fix:
- определить `dq=q_a-q_b`, `dv=v_a-v_b`;
- `effort=k*dq+c*dv`;
- сохранить прежнюю физическую внутреннюю силу через `force_a -= effort`, `force_b += effort`;
- damper heat оставить `c*dv^2` (знак не влияет);
- observe/readback вычислять тем же `q_a-q_b`, `v_a-v_b`;
- guard/failure продолжает использовать signed effort и проверяет оба направления.

Так физическая траектория остаётся эквивалентной до численной точности, а знак observables соответствует Work Order.

Regression coverage:
- G2 open-regression runtime должен для каждого active generalized element проверять `efforts_n == k*(q_a-q_b)+c*(v_a-v_b)`;
- существующие R3/G2 lifecycle/event tests подтверждают отсутствие изменения failure semantics и динамики.

## Finding R2-B — exact-head workflow freshness

Affected module:
`.github/workflows/fabric-holdout-r4-g2-linux-double.yml`.

Новый `lossless_replay_bridge_v1.gd` наследует
`scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd`, но G2 workflow `paths` не включает canonical bridge. Bridge-only push может изменить replay semantics без нового exact G2 run.

Canonical fix: добавить точный path canonical bridge в trigger. Не расширять workflow на нерелевантные ветки и не менять команды/runner/binary.

Regression/static control: final workflow content обязан содержать canonical bridge path рядом с compiler/runtime/general surfaces.

## Разрешённый R2 scope

```text
scripts/research/fabric_bake0/fabric_composition_r3_general_system_v1.gd
tests/research/fabric1/fabric_holdout_r4_g2_acceptance.gd
.github/workflows/fabric-holdout-r4-g2-linux-double.yml
docs/research/FABRIC_HOLDOUT_R4_G2_REPAIR_R2_RU.md
```

Никаких изменений `NetworkUtils`, lossless transport codec, graph/mechanics compiler, thresholds/golden, G1 frozen bytes, Construction/Matter ownership или B0.6 PERF budget.

## Validation

После patch старое evidence на `989ed83c` становится historical. Требуется новый immutable HEAD/TREE и:

1. focused G2 acceptance — включая новый signed-effort assertion;
2. exact self-hosted G2/R3/R2/R1 workflow на новом HEAD;
3. повторная шестигейтовая qualification: G2, B0.4-D Linux, Complex Labs, CX-VIS0, B0.6-CLOSE, B0.4-D Portable;
4. fresh independent re-review нового exact HEAD/TREE;
5. только после PASS — Director pre-freeze decision.

Production freeze / unseen holdout / R4 acceptance этим Repair R2 не разрешаются.
