# CH4 — Quaternius Animated Character Lab

CH4 — изолированный presentation vertical поверх актуального `main`. Он намеренно не меняет `LunarPlayer`, controller, collision, inventory, Item Graph, prediction/reconciliation или сетевые wire contracts.

## Цель

Проверить на реальной ходимой сцене Universal Base Characters + Universal Animation Library от Quaternius до production-интеграции.

Граница ответственности:

```text
CharacterBody3D / collision / movement
                |
                v
       QuaterniusAvatarPresenter
                |
                +-- visible Base Character skeleton
                +-- hidden Animation Library skeleton
                +-- same-rig pose copy by bone name
```

Presentation получает только `velocity`, `up` и желаемое направление взгляда. Он не читает input, не вызывает `move_and_slide`, не создаёт collision и не передаёт root motion игровому телу.

## Почему ассеты не коммитятся

Официальные Standard ZIP распространяются Quaternius бесплатно под CC0, но каждый пакет весит десятки/сотни мегабайт и itch.io выдаёт его через интерактивную download-страницу. CH4 хранит код интеграции, а локальные исходники устанавливаются в `assets/external/quaternius/` и добавляются в `.git/info/exclude`.

Нужны два бесплатных файла:

- `Universal Base Characters[Standard].zip`;
- `Universal Animation Library[Standard].zip`.

Положите оба ZIP в обычную Windows-папку `Downloads`, затем выполните:

```powershell
.\INSTALL_CH4_QUATERNIUS_ASSETS.ps1
```

Установщик полностью распакует оба пакета, сохраняя текстуры и зависимые `.bin` файлы.

## Анимация

CH4 сначала ищет анимации, встроенные в выбранную модель. Если их нет, он загружает Universal Animation Library отдельной скрытой сценой и копирует pose с её skeleton на skeleton персонажа по нормализованным именам костей.

Позиция root/hips/pelvis не копируется. Поэтому даже если выбран файл с root-motion данными, movement authority остаётся у `CharacterBody3D`. Для качества всё равно предпочтителен вариант библиотеки без root motion.

Семантика первой итерации:

- `idle` — горизонтальная скорость до 0.12 м/с;
- `walk` — ниже run threshold;
- `run` — выше run threshold.

Выбор конкретных animation clips делается динамически по именам (`idle`, `walk`, `run`, `jog`, `sprint`), чтобы не зашивать структуру ZIP в production-код.

## Проверка

```powershell
.\RUN_CH4_QUATERNIUS_CHARACTER_TESTS.ps1
.\PLAY_CH4_QUATERNIUS_CHARACTER_LAB.ps1
```

Если внешние Quaternius-файлы установлены, focused runner автоматически включает строгую проверку реальной модели: target skeleton должен загрузиться, `Idle/Walk/Run` должны разрешиться, а presenter должен выйти в `QUATERNIUS_RETARGET` или `QUATERNIUS_EMBEDDED`.

Без внешних файлов runner проверяет presentation contract на процедурном fallback. Fallback существует только как fail-safe и unit-test fixture.

### Fix1 — Windows PowerShell и регистр glTF URI

Официальный Standard ZIP может содержать относительные glTF URI, регистр которых отличается от реального имени каталога, например `textures/...` при каталоге `Textures/...`. Windows открывает такой путь, но Godot предупреждает, что экспорт на case-sensitive платформы будет сломан.

Перед editor import runner и PLAY теперь запускают `quaternius_asset_preflight.gd`. Он проходит только локальные `.gltf`, находит относительные `uri` и исправляет только регистр сегментов по реальному filesystem. Геометрия, числовые поля glTF, `.bin` и текстуры не переписываются.

Windows PowerShell 5.1 также представляет native stderr как `NativeCommandError`. Godot пишет обычные warnings в stderr даже при exit code 0, поэтому CH4 runner временно переводит native invocation в non-terminating режим, после чего принимает решение по реальному exit code и маркерам `FAIL`, `SCRIPT ERROR`, `Parse Error`, `Compile Error`.

`PLAY_CH4_QUATERNIUS_CHARACTER_LAB.ps1` теперь сам выполняет preflight и полный editor import. Поэтому запуск lab больше не зависит от того, был ли до него вручную успешно завершён focused runner.

Управление lab:

- `WASD` — ходьба;
- `Shift` — бег;
- `Space` — прыжок;
- мышь — камера;
- `V` — повернуть модель на 180°, если конкретный export имеет обратную forward-axis;
- `Esc` — отпустить мышь, ЛКМ — снова захватить.

## Следующий этап после принятия CH4

Только после визуальной приёмки lab следует подключать тот же presenter под существующий `LunarPlayer.visual_root`, а затем под `RemotePlayerPresenter`. Collision/body/controller/network при этом остаются существующими.
