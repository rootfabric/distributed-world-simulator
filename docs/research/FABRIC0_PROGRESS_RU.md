# FABRIC0 — журнал исследовательского прогресса

## FABRIC0.1 — Compositional scalar playground

**Durable branch:** `research/fabric0-compositional-world-fabric-r1`  
**Historical research head:** `2306ad446f7b6f0ee13b0986e38df3ee6d274dee`  
**PR:** `#317` (Draft)  
**Evidence:** `validation/fabric0-compositional-world-fabric-v1-validation.json`  
**Result:** `PASS_RESEARCH_ONLY`, 44 assertions.

Закрыто:

- typed domains;
- generic source/gain/transducer/threshold/gate/integrator/sink;
- switchable function;
- breakable topology;
- reusable feedback pattern;
- tank + heater;
- proximity door;
- deterministic replay.

## FABRIC0.2 — Inline switch + coupled rotational wall

**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`  
**Parent research head:** `2306ad446f7b6f0ee13b0986e38df3ee6d274dee`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v2-validation.json`.

Новый результат:

- `Switch` стал самостоятельным inline Element с state `closed`;
- `battery -> Switch -> lamp` реально включает и выключает lamp element;
- тот же Switch переиспользуется в `torque` domain;
- добавлены generic `rotational_inertia` и `viscous_load`;
- создан coupled cycle `speed -> load reaction torque -> inertia`;
- load reaction уменьшает net torque без device controller;
- после отключения motor source inertia сохраняет движение, load тормозит его;
- локальный discrete work/kinetic-energy identity проходит;
- rotational graph deterministic replay проходит;
- exact double-Godot acceptance: 70 assertions PASS.

Следующая исследовательская граница:

`FABRIC0.3 Two-source / Junction Wall` — вывести явные junction/conservation equations и проверить, можно ли перейти к acausal solving без разрушения модели `Port/Bond/State`.

Production promotion не заявляется. PR остаётся Draft.
