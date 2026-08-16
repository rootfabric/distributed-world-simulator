# V0-P3 — ручной визуальный gate V-P3.1

## Назначение

Этот gate закрывает обязательную ручную проверку первого resource/mining runtime slice перед переходом к следующей продуктовой интеграции `resource -> inventory/container -> Construction`.

Он **не меняет production runtime** и запускается поверх зафиксированного Windows-GREEN P3 R13:

```text
f27a60279c8ad61d47ebe3fad81b6898679c660f
```

Validation tooling находится в отдельной ветке и при запуске fail-closed проверяет, что:

- текущий HEAD является потомком exact R13 выше;
- `config/resources/v0_resource_nodes.json`, `scripts/app/earth_p3_resource_mining_app.gd` и весь `scripts/runtime/networked_gameplay/p3` не отличаются от R13;
- checkout чистый;
- используются обычный V0 Earth MVP launcher, dedicated server и ровно два графических клиента `a` / `b`;
- managed session действительно запущена для `world=earth`.

## Запуск на Windows

Из корня exact validation checkout/worktree:

```powershell
.\RUN_V0_P3_VISUAL_GATE.ps1 -Restart
```

Канонический Godot по умолчанию:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Если нужно явно указать GUI executable:

```powershell
.\RUN_V0_P3_VISUAL_GATE.ps1 `
    -GodotExe "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
    -GodotGuiExe "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe" `
    -Restart
```

Gate переиспользует `RUN_V0_MVP_AUTO.ps1`: preflight/import/UID checks, автоматический поиск свободного UDP-порта, обычный `--network-mvp --world=earth`, dedicated server, два GUI-клиента и существующую изоляцию Breakpoint runtime bridge.

## V-P3.1 — обязательная ручная последовательность

### 1. Оба клиента в одной Earth session

Убедиться, что открыты два графических клиента и оба находятся в одном Earth runtime.

Ожидаемые logical identities:

```text
client A = a
client B = b
```

### 2. Видимый resource node

На клиенте A найти видимый узел руды в игровой зоне.

Канонический первый узел:

```text
resource_node_id = resource/earth/ore-demo/1
initial_units    = 8
output           = item/ore
```

### 3. Interaction focus

Подойти к руде и навести камеру на узел.

Ожидаемый prompt:

```text
E — Добыть руду · Руда ×8
```

Prompt является presentation-слоем. Каноническая identity ресурса и решение о допустимости mining остаются server-authoritative.

### 4. Одна добыча

Нажать `E` ровно один раз.

Ожидаемый authoritative переход:

```text
remaining_units: 8 -> 7
resource generation: +1
canonical output: exactly one item/ore
```

Визуально ore node должен уменьшиться. Полное истощение должно скрывать/отключать resource target, но в V-P3.1 достаточно подтвердить первый переход `8 -> 7`.

### 5. Canonical inventory output

Открыть существующий modern network inventory клиента A и убедиться, что после mining появился один новый канонический `item/ore`.

Нельзя считать PASS, если руда появилась только как локальная UI-проекция без соответствующего authoritative изменения. Уже существующий automated R13 real-UDP gate отдельно доказывает canonical Item Graph output; эта ручная проверка подтверждает product presentation на той же архитектуре.

### 6. Второй клиент

На клиенте B убедиться, что тот же resource node уже находится в состоянии `7`, а не `8`.

Это визуальная проверка общей authoritative resource state, а не двух независимых локальных копий.

### 7. Ошибки runtime

Проверить отсутствие устойчивой parser/runtime/network ошибки после mining.

Launcher печатает точный каталог логов. Он находится под:

```text
%LOCALAPPDATA%\DistributedWorldSimulator\V0MvpLauncher\logs\<session-id>\
```

Историческое transient-сообщение `COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH`, наблюдавшееся в автоматическом R13 run и затем само восстановившееся, не скрывать: если оно возникает, записать момент и проверить, остаётся ли ошибка persistent и влияет ли она на mining/convergence.

## Остановка

```powershell
.\RUN_V0_P3_VISUAL_GATE.ps1 -Stop
```

## PASS

Ручной `V-P3.1 PASS` допустим только если одновременно подтверждены:

1. A и B работают в одной Earth session;
2. A видит canonical ore target;
3. interaction prompt появляется;
4. одно `E` даёт видимое `8 -> 7`;
5. один `item/ore` появляется через существующий inventory UI;
6. B видит тот же depleted state;
7. нет persistent runtime failure, ломающего сценарий.

Зафиксировать вместе с PASS:

- exact validation HEAD;
- exact R13 ancestor;
- Godot version;
- каталог session logs;
- краткий результат каждого из 7 пунктов;
- любые transient warnings.

## Non-claims

`V-P3.1 PASS`:

- не является independent Reviewer / Verifier / Director verdict для PR #113;
- не разрешает merge PR #113 или PR #109;
- не объявляет P3 или V0 globally accepted;
- только закрывает предусмотренный manual product-presentation gate перед следующим bounded V0 slice.
