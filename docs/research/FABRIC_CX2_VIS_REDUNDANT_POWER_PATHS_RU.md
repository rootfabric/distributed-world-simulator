# FABRIC CX2-VIS — Redundant Power Paths

**Статус:** IMPLEMENTED / exact verification required  
**Ветка:** `feature/fabric-cx2-vis-redundant-power-r1`  
**Predecessor:** CX-VIS0 / CX-VIS1 powered observatory.

## Цель

Доказать визуально и executable, что функциональная сеть не содержит скрытого shortcut вида «сломался забор → лампа OFF».

Стенд использует два независимых пути:

```text
BATTERY
  ├─ wire/path-a ─┐
  └─ wire/path-b ─┴─ LAMP
```

Оба пути поддерживаются разными structural bond ID внутри того же 2000-part COMPLEX0 subject.

```text
break A only  -> lamp ON
break B only  -> lamp ON
break A + B   -> lamp OFF
```

Дополнительно проверяется:

- порядок A→B и B→A даёт одинаковый финальный physical state;
- unrelated structural break не влияет на оба power paths;
- duplicate event fail-closed;
- все состояния лампы берутся из `Fabric.solve()`, а не из номера visual-frame.

## Сцена

```text
res://scenes/labs/fabric/cx2_redundant_power_paths.tscn
```

Visual stages:

```text
BOTH_PATHS
BREAK_A
BREAK_B
BREAK_A_PLUS_B
```

## Exact model

```text
res://scripts/research/fabric_bake0/cx2_vis_redundant_power_observation_v1.gd
```

Он использует:

```text
CX-VIS0 exact 2000-part observation
        +
COMPLEX1A redundant_path()
        ↓
support/path-a -> exact COMPLEX0 weak bond
support/path-b -> second distinct structural bond
        ↓
FABRIC solve
```

## Acceptance

```text
res://tests/research/fabric_bake0/fabric_bake_cx2_vis_redundant_power_acceptance.gd
```

Runner:

```bash
bash ./RUN_FABRIC_CX2_VIS_TESTS.sh
```

Этот стенд является functional falsifier и не заявляет, что второй break уже прошёл полный structural guard/unbake/rebake lifecycle. Полный cross-representation E2E переносится в следующий этап — `COMPLEX1B visual mixed-representation E2E`.
