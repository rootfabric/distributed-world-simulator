# T1A.5 FIX1 — Transactional Runtime Effects

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a6-runtime-presentation-multiplayer-binding`  
**Control plane:** `PC0-2026-08-10-R1`  
**Причина:** blocker `T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_FIX1_REQUIRED_BEFORE_T1A6_ACCEPTANCE`  
**Статус:** `IMPLEMENTED CANDIDATE / WINDOWS VALIDATION REQUIRED`

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

То есть utility side effect мог произойти раньше canonical runtime commit. При последующем отказе runtime update это оставляло риск partial state.

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

## Новый regression

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

Focused runner:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_TESTS.ps1 -GodotPath $Godot
```

Он выполняет editor import, C5B contracts, прежний T1A.5 acceptance и новый transactional regression.

После его PASS требуется повторный T1A.6 focused multiplayer gate и полный world regression, потому что runtime code изменён после предыдущих acceptance evidence.

## PC0

До свежих PASS статус T1A.6 не считается ACCEPTED:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

Переход в `T1A.7 Runtime Recovery / Interest / Scale` остаётся заблокирован stop rule-ом PC0 до закрытия FIX1 и повторной acceptance T1A.6.
