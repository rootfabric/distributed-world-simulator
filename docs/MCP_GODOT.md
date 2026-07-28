# Godot MCP: руководство для автономного агента

Этот документ описывает рабочий контракт, по которому агент может сам запустить
проект, дождаться готовности мира, наблюдать его состояние, управлять персонажем
и интерфейсом, делать снимки игрового viewport, читать логи и корректно завершать
свой процесс.

В проект встроен `Breakpoint MCP` 1.7.0 с локальными исправлениями ввода. Он
использует только loopback:

- `127.0.0.1:9080` — bridge открытого редактора;
- `127.0.0.1:9081` — bridge запущенной игры;
- `127.0.0.1:6005` — встроенный GDScript LSP Godot;
- `127.0.0.1:6006` — встроенный Godot DAP.

Официальное описание MCP host и его актуальный каталог инструментов:

- <https://github.com/jlivingston-Cipher/godot-breakpoint-mcp>
- <https://github.com/jlivingston-Cipher/godot-breakpoint-mcp/blob/main/docs/TOOL_CATALOG.md>

## Главный контракт агента

При работе внутри запущенного мира агент обязан:

1. Запускать Godot через MCP как управляемый процесс, если доступен
   `godot_run_managed`.
2. Использовать только double-precision сборку из `C:\Godot\godot\bin\`.
3. Посылать игровой ввод только через `runtime_inject_input`.
4. Наблюдать игру через `runtime_screenshot`, `runtime_get_tree`,
   `runtime_get_property`, `runtime_assert_*` и `runtime_get_log`.
5. Не использовать `SendKeys`, `PostMessage`, PowerShell UI Automation,
   эмуляцию Windows-клавиатуры, перемещение системного курсора и снимки рабочего
   стола.
6. Подтверждать результат действия состоянием мира. Ответ `injected: true`
   означает только, что событие передано в `Input.parse_input_event` или
   `Input.action_press`; он не доказывает результат игрового действия.
7. Всегда отпускать удерживаемые actions и клавиши, даже если сценарий завершился
   ошибкой.
8. Хранить временные PNG и логи только в `artifacts/`. Каталог уже исключён из
   Git.
9. Не читать, не печатать и не передавать содержимое
   `.godot/breakpoint_mcp.secret`. Аутентификацию выполняет MCP host.
10. Не запускать второй экземпляр runtime на порту `9081`, пока не остановлен
    первый.

Имена ниже — логические имена MCP tools. Клиент может показывать их с префиксом
сервера, например `godot.runtime_get_tree`, `godot_runtime_get_tree` или
`mcp__godot__runtime_get_tree`.

## Архитектура управления

```text
агент
  │ MCP over stdio
  ▼
breakpoint-mcp host
  ├── запускает double Godot и владеет managed process
  ├── 9080 ── редактор: сцены, узлы, ресурсы, undo/redo
  ├── 9081 ── игра: SceneTree, свойства, ввод, кадр, runtime-логи
  ├── 6005 ── GDScript LSP
  └── 6006 ── Godot DAP
