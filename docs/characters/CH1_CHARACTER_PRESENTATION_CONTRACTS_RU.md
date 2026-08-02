# CH1 — Character Presentation Contracts and Registry

CH1 создаёт изолированный, headless-safe слой контрактов персонажа. Этап не меняет production player runtime, M3 network runtime или текущие сцены игрока.

Реализованы stable IDs, JSON-safe validation, `CharacterDefinition`, body/animation/socket/appearance profiles, motion/action state, базовый presentation adapter и sealed registry с fallback. Mesh, Skeleton и AnimationPlayer не входят в canonical state. Unsafe resource paths и Object/Node/RID в payload отклоняются.

Проверка:

```text
RUN_CH1_CHARACTER_CONTRACTS_TESTS.ps1 -GodotPath <godot-double-console.exe>
./RUN_CH1_CHARACTER_CONTRACTS_TESTS.sh <godot-double-binary>
```

Профиль выполняет editor import и 30 focused assertions.
