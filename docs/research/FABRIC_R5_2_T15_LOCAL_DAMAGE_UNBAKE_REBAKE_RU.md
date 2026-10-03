# FABRIC R5.2 / T15 — Local Damage → Selective UNBAKE → ReBAKE

Статус: **IMPLEMENTED / IMPLEMENTER LOCAL EXACT PASS / FRESH REVIEW+VERIFIER PENDING**.

База: frozen T14 runtime `5a65e6d245fda85de50d1cf6c4a551c6240677be`, tree `291048dae0044b28b013be045a05270a9b3e5220`.
T14 остаётся отдельным human merge gate; T15 — stacked research candidate поверх точного frozen runtime, не объявляет T14 автоматически merged/closed.

## Цель

T14 доказал, что один instance может получить detailed compiled view без влияния на physical execution. T15 делает следующий шаг: **один конкретный instance реально меняет свою canonical/source-side внутреннюю структуру**, только затронутая detailed leaf-сборка и её dependent ancestors перекомпилируются, caller-owned physical state переносится в новый compiled family, а старый binding немедленно становится неисполняемым.

Сценарий:

```text
100 instances / 4 shared families
             ↓
family-b / t15-instance-058
root/bank/unit03/cannon/emitter
             ↓ local source materialization
128 GAAS gain cells
             ↓ disable cell #009
recompile exactly:
  emitter
  cannon
  unit03 turret
  bank
  ship
             ↓
5 changed compiled paths
25 unchanged compiled subtrees reused byte-for-byte
             ↓
instance-058 fork → damaged family
other 99 instances stay on original shared families
             ↓ repair same source cell
same bounded 5-path rebuild
             ↓
instance-058 fork → repaired family
```

## Что здесь считается UNBAKE

T15 не пытается восстановить canonical leaves из байтов bake artifact. Источник истины остаётся canonical/source owner. Fixture materializes detailed T9 source graph и перед мутацией проверяет, что его `graph_hash` совпадает с `source_graph_hash` текущего compiled emitter. Если anchor не совпадает — `T15_SOURCE_UNBAKE_ANCHOR_MISMATCH`.