```

Редакторский screenshot и runtime screenshot — разные вещи:

- `screenshot_editor` снимает 2D/3D viewport редактора;
- `runtime_screenshot` снимает только viewport запущенной игры;
- для доказательства поведения игры нужен `runtime_screenshot`.

## Однократная настройка Codex

В `C:\Users\root\.codex\config.toml` должен быть зарегистрирован MCP server.
Для полноценного управления миром и захвата stdout/stderr используйте именно
double console executable:

```toml
[mcp_servers.godot]
command = "npx"
args = ["-y", "breakpoint-mcp"]
env = { GODOT_PROJECT = "C:\\Godot\\lunar-world-double-godot", GODOT_BIN = "C:\\Godot\\godot\\bin\\godot.windows.editor.double.x86_64.console.exe", BREAKPOINT_TOOLSETS = "cli,runtime,processes", BREAKPOINT_PRIVILEGED_GROUPS = "code-execution" }
```

Пояснения:

- `GODOT_BIN` намеренно указывает на `double.x86_64.console.exe`;
- `cli,runtime,processes` оставляет компактный набор инструментов для запуска и
  жизни в мире;
- `code-execution` нужен актуальному host для `godot_run_managed`,
  `runtime_call_method` и других явно привилегированных операций;
- `runtime_inject_input` всё равно может требовать подтверждение. Если клиент не
  поддерживает MCP elicitation, передавайте `"confirm": true`;
- для редактирования сцен, LSP и DAP уберите `BREAKPOINT_TOOLSETS` либо задайте
  требуемые группы дополнительно: `editor,lsp,dap`.

После изменения конфигурации полностью перезапустите MCP-клиент. Уже запущенная
сессия обычно не перечитывает список серверов и tools.

Проверить установку вне игрового сценария можно командой:

```powershell
npx -y breakpoint-mcp doctor --project "C:\Godot\lunar-world-double-godot" --require-live --json
```

Это только диагностическая проверка соединений. Она не должна использоваться для
ввода в игру. В runtime-only режиме недоступность `9080`, LSP и DAP допустима;
критичен ответ runtime bridge на `9081`.

Проверенная в репозитории версия addon указана в
`addons/breakpoint_mcp/plugin.cfg`. Не запускайте `breakpoint-mcp init --force`
в рамках обычной проверки: он может заменить addon и стереть локальное
исправление `physical_keycode`. Обновление addon и npm host делается отдельной
задачей с повторным end-to-end тестом управления человеком и агентом.

## Что уже подключено в проекте

`project.godot` содержит:

```ini
[autoload]
BreakpointRuntimeBridge="*res://addons/breakpoint_mcp/runtime_bridge.gd"

[editor_plugins]
enabled=PackedStringArray("res://addons/breakpoint_mcp/plugin.cfg")
```

Тестовая комната:

```text
res://scenes/testing/playground.tscn
```

Её корень — `PlaygroundRuntime`. При прямом запуске он сам создаёт InputMap для
`WASD`, прыжка и ускорения, маршрутизирует `Tab`, `E`, `F`, `G`, `1–0` и
поддерживает одновременно человеческий и MCP-ввод.

Batch-файлы `launch_mcp_game.bat` и `launch_playground.bat` оставлены для ручного
запуска человеком. Автономный агент должен предпочитать managed process через
MCP, потому что только тогда он получает идентификатор процесса, stdout/stderr и
может завершить именно свой экземпляр.

## Предстартовая проверка

Перед каждым сценарием агент выполняет следующие проверки.

### 1. Проверить бинарник

Вызвать:

```text
godot_version {}
```

Затем проверить свою MCP-конфигурацию: источником истины для precision является
путь `GODOT_BIN`, который должен заканчиваться на:

```text
godot.windows.editor.double.x86_64.console.exe
```

Не подменять его обычной `godot.exe`, single-precision или 32-битной сборкой.

### 2. Проверить отсутствие собственного старого процесса

Если в контексте текущей MCP-сессии сохранён `managed_id`, сначала запросить:

```text
godot_output {"id":"<managed_id>","since_seq":0,"stream":"both"}
```

Если процесс ещё работает, либо продолжить работу именно с ним, либо остановить:

```text
godot_stop {"id":"<managed_id>"}
```

Не завершать все процессы Godot по имени: пользователь может держать другой
редактор или другой проект.

### 3. Выбрать режим

- Для работы с тестовой комнатой запускать её напрямую.
- Для проверки полного приложения запускать main scene без параметра `scene`,
  затем переходить в `playground` штатной командой приложения.
- Не держать одновременно прямой playground и main scene на одном runtime-порту.

## Запуск тестовой комнаты через MCP

Предпочтительный вызов:

```text
godot_run_managed
{"scene":"res://scenes/testing/playground.tscn"}
```

Сохранить из результата:

- `id` как `managed_id`;
- `pid` только для отчёта;
- `running`;
- `scene`.

`managed_id`, а не PID, передаётся в `godot_output` и `godot_stop`.

Если `godot_run_managed` отсутствует в списке tools, проверить
`BREAKPOINT_TOOLSETS=cli,runtime,processes`,
`BREAKPOINT_PRIVILEGED_GROUPS=code-execution` и перезапустить MCP-клиент.
`godot_run_project` запускает detached process и поэтому хуже подходит
автономному агенту: host не даёт симметричный управляемый stop по его PID.

## Ожидание готовности

Нельзя отправлять `Tab`, `W` или screenshot немедленно после запуска. Сначала
runtime должен принять соединение и построить сцену.

Повторять с коротким интервалом:

```text
runtime_get_tree
{"max_depth":3}
```

Готовность тестовой комнаты подтверждается только когда в ответе есть:

```text
.
├── UniversalTestPlayer
├── ItemGameplayController
└── ItemWorldInteractor
```

Дополнительная машинная проверка:

```text
runtime_assert_scene_structure
{
  "expect":[
    {"path":".","type":"Node3D"},
    {"path":"UniversalTestPlayer"},
    {"path":"ItemGameplayController"},
    {"path":"ItemWorldInteractor"}
  ]
}
```

После готовности получить начальный кадр:

```text
runtime_screenshot {}
```

Если первый кадр чёрный, но SceneTree уже готов, запросить ещё один runtime
screenshot. Если чёрный и обязательных узлов нет, это не проблема рендера:
сначала читать stderr и искать ошибку загрузки/парсинга.

## Базовый цикл «жизни» агента в мире

Каждое осмысленное действие выполняется как замкнутый цикл:

```text
НАБЛЮДАТЬ
  runtime_get_tree / runtime_get_property / runtime_screenshot
      ↓
