# M7: раздельный диагностический запуск сети

Этот режим запускает dedicated server и каждого графического клиента в отдельной консоли. У всех процессов отдельные пользовательские каталоги и отдельные постоянные логи.

## Терминал 1 — сервер

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\START_M7_NETWORK_SERVER.ps1 -GodotPath $Godot -SessionId manual -ResetPersistence
```

Сервер остаётся в этой консоли. Главный лог:

```text
artifacts/runtime/m7-network-debug/manual/server/godot.log
```

## Терминал 2 — клиент A

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\START_M7_NETWORK_CLIENT.ps1 -GodotPath $Godot -SessionId manual -PlayerId a
```

## Терминал 3 — клиент B

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\START_M7_NETWORK_CLIENT.ps1 -GodotPath $Godot -SessionId manual -PlayerId b
```

Клиент в debug-режиме не закрывает окно автоматически при disconnect или ошибке подключения. Ошибка остаётся на экране, в консоли и в `godot.log`.

## Отдельное наблюдение за логом

```powershell
.\WATCH_M7_NETWORK_LOG.ps1 -SessionId manual -Role server
.\WATCH_M7_NETWORK_LOG.ps1 -SessionId manual -Role client-a
.\WATCH_M7_NETWORK_LOG.ps1 -SessionId manual -Role client-b
```

Структурированные события имеют префиксы:

```text
[m7_server]
[m7_client]
[m7_item_rejected]
[m7_network_error]
```

## Остановка

```powershell
.\STOP_M7_NETWORK_DEBUG.ps1 -SessionId manual
```

## Повторная проверка recovery

Остановите сервер, не удаляя persistence, и снова запустите ту же команду без `-ResetPersistence`. Для чистого мира используйте `-ResetPersistence`.

## Как читать сбой

Если игрок двигается вперёд и затем возвращается назад, проверьте клиентский лог на
`m7_hard_snap`, `m7_network_error` и рост очередей команд. В исправленной версии
клиент не запускает собственную физику одновременно с сервером: он передаёт только
`MOVEMENT_INTENT`, а отображение плавно следует authoritative snapshot.

Если `E` не подбирает предмет, найдите последнюю строку `[m7_item_rejected]` в логе
клиента. В ней присутствуют `error_code`, понятное сообщение и target operation ID.
Типовые причины: предмет дальше пяти метров, закрыт препятствием или уже подобран
другим клиентом.

Если сервер завершился, сначала смотрите последнюю строку `[m7_server]`, затем
`server/server-state.json`. Клиентская команда запуска проверяет не только состояние
`READY`, но и живой PID из `server/process.json`, поэтому устаревший файл от прошлого
запуска больше не считается работающим сервером.
