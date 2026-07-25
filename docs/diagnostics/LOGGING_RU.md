# Диагностика и логирование

## Постоянный лог

```text
user://logs/lunar_simulation.jsonl
```

Формат — JSON Lines, одна запись на строку. Лог автоматически ротируется
примерно после 2 МБ, сохраняются три предыдущих файла.

Основные категории:

```text
application
ui
display
gameplay
entity_registry
integration_test
diagnostics
```

## Диагностический снимок

Клавиша `F9` создаёт:

```text
user://diagnostics/diagnostic_<date>.json
```

Внутри:

- версия Godot и ОС;
- разрешение и режим окна;
- позиция игрока;
- snapshot зон и чанков;
- snapshot Entity Registry;
- последние миграции;
- последние записи лога;
- результат мини-теста.

## Где находится user:// в Windows

Обычно:

```text
%APPDATA%\Godot\app_userdata\Real Scale Procedural Moon\
```

Для обратной связи наиболее полезны:

```text
logs\lunar_simulation.jsonl
diagnostics\diagnostic_*.json
```