ВЫБРАТЬ ОДНО ДЕЙСТВИЕ
  runtime_inject_input
      ↓
ДАТЬ МИРУ ОБРАБОТАТЬ КАДР
  следующий runtime_screenshot или read-only runtime-вызов
      ↓
ПРОВЕРИТЬ ЭФФЕКТ
  runtime_assert_* / runtime_get_property / новый screenshot
      ↓
ПРОЧИТАТЬ ТОЛЬКО НОВЫЕ ЛОГИ
  runtime_get_log {since_seq:last_seq}
```

Правила цикла:

- Не посылать длинную слепую последовательность, если промежуточное состояние
  влияет на следующий шаг.
- После поворота проверить кадр или focus; после движения проверить позицию;
  после `E` проверить UI/состояние контейнера.
- Для непрерывного движения использовать короткие импульсы:
  `pressed:true` → один или несколько MCP-наблюдений → `pressed:false`.
- При ошибке сначала отпустить все actions, затем диагностировать.
- Для UI опираться на актуальный screenshot. Координаты мыши относятся к
  игровому viewport, а не к экрану Windows.

## Форматы `runtime_inject_input`

Вызовы ниже показывают payload конкретного tool. `"confirm":true` находится на
верхнем уровне вызова MCP host.

### InputMap action

Нажать и удерживать движение вперёд:

```json
{
  "event":{
    "kind":"action",
    "action":"move_forward",
    "strength":1.0,
    "pressed":true
  },
  "confirm":true
}
```

Обязательно отпустить:

```json
{
  "event":{
    "kind":"action",
    "action":"move_forward",
    "pressed":false
  },
  "confirm":true
}
```

В прямом `playground.tscn` доступны:

| Action | Результат |
|---|---|
| `move_forward` | вперёд |
| `move_back` | назад |
| `move_left` | влево |
| `move_right` | вправо |
| `jump` | прыжок |
| `boost` | ускорение |

Для движения предпочтительны actions, а не буквенные key events: это проверяет
тот же InputMap, которым пользуется игровой контроллер.

### Клавиша

Полный клик клавиши состоит из двух вызовов: down и up.

```json
{
  "event":{"kind":"key","keycode":4194306,"pressed":true},
  "confirm":true
}
```

```json
{
  "event":{"kind":"key","keycode":4194306,"pressed":false},
  "confirm":true
}
```

Коды, нужные в playground:

| Клавиша | `keycode` | Действие |
|---|---:|---|
| Escape | `4194305` | закрыть активное меню, если UI обрабатывает Escape |
| Tab | `4194306` | открыть/закрыть инвентарь |
| Space | `32` | прыжок; для движения лучше action `jump` |
| E | `69` | взаимодействие |
| F | `70` | фонарь |
| G | `71` | выбросить выбранный предмет |
| 1…9 | `49`…`57` | выбрать hotbar |
| 0 | `48` | выбрать десятый слот |

У Godot специальные клавиши включают бит `Key.SPECIAL`; поэтому Tab — не `9`, а
`4194306`. Старое значение `4194308` для Tab неверно.

Локальное исправление runtime bridge записывает один код одновременно в
`keycode` и `physical_keycode`. Благодаря этому один и тот же обработчик получает
ввод от MCP и от физической клавиатуры.

### Движение мыши

При захваченном курсоре камера использует `relative`:

```json
{
  "event":{
    "kind":"mouse_motion",
    "position":{"__type__":"Vector2","x":640,"y":360},
    "relative":{"__type__":"Vector2","x":40,"y":-10}
  },
  "confirm":true
}
```

- положительный `relative.x` обычно поворачивает взгляд вправо;
- знак вертикального поворота проверять небольшим движением и screenshot;
- использовать небольшие шаги и обратную связь, не один огромный рывок.

При открытом UI нужен абсолютный `position`. Пример наведения:

```json
{
  "event":{
    "kind":"mouse_motion",
    "position":{"__type__":"Vector2","x":273,"y":617},
    "relative":{"__type__":"Vector2","x":0,"y":0}
  },
  "confirm":true
}
```

Координата `(273, 617)` — только проверенная стартовая точка первого hotbar-слота
для viewport `1280×720`. При другом размере агент обязан заново определить
координату по runtime screenshot.

### Клик мыши

Клик — это down и up в одной viewport-координате:

```json
{
  "event":{
    "kind":"mouse_button",
    "button":1,
    "pressed":true,
    "position":{"__type__":"Vector2","x":273,"y":617}
  },
  "confirm":true
}
```

```json
{
  "event":{
    "kind":"mouse_button",
    "button":1,
    "pressed":false,
    "position":{"__type__":"Vector2","x":273,"y":617}
  },
  "confirm":true
}
```

Индексы: `1` — левая кнопка, `2` — правая.

## Состояние мира и Godot Variant

Пути runtime разрешаются относительно текущей запущенной сцены:

- `"."` — корень `PlaygroundRuntime`;
- `"UniversalTestPlayer"` — игрок;
- `"ItemGameplayController"` — предметная подсистема;
- `"ItemWorldInteractor"` — raycast-взаимодействие.

Абсолютный путь начинается с `/root/`, но относительный путь стабильнее при
проверке текущей сцены.

Прочитать свойство:

```text
runtime_get_property
{"path":"ItemGameplayController","property":"inventory_open"}
```

Прочитать цель взаимодействия:

```text
runtime_get_property
{"path":"ItemWorldInteractor","property":"current_snapshot"}
```

Сложные значения передаются tagged Variant:

```json
{"__type__":"Vector2","x":273.0,"y":617.0}
{"__type__":"Vector3","x":3.0,"y":1.2,"z":-0.5}
{"__type__":"Color","r":1.0,"g":0.5,"b":0.0,"a":1.0}
{"__type__":"NodePath","path":"UniversalTestPlayer"}
```

Для компактного снимка тестового мира можно вызвать:

```text
runtime_call_method
{
  "path":".",
  "method":"create_runtime_snapshot",
  "args":[],
  "confirm":true
}
```

Результат содержит `player_position`, controller snapshot и item gameplay
snapshot. `runtime_call_method` считается привилегированным, даже если конкретный
метод только читает состояние, поэтому лучше использовать обычные
`runtime_get_property` и assertions там, где их достаточно.

## Сценарий 1: открыть инвентарь и снять кадр

Это эталонная последовательность для любого агента.

1. Запустить `res://scenes/testing/playground.tscn` через
   `godot_run_managed`.
