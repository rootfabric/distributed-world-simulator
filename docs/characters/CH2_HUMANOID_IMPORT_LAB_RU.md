# CH2 — Humanoid Import Lab

CH2 добавляет изолированный humanoid asset pipeline без подключения к production M3 runtime.

Реализованы три `CharacterDefinition`: standard, slim и technical dummy. Все используют общий `body/human_standard`, семантический animation profile и semantic sockets. Процедурный humanoid содержит 12-костный skeleton, 10 обязательных анимаций плюс RESET, материалы и сокеты для головы, рук, груди, спины, бедра и фонаря.

`HumanoidImportValidator` загружает сцену, проверяет root type, skeleton, обязательные кости, все semantic animation mappings и все socket paths. Каталог загружается fail-closed через `CharacterCatalogLoader`.

Проверка:

```text
RUN_CH2_HUMANOID_IMPORT_LAB_TESTS.ps1 -GodotPath <godot-double-console.exe>
./RUN_CH2_HUMANOID_IMPORT_LAB_TESTS.sh <godot-double-binary>
```

Профиль выполняет editor import, CH1 regression и 37 CH2 assertions.
