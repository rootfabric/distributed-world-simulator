# T1A.5 FIX1 — Transactional Runtime Effects

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a6-runtime-presentation-multiplayer-binding`  
**Control plane:** `PC0-2026-08-10-R1`  
**Причина:** blocker `T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_FIX1_REQUIRED_BEFORE_T1A6_ACCEPTANCE`  
**Статус:** `ACCEPTED / T1A6 REVALIDATION PENDING`

## Почему потребовался FIX1

T1A.5 functional acceptance доказал работу двери, генератора, лампы и консоли, но architecture audit обнаружил нарушение transactional ordering.

До FIX1 путь для utility-changing команды был фактически таким:

```text
runtime command
  -> handler
  -> _recompute_power()
       mutates power_tick
       mutates power_storage
       mutates power_execution_profile
  -> runtime subject update
  -> operation terminal record
```

Utility side effect мог произойти раньше canonical runtime commit. При последующем отказе runtime update это оставляло риск partial state.

## Исправленная граница

Теперь порядок:

```text
runtime command
  -> pure handler
  -> pure utility projection
  -> runtime subject commit
  -> validated utility effect commit
  -> terminal SUCCEEDED record
```

Если effect committer возвращает ошибку после runtime subject update, generic executor восстанавливает предыдущее состояние `ConstructionRuntimeStateStore` через существующие `to_dict()/load_dict()` и записывает terminal rejection.

Exact replay разрешается operation ledger до handler-а, поэтому committed effect не выполняется второй раз.

## Изменения

### Generic C5B executor

`ConstructionAffordanceRuntimeExecutor.setup()` получил необязательный `effect_committer`.

Handler может вернуть:

```text
effect: Dictionary
```

Только mutating command может иметь effect. Для transactional effect store обязан поддерживать snapshot/restore через существующие `to_dict/load_dict`.

Нового transaction coordinator, registry или persistence foundation не добавлено.

### D0 T1A.5 runtime

Старый mutating `_recompute_power()` заменён на:

```text
_project_power()      # pure projection
_apply_power_effect() # validate first, mutate only after validation
```

`GENERATOR`, `LAMP`, `CONSOLE` строят effect projection в handler-е. `DOOR` не создаёт utility effect.

## Regression

Добавлен:

```text
tests/construction/t1a5_transactional_runtime_effects_acceptance.gd
```

Он проверяет:

```text
successful effect commits exactly once
exact replay does not recommit effect
failed effect commit rolls runtime store back byte-equivalently
failed transaction is terminal REJECTED
failed replay is stable and does not rerun effect
D0 generator utility tick advances once
D0 generator replay does not advance tick/battery/revision
stale D0 command changes neither runtime nor utility state
```

Первый Windows probe обнаружил только parse-проблему самого нового regression-теста: GDScript не смог вывести тип динамического `success_generation`. Production runtime до этого прошёл C5B и исходный T1A.5 acceptance. Parse fix сделал динамические значения теста явными `int/String/Dictionary`; runtime semantics не менялись.

## Windows acceptance

На head `a5e2795698a469a7f160214b3e4880014f6759a2` focused runner прошёл полностью:

```text
C5B affordance runtime contracts: PASS (32 assertions)
T1A.5 interactive runtime execution: PASS (67 assertions)
T1A.5 transactional runtime effects: PASS (36 assertions)
T1A.5 transactional runtime effects focused gate passed.
```

Это закрывает локальное доказательство blocker-а `T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_FIX1_REQUIRED_BEFORE_T1A6_ACCEPTANCE`.

## Что остаётся для T1A.6

Предыдущий T1A.6 multiplayer PASS и world regression PASS были получены до runtime semantic change, поэтому они остаются исторически корректными, но stale для formal acceptance.

Нужно повторить:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_T1A6_RUNTIME_PRESENTATION_MULTIPLAYER_TESTS.ps1 -GodotPath $Godot

$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

До этих двух свежих PASS статус T1A.6:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

Переход в `T1A.7 Runtime Recovery / Interest / Scale` остаётся заблокирован stop rule-ом PC0 до повторной acceptance T1A.6.