2. Дождаться готовности через `runtime_get_tree`.
3. Получить baseline логов:

   ```text
   runtime_get_log {"since_seq":0}
   ```

   Сохранить `latest_seq` как `last_runtime_seq`.

4. Проверить исходное состояние:

   ```text
   runtime_get_property
   {"path":"ItemGameplayController","property":"inventory_open"}
   ```

5. Послать Tab down и Tab up через `runtime_inject_input` с кодом `4194306`.
6. Проверить состояние:

   ```text
   runtime_assert_node_state
   {
     "path":"ItemGameplayController",
     "expect":{"inventory_open":true}
   }
   ```

7. Проверить видимый текст без OCR:

   ```text
   runtime_assert_screen_text
   {"text":"ИНВЕНТАРЬ","present":true}
   ```

8. Получить:

   ```text
   runtime_screenshot {}
   ```

9. На кадре проверить:

   - заголовок `ИНВЕНТАРЬ`;
   - `Рюкзак игрока`;
   - hotbar `1–0`;
   - инспектор предмета справа, если он включён;
   - отсутствие чёрного кадра или editor chrome.

10. Навести мышь на первый слот по координате, найденной на этом кадре.
11. Получить ещё один `runtime_screenshot` и проверить tooltip/hover.
12. Закрыть инвентарь вторым Tab down/up.
13. Проверить:

   ```text
   runtime_assert_node_state
   {
     "path":"ItemGameplayController",
     "expect":{"inventory_open":false}
   }
   ```

