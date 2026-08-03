# CH3 — Isolated Player Presentation Host

CH3 создаёт единый `PlayerPresentationHost` и `HumanoidCharacterPresentationAdapter`, используемый одинаково local и simulated-remote fixtures. Этап по-прежнему не меняет M3 production runtime.

## Состав

- `SemanticAnimationDriver` выводит semantic animation из фактических `velocity`, `grounded` и `facing_yaw`, а не из локального `Input`;
- one-shot actions защищены `action_sequence`;
- смена модели транзакционна: новый adapter полностью конфигурируется до удаления старого;
- неизвестный character ID использует registry fallback;
- first-person policy скрывает только голову и визор, сохраняя тело и тени;
- semantic sockets доступны через host;
- лабораторный `CharacterBody3D` поддерживает ходьбу, бег, прыжок, приземление, pickup action и смену модели.

## Визуальная сцена

```text
res://scenes/labs/character/character_presentation_lab.tscn
```

Управление:

```text
WASD  движение
Shift бег
Space прыжок
E     pickup-анимация
Tab   следующий персонаж
F     first/third person
```

Запуск:

```text
PLAY_CH3_CHARACTER_PRESENTATION_LAB.ps1 -GodotPath <godot-double.exe>
./PLAY_CH3_CHARACTER_PRESENTATION_LAB.sh <godot-double-binary>
```

Полная проверка:

```text
RUN_CH3_ISOLATED_PRESENTATION_HOST_TESTS.ps1 -GodotPath <godot-double.exe>
./RUN_CH3_ISOLATED_PRESENTATION_HOST_TESTS.sh <godot-double-binary>
```
