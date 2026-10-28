# CHAR1 Embedded Real Avatar Windows R1

Цель: самодостаточная тестовая Windows-сборка **с настоящей Quaternius-моделью внутри**.
Предыдущие portable ZIP содержали исходники и запускатель, но НЕ внешние модели.
Этот этап устраняет зависимость готового ZIP от внешних Quaternius-файлов и
локально установленного Godot. Основная ветка и multiplayer-ядро не меняются.

## Что находится в ZIP

CHAR1_REALISTIC_WITH_AVATAR/
- runtime/godot.windows.editor.double.x86_64.exe и console.exe (canonical 4.7.1 double)
- project/ — exact tracked Git snapshot текущего HEAD
- project/assets/external/quaternius/base_characters/ — локально предоставленный официальный CC0
- project/assets/external/quaternius/animation_library/ — локально предоставленная UAL1 CC0
- START_CHAR1.cmd и VERIFY_CHAR1.cmd — автономный запуск через bundled runtime
- BUILD_INFO.json — исходный HEAD/TREE и исходные SHA256
- EMBEDDED_BUILD_INFO.json — hash движка и реально упакованных glTF/GLB, asset counts и PASS tests
- LICENSES/ — MIT notice Godot и provenance CC0 Quaternius
- evidence/ — результаты preflight, cold import и strict headless tests

Это **готовый portable Godot runtime + исходный проект/ассеты**, а не
оптимизированный экспорт в отдельную production Game.exe. Для ручного
CHAR1 GUI-acceptance этого достаточно. При первом запуске выполняется
import встроенных ассетов, затем открывается обычное 3D-окно.

## Сборка на Windows, где Quaternius ранее уже проверен

Исходники находятся в ветке feature/char1-realistic-avatar-preview-r1,
поверх CHAR1 PR #745. Пользовательский Windows-host уже имеет нужные
base_characters и animation_library (44/4 source scenes, ранее 65 matched bones).

В свежем checkout exact HEAD:

    pwsh -NoProfile -File .\BUILD_CHAR1_WITH_AVATAR.ps1

Если ассеты в нестандартном каталоге:

    pwsh -NoProfile -File .\BUILD_CHAR1_WITH_AVATAR.ps1 -AssetSource 'C:\...\quaternius'

Сборщик кладёт ZIP в artifacts/char1-with-avatar/; существующий ZIP
не перезаписывает. До запуска проверяет Git HEAD/clean tracked source,
canonical console Godot SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5,
реальные glTF и UAL1_Standard.glb, и **не позволяет** пустой/FALLBACK build.

Действия сборщика:
1. git archive exact HEAD → исходный tracked-source ZIP
2. копирование только двух Quaternius asset families и локального Godot runtime
3. CH4 glTF URI preflight
4. cold Godot import (exit=0, no SCRIPT/PARSE/COMPILE ERROR)
5. test_char1_embedded_quaternius_assets.gd: настоящая модель, rig,
   >=50 bone matches при RETARGET, UAL1, Idle/Walk/Run, no root motion
6. test_char1_first_person_body_visibility.gd и CHAR1 provider regression
7. удаление Godot import cache (восстанавливается при первом запуске)
8. сборка ZIP и CRC/SHA256 verification model+animation из самого ZIP

**Не надо коммитить бинарные модели в Git.** Лицензия Quaternius CC0
позволяет распространять их в готовом пакете; источники и лицензии
сохраняются внутри него. Godot MIT notice включён.

## Приёмка ZIP на чистой Windows-машине

Распаковать в доступную для записи папку, запустить START_CHAR1.cmd.

Нет необходимости заранее скачивать Godot или Quaternius. START_CHAR1.cmd
явно указывает bundled runtime/console.exe и использует существующий
portable PS5.1 Process.Handle fix.

Проверить:
- THIRD_PERSON: настоящая модель Superhero_Male_FullBody видна и анимируется
- FIRST_PERSON: локальное тело **полностью скрыто**, мир/камера видны
- C/V переключает эти состояния в обе стороны
- I/W/R: Idle/Walk/Run; 1/2/3: реальные/процедурные варианты
- после смены аватара в FIRST_PERSON скрытие сохраняется
- отдельно VERIFY_CHAR1.cmd повторяет product/headless/GUI smoke
- ассеты должны загружаться именно RETARGET либо EMBEDDED, не FALLBACK

## Автоматическая сборка

GitHub Actions: .github/workflows/char1-bundled-real-avatar-windows.yml

Ubuntu job проверяет код и запрет fallback; Windows job на
self-hosted Windows runner использует ранее проверенные локальные CC0
ассеты, выполняет реальные Godot gates и публикует большой ZIP как
workflow artifact. Если self-hosted runner offline/queued, выполнить
BUILD_CHAR1_WITH_AVATAR.ps1 на проверенной Windows-машине.

CHAR1 #747 остаётся Draft до independent exact GUI-verification этого ZIP.
Не делать merge в main автоматически.