14. Прочитать только новые ошибки:

   ```text
   runtime_get_log
   {
     "since_seq":"<last_runtime_seq>",
     "levels":["warning","error"]
   }
   ```

## Сценарий 2: подойти к контейнеру и открыть его через `E`

Этот сценарий должен проверять реальный controller/input path. Не заменяйте его
прямым вызовом `open_container`, если задача состоит в проверке управления.

В стартовом demo crate имеет definition `portable_crate`, название
`Универсальный ящик` и обычно находится около `(3, 0.8, -2)`. Персистентное
состояние может изменить фактическую позицию, поэтому источником истины остаются
runtime snapshot, кадр и focus interactor.

1. Убедиться, что инвентарь закрыт:

   ```text
   runtime_assert_node_state
   {
     "path":"ItemGameplayController",
     "expect":{"inventory_open":false}
   }
   ```

2. Получить начальную позицию через `create_runtime_snapshot` или свойство
   `UniversalTestPlayer.global_position`.
3. Давать короткие импульсы `move_right` и `move_forward`. После каждого импульса:

   - вызвать `runtime_screenshot` как границу нескольких отрисованных кадров;
   - отпустить action;
   - снова прочитать позицию.

4. Не ориентироваться только на расстояние. Прочитать:

   ```text
   runtime_get_property
   {"path":"ItemWorldInteractor","property":"current_snapshot"}
   ```

5. Если snapshot пуст, небольшими `mouse_motion.relative` повернуть или наклонить
   камеру и после каждого шага снова читать `current_snapshot`.
6. Продолжать только когда snapshot показывает ожидаемый объект и prompt
   взаимодействия. Для demo crate ожидается заголовок `Универсальный ящик`.
7. Послать `E` down/up (`keycode:69`).
8. Проверить одновременно:

   ```text
   runtime_assert_node_state
   {
     "path":"ItemGameplayController",
     "expect":{"inventory_open":true}
   }
   ```

   ```text
   runtime_assert_screen_text
   {"text":"Универсальный ящик","present":true}
   ```

9. Получить `runtime_screenshot`.
10. Прочитать новые warning/error логи.

Если требуется проверить только отрисовку внешнего контейнера и уже известно,
что ввод работает, допустим white-box smoke test:

```text
runtime_call_method
{
  "path":"ItemGameplayController",
  "method":"open_container",
  "args":["demo_crate_contents"],
  "confirm":true
}
```

Этот вызов доказывает работу предметной подсистемы и UI, но не доказывает работу
движения, raycast focus или клавиши `E`. В отчёте обязательно назвать проверку
white-box, если использовался такой путь.

## Снимки экрана и артефакты

Правильный снимок создаётся так:

```text
runtime_screenshot {}
```

MCP tool возвращает PNG как image content и метаданные `width`/`height`. Это
изображение игрового viewport без рабочего стола, заголовка окна Godot и других
окон Windows.

