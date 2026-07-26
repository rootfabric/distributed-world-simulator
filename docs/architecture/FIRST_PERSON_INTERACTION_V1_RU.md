# First-person Interaction v1

## Назначение

Слой взаимодействия отделён от контроллера движения, постоянного хранилища и
конкретной реализации объекта. Контроллер отвечает только за движение и камеру.
`WorldInteractor` отвечает за поиск цели и вызов контракта. Сам объект определяет
информацию, действие и визуальную реакцию.

## Поток данных

```text
Active First-person Camera
        │ центральный physics ray, 6 м
        ▼
WorldInteractor
        │ ищет группу world_interactable
        ▼
Interactable contract
        ├── get_interaction_descriptor(actor)
        ├── set_interaction_focus(enabled)
        └── interact(actor, context)
                │
                ▼
SurveyBeaconInteractable
                │
                ▼
LunarWorldRepository
        ├── меняет beacon_state
        ├── меняет landmark.enabled
        ├── пишет journal
        ├── сохраняет chunk
        └── обновляет runtime и landmark marker
```

## Контракт интерактивного объекта

Объект должен:

1. входить в группу `world_interactable`;
2. возвращать словарь `lunar.interaction_descriptor.v1`;
3. принимать фокус через `set_interaction_focus(bool)`;
4. выполнять основное действие через `interact(actor, context)`;
5. возвращать результат с `success` и `message`.

Минимальный descriptor:

```text
schema
entity_id
entity_type
title
details
prompt
```

`WorldInteractor` добавляет к descriptor текущую дистанцию и точку попадания.

## Первая реализация

Survey Beacon поддерживает:

- наведение центральным лучом в режиме первого лица;
- контурную подсветку;
- вывод состояния, ID и дистанции;
- `E` для включения или выключения сигнала;
- изменение цвета сигнальной сферы и надписи `SURVEY/STANDBY`;
- сохранение состояния в компоненте `beacon_state`;
- скрытие дальней метки и снятие cache pin у выключенного маяка.

## Ограничения v1

- один основной action;
- нет удержания клавиши и progress action;
- нет вторичного действия и контекстного меню;
- нет placement preview;
- outline основан на `material_overlay`, а не на отдельном post-process pass;
- взаимодействие отключено в третьем лице и в режиме спектатора.
