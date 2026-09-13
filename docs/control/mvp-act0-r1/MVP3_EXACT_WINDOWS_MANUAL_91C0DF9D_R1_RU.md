# MVP3 — EXACT WINDOWS MANUAL GRAPHICAL GATE R1

## Назначение

Это manual-evidence carrier. Он не меняет product runtime и не является acceptance/verification веткой.

Проверяемый immutable subject:

```text
HEAD = 91c0df9d9e9c36f3519110aea85b5884214b9278
TREE = 1a77202306e5a7f943b24e47d5c84f666b0a2cdc
REF  = freeze/v0-mvp3-r12-91c0df9d-r1
```

Parent `V0-MVP-R1-WO-001` остаётся `IN_PROGRESS`.

## Исполнитель

Роль: `FRESH_WINDOWS_MANUAL_EXECUTOR`, не Implementer, Reviewer и не Independent Verifier. Результат исполнителя — только raw manual evidence.

Использовать Windows double Godot:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
4.7.1.stable.double.custom_build.a13da4feb
SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Перед запуском live-проверить SHA-256, `git rev-parse HEAD`, `HEAD^{tree}`, freeze ref и чистый tracked worktree. Не использовать более новый product HEAD даже если ветка сдвинулась.

## Запуск

На чистом checkout exact subject:

```powershell
$env:PYTHONUTF8 = '1'
$env:GODOT_BIN = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
& $env:GODOT_BIN --headless --editor --path . --import --quit
if ($LASTEXITCODE -ne 0) { throw 'IMPORT_FAILED' }

$Out = "artifacts\mvp3-manual-91c0df9d-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
.\RUN_V0_MVP3_GRAPHICAL_ROUNDTRIP.ps1 -GodotBin $env:GODOT_BIN -Python python -OutputPath $Out -Manual
```

Обязателен именно `-Manual`. Запуск без него — automatic regression и manual PASS не создаёт.

## Реальный пользовательский сценарий

Должны одновременно существовать gateway + authority/a + authority/b + client/a + client/b. В обоих графических окнах ввод выполняется физической клавиатурой человеком ИЛИ разрешённым repository Breakpoint MCP `runtime_inject_input` согласно `docs/MCP_GODOT.md`. Запрещены `SendKeys`, `PostMessage`, PowerShell UI Automation, OS cursor automation, desktop screenshots и изменение runtime/test code ради evidence.

1. В окне A удерживать `D`/Right до реального A→B. После перехода продолжить движение на B и визуально подтвердить, что тот же body остаётся под управлением.
2. В окне A удерживать `A`/Left до B→A. После возврата выполнить дополнительное ненулевое движение на A.
3. В окне B выполнить минимум два собственных изменения направления/движения; B не должен быть только наблюдателем.
4. Оба окна должны всё время видеть обоих игроков. Не закрывать клиент во время handoff.
5. После доказанного A→B→A отпустить все удерживаемые клавиши. В обоих окнах нажать `Esc` для штатного FINISH.

Если используется MCP, каждый `injected:true` подтверждает только доставку input event; после него обязательно проверить фактическое изменение canonical snapshot/viewport. Всегда отпустить held keys/actions при ошибке.

## Fail-closed критерии

Manual PASS возможен только если launcher exit=0 И одновременно:

- manifest `manual_input_mode=true` и `manual_input_executed=true`;
- `manual_input_events >= 2` у A и B;
- пять distinct process IDs;
- A transfer rows строго `authority/a -> authority/b -> authority/a`;
- каждый transfer имеет `post_activation_movement_proven=true`, ненулевое `before.position.x != after.position.x`, растущие `last_input_sequence/state_revision`, fixed tick receipt `delta_seconds=1/60`;
- B имеет собственные ненулевые fixed-tick input observations;
- client A/B: `connects=1`, `disconnects=0`, `reconnects=0`, `respawns=0`, `identity_changes=0`;
- gateway/backend links: reconnect/disconnect/failure_code отсутствуют;
- body/camera/surface instance IDs сохраняются;
- P7 projection contract остаётся `IMMUTABLE_P7_BOOTSTRAP_PROJECTION`, `canonical_state_owned=false`;
- реальные `client-a.png` и `client-b.png` присутствуют и соответствуют завершённому запуску;
- logs не содержат `SCRIPT ERROR`, `Parse Error`, `Compile Error`;
- tracked worktree после запуска чистый.

Любое несоответствие = FAIL/INSUFFICIENT_EVIDENCE, не «почти PASS».

## Evidence manifest

После запуска НЕ редактировать raw output. Отдельно записать:

- executor/machine OS;
- exact HEAD/TREE/freeze ref;
- Godot version + SHA-256;
- UTC start/end;
- фактическую команду;
- launcher exit code;
- SHA-256 каждого raw log/JSON/PNG и общего списка;
- `git status --porcelain --untracked-files=no` до/после;
- метод ввода: `HUMAN_PHYSICAL_KEYBOARD` или `BREAKPOINT_MCP_RUNTIME_INJECT_INPUT`;
- при MCP — названия runtime tools и подтверждения фактических world-state изменений, без чтения/публикации MCP secret.

Результат этой задачи не создаёт `PREDICATE_VERIFIED`. После manual PASS его bytes должен независимо проверить Fresh Independent Verifier/Coordinator прежде, чем leaf может быть закрыт.

На момент создания инструкции manual run в текущей ChatGPT tool-среде НЕ выполнялся: здесь отсутствует подключённый Windows Godot/Breakpoint MCP или другой разрешённый live-input канал. Это поле нельзя менять на PASS по automatic CI evidence.