Если клиент показывает image content напрямую, агент может анализировать его без
промежуточного файла. Если результат предоставлен как `base64`, разрешено только
декодировать уже созданный MCP PNG в:

```text
artifacts/mcp/<сценарий>.png
```

Декодирование payload не является повторным снимком. Запрещено заменять его
desktop capture. В отчёте указать:

- что использован `runtime_screenshot`;
- размер viewport;
- путь артефакта, если клиент сохранил файл;
- состояние мира непосредственно перед кадром.

Для визуальной регрессии можно хранить эталон внутри проекта и вызывать
`runtime_screenshot_diff`, но сравнение чувствительно к разрешению, динамическому
тексту, случайным данным и времени кадра. Для функционального UI-теста сначала
использовать `runtime_assert_screen_text` и node state, затем screenshot как
визуальное доказательство.

## Логи

Есть два независимых источника.

### Runtime ring buffer

```text
runtime_get_log
{"since_seq":0,"levels":["info","warning","error"]}
```

Ответ возвращает `latest_seq`. Сохраняйте его и дальше запрашивайте только новые
записи:

```text
runtime_get_log
{"since_seq":123,"levels":["warning","error"]}
```

Поле `capture` сообщает, установлен ли перехват стандартных Godot сообщений. На
движках без scriptable logger buffer может содержать только сообщения, явно
направленные через `BreakpointRuntimeBridge.push_log`.

### stdout/stderr managed process

```text
godot_output
{
  "id":"<managed_id>",
  "since_seq":0,
  "stream":"both"
}
```

Этот источник особенно важен при parse error, crash или сбое до запуска runtime
bridge. Как и у runtime log, сохраняйте `latest_seq` и не перечитывайте весь лог
после каждого действия.

Успешный сценарий требует:

- процесс не завершился неожиданно;
- в новых runtime/managed логах нет относящихся к сценарию ошибок;
- assertions и фактический кадр согласуются.

## Диагностика типичных отказов

### Runtime tool не подключается к `9081`

1. Проверить `godot_output` по `managed_id`.
2. Если процесс завершился — читать `exit_code`, stdout и stderr.
3. Если процесс жив — повторить `runtime_get_tree` после нескольких кадров.
4. Проверить, что запущен один экземпляр проекта и autoload включён.
5. Не пытаться чинить это Windows-инъекцией: она не восстанавливает bridge.

### Окно чёрное

1. Запросить `runtime_get_tree`.
2. Если нет `UniversalTestPlayer` и предметных узлов — искать parse/runtime error
   в `godot_output`.
3. Если дерево готово — запросить следующий `runtime_screenshot`.
4. Проверить размер PNG. Нулевой/неожиданный размер — отдельная проблема viewport.
5. Не считать наличие процесса доказательством готового мира.

Ранее в `playground_runtime.gd` чёрный кадр вызывали ошибки вывода типов GDScript,
а не MCP или double renderer. Поэтому stderr проверяется раньше графических
гипотез.

### Камера вращается, но WASD и `E` не работают

Для прямого `playground.tscn` это обычно означает одно из состояний:

- отсутствуют InputMap actions;
- key event содержит только logical code, а код игры читает
  `physical_keycode`;
- инвентарь открыт, поэтому player process отключён, а interactor disabled;
- камера не наведена на interactable, поэтому `E` штатно ничего не открывает.

Проверка:

1. `inventory_open` должен быть `false`.
2. После импульса `move_forward` позиция должна измениться.
3. `ItemWorldInteractor.current_snapshot` перед `E` не должен быть пуст.
4. Tab должен быть `4194306`, E — `69`.
5. В установленном bridge должны заполняться и `keycode`, и
   `physical_keycode`.

### Agent action остался зажат

Немедленно отправить `pressed:false` для:

```text
move_forward
move_back
move_left
move_right
jump
boost
```

После этого проверить позицию двумя последовательными чтениями. Не закрывать
процесс, пока actions удерживаются, если мир нужно передать человеку.

### Мышь человека вращает камеру, но клавиатура не двигает