После этого изменяется один source component (`enabled=false` у gain-cell #009) и выполняется существующий T9 compiler. Это bounded source-side UNBAKE/rebuild, а не ручная правка descriptor/capsule.

Одна materialization/rebuild проходит 128 T9 source cells, а не все 4275 source components Ship Matryoshka.

## Selective rebuild

Damage и repair каждый выполняют ровно 5 compiler/compose invocations:

```text
1 emitter leaf
1 cannon
1 turret
1 bank
1 ship
= 5 compile events
```

T15 runtime вычисляет exact binary hash manifest всей old/new hierarchy и требует, чтобы changed paths были **точно**:

```text
root
root/bank
root/bank/unit03
root/bank/unit03/cannon
root/bank/unit03/cannon/emitter
```

Любое дополнительное изменение sibling subtree или topology shape fail-closed. Для 30-node T12 hierarchy это означает 25 unchanged subtree identities на каждую mutation.

## Per-instance fork

Shared family не мутируется. Для affected instance регистрируется новый immutable prepared family model. Семантические:

- `instance_id`;
- `world_slot`;
- caller-owned physical state

сохраняются. Меняются compiled model/binding identities, а `state_revision` и `damage_revision` возрастают.

Старый binding после commit возвращает `T15_INSTANCE_SUPERSEDED`. Это derived execution fence, а не новый canonical revision owner.

T15 не утверждает pointer-shared child execution между old/new full-family models; recursive shared execution остаётся R5.3.

## State projection

Текущий damage fixture меняет emitter law, но не state schema T12. Поэтому T15 разрешает projection только если новый prepared model принимает прежний `physical` state byte-exact. Перед/после hashes обязаны совпасть.

Если новый model не принимает прежний state — `T15_STATE_PROJECTION_UNSAFE`; скрытое состояние не синтезируется.

Damage не сбрасывает:

- battery charge;
- battery/cooling temperatures;
- servo position/velocity;
- иной caller-owned T12 physical state.

Repair выполняется уже из evolved damaged state, а не из первоначального snapshot.

## T14 ↔ T15 ordering

Active T14 observation overlay на старом binding должен быть release'нут до structural fork:

```text
T15_ACTIVE_OBSERVATION_MUST_RELEASE
```

После fork старый observation snapshot/binding не может продолжать physical execution как актуальный instance.

## Physical consequence

Отключённая gain-cell остаётся физической частью emitter (масса не исчезает), но меняет active-cell envelope и laser boundary behavior. Acceptance требует:

```text
other 99 instances = exact-equivalent
selected damaged instance = physically diverges
steady compact leaf traversals = 0
```

После repair enabled emitter на новом canonical revision обязан восстановить healthy boundary physics для того же evolved physical state. Для этого используется независимый healthy family runtime как reference.

## Accounting ожидаемого candidate

```text
T13.5 baseline compile events            = 42
Damage local compile events              = 5
Repair local compile events              = 5
Damage+repair source leaf traversals      = 256 (2 × 128)
Source components per ship               = 4275
Changed paths per mutation               = 5
Unchanged subtrees per mutation           = 25
Original prepared family models          = 4
Final prepared successor models          = 6
Expected final unique subtree identities = 52
Expected final subtree occurrences       = 180
Expected final reuse hits                 = 128
```

Compile/build work и steady-state execution намеренно считаются отдельно. После fork/repair physical ticks снова идут по compact T13/T12 runtime без source-leaf traversal.

## Negative gates

- wrong selected path → `T15_DIVERGENCE_NOT_LOCAL_TO_SELECTED_CHAIN`;
- changed topology shape → `T15_TOPOLOGY_SHAPE_CHANGED`;
- source graph not matching current compiled leaf → `T15_SOURCE_UNBAKE_ANCHOR_MISMATCH`;
- active T14 observation → `T15_ACTIVE_OBSERVATION_MUST_RELEASE`;
- duplicate event → `T15_EVENT_ALREADY_APPLIED`;
- old binding after fork → `T15_INSTANCE_SUPERSEDED`;
- incompatible state projection → `T15_STATE_PROJECTION_UNSAFE`.

## Что T15 пока не заявляет

Этот checkpoint не является:

- корпусом или полётом корабля;
- impact/fracture damage T9 semiconductor от stress solve;
- общим arbitrary-topology source editor;
- persistent restart closure нового fork family;
- network authority handoff;
- child-runtime pointer sharing между successor families;
- универсальным auto-repair planner;
- production integration.

Damage trigger в fixture — controlled canonical/source mutation для falsification T15 fork/rebuild contract. Следующий SHIP-LAB-1 применит этот механизм к наблюдаемым mount/power/matter/frame failures; физическое разрушение от нагрузки/удара будет отдельным acceptance и не подменяется `enabled=false`.

## Roadmap

```text
T14 observation refinement
        ↓
T15 local source divergence / instance fork / selective rebuild  ← THIS
        ↓
T16 NO_SAFE_BAKE adversarial cases
        ↓
R5.3 recursive/shared hierarchical execution
        ↓
R5.4 mixed-complexity machine
        ↓
R5 CLOSE → R6 fresh current-main integration
        ↓
SHIP-LAB-1 powered platform / damage / repair
```


## Implementer exact evidence — 3 октября 2026

Runtime subject: `14a5ec14f6421157321e8d4aa0c3809b84e0df94`, tree `0d60544ff930a8d6483403f4e0d14c6447e58673`. Canonical Linux double Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Три отдельных T15 процесса: **491/491 PASS** каждый; raw logs byte-identical (`c295f4d68b4f95f05723d4a21112d00b7516defc7757270a1add55cff7d93654`), deterministic result hash `daf068dac4b7fd002ab78007db171e02881807b83e05009b5ecf04b756025e8f`. Fresh import fatal markers = 0.

Наблюдаемый результат exact subject:

```text
100 instances; target = t15-instance-058 / family-b
selected source path = root/bank/unit03/cannon/emitter
other 99 exact-equivalent after damage = 99
T13.5 baseline compile events = 42
damage selective compiles = 5
repair selective compiles = 5
source leaf traversals over damage+repair = 256 = 2 × 128
changed compiled paths per mutation = 5
unchanged compiled subtrees per mutation = 25
final prepared family models = 6
final unique subtree identities = 52
steady source leaf traversals after damage = 0
state preserved across damage projection = true
state preserved across repair projection = true
repair restores healthy boundary behavior = true
all model identities intact = true
```

Unchanged regressions on the same runtime subject: T14 `1208 PASS`, T13.5 `777 PASS`, T13 `1377 PASS`, T12 `8386 PASS`; Python evidence/source-contract tests `4/4 PASS`. Durable implementer record: `validation/fabric-r5-2-t15-local-damage-implementer-exact-evidence.v1.json`.

Это **не independent acceptance**: Fresh Reviewer/Verifier и T14 human closure/merge остаются отдельными gates.