1. Агент отпускает все actions.
2. Инвентарь закрывается.
3. Проверяется `inventory_open:false`.
4. Проверяется фокус игрового `Window` изнутри Godot:

   ```text
   runtime_call_method
   {
     "path":"/root",
     "method":"has_focus",
     "args":[],
     "confirm":true
   }
   ```

5. Если получено `return:false`, агент может вернуть фокус без Windows-команд:

   ```text
   runtime_call_method
   {
     "path":"/root",
     "method":"grab_focus",
     "args":[],
     "confirm":true
   }
   ```

6. Повторный `has_focus` должен вернуть `true`. Если пользователь после этого
   переключится обратно в IDE/чат, окно закономерно снова потеряет фокус; перед
   ручной игрой достаточно обычного клика внутри игрового окна.
7. Если `has_focus:true`, но проблема остаётся, проверяются InputMap,
   `control_enabled`, physics processing, controller snapshot и runtime-логи.

Не использовать Windows `PostMessage` как «исправление»: это создаёт второй,
отличающийся от человеческого, канал ввода и маскирует дефект.

### MCP host зависает на initialize

1. Не посылать raw TCP-команды в игру как обычный рабочий путь.
2. Перезапустить MCP client, чтобы он заново поднял stdio host.
3. Выполнить `breakpoint-mcp doctor`.
4. Сверить совместимость npm host и checked-in addon.
5. Не раскрывать bridge secret в логах диагностики.

Raw bridge допустим только для разработки самого MCP и не считается выполнением
сценария, в котором пользователь потребовал управление через MCP.

## Корректное завершение и передача мира человеку

Если игру нужно оставить человеку:

1. Отпустить все actions и key downs.
2. Закрыть служебные меню, если они не являются результатом задания.
3. Убедиться, что мир больше не меняется от агентского ввода.
4. Сообщить человеку, что процесс оставлен запущенным, и указать состояние UI.
5. Не останавливать managed process.

Если игру нужно завершить:

1. Получить финальные warning/error логи.
2. Сохранить финальный runtime screenshot.
3. Вызвать:

   ```text
   godot_stop {"id":"<managed_id>"}
   ```

4. Проверить через `godot_output`, что процесс вышел.

Не использовать `Stop-Process -Name godot*`, `taskkill /IM godot*` и аналогичные
широкие команды: они могут закрыть редактор пользователя или другой проект.

## Минимальный шаблон задания для другого агента

Следующий текст можно вставлять в задачу без дополнительных устных пояснений:

```text
Перед началом прочитай docs/MCP_GODOT.md и следуй его контракту.
Используй double console Godot из C:\Godot\godot\bin\.
Запусти res://scenes/testing/playground.tscn через godot_run_managed.
Дождись готового runtime SceneTree. Все действия в игре выполняй только через
runtime_inject_input; наблюдение — через runtime_screenshot, runtime_get_tree,
runtime_get_property, runtime_assert_* и runtime_get_log. Не используй SendKeys,
PostMessage, desktop screenshot или управление системным курсором.

Выполни последовательность: <ШАГИ>.

После каждого шага проверь фактический эффект. Сохрани MCP viewport screenshots
в artifacts/, проверь новые warning/error логи, отпусти все удерживаемые actions.
В конце либо останови именно свой managed process через godot_stop, либо явно
оставь его человеку — в зависимости от задачи. В отчёте перечисли фактические
проверки, артефакты, ошибки логов и состояние процесса.
```

## Чек-лист приёмки агентского сценария

- [ ] Использована double x86_64 console сборка.
- [ ] Процесс запущен через MCP и сохранён `managed_id`.
- [ ] Runtime SceneTree подтверждён до первого ввода.
- [ ] Все игровые события посланы через `runtime_inject_input`.
- [ ] Каждое удержание имеет соответствующий release.
- [ ] Результат подтверждён property/assertion, а не только `injected:true`.
- [ ] Screenshot получен через `runtime_screenshot`, не с рабочего стола.
- [ ] Проверены только новые runtime и managed warning/error логи.
- [ ] PNG/логи сохранены только в `artifacts/`.
- [ ] Не выведен `.godot/breakpoint_mcp.secret`.
- [ ] Собственный managed process корректно остановлен или явно передан человеку.
