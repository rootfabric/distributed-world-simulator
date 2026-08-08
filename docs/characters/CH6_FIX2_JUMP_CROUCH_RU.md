# CH6 fix2 — Jump / Crouch Presentation Polish

## Причина

После CH6 fix1 first-person body suppression и Shadow Preservation работают графически. Выявлена небольшая проблема тестового lab: клавиша `V` меняла технический `model_yaw_offset` на 180 градусов. Поскольку shadow proxy повторяет transform world presentation, тень тоже разворачивалась и персонаж визуально начинал бежать спиной вперед.

`model_yaw_offset` нужен как техническая настройка импорта/выравнивания конкретного ассета, но не как gameplay-команда. В fix2 пользовательский hotkey `V` удалён полностью. Сам setter `set_model_yaw_offset_degrees()` оставлен в presenter-е для конфигурации будущих моделей.

## Quaternius Universal Animation Library

Для используемого `UAL1_Standard` подтверждены клипы:

- `Jump_Start`
- `Jump`
- `Jump_Land`
- `Crouch_Idle`
- `Crouch_Fwd`

Текущий lab сознательно использует простой набор без AnimationTree:

- airborne state -> `Jump`;
- crouching + почти нулевая горизонтальная скорость -> `Crouch_Idle`;
- crouching + движение -> `Crouch_Fwd`.

`Jump_Start` и `Jump_Land` уже распознаются и публикуются как animation capabilities, но пока не включены в переходы. Это позволяет позже добавить короткие start/land transitions без изменения общего presenter contract.

## Presentation state contract

`QuaterniusAvatarPresenter.apply_motion()` получил необязательный четвёртый аргумент `motion_state`:

```gdscript
avatar.apply_motion(
    velocity,
    up,
    facing_direction,
    {
        "grounded": is_grounded,
        "crouching": is_crouching,
    }
)
```

Это presentation-only metadata. Presenter по-прежнему:

- не читает `Input`;
- не вызывает `move_and_slide`;
- не владеет `CharacterBody3D`;
- не меняет network authority;
- не применяет root motion.

Для будущего дрона, животного, киборга или другого тела gameplay/controller layer может передавать собственные presentation states либо использовать другой presenter. CH6 generic `ControllableViewAdapter` и Shadow Preservation от Quaternius не зависят.

## Crouch в изолированном lab

Добавлен тестовый crouch controller, только для character lab:

- `Ctrl` — удерживать присед;
- скорость в приседе: 1.8 м/с;
- capsule height: 1.85 -> 1.15 м;
- camera eye height: 1.62 -> 1.02 м с плавным переходом;
- прыжок во время приседа блокируется;
- при отрыве от земли crouch state снимается.

Это не production crouch для `LunarPlayer`. Проверка потолка/возможности встать под препятствием, сетевой crouch state и authoritative collision reconciliation должны делаться отдельно при production integration.

## Jump

Физика прыжка в lab не изменилась: `CharacterBody3D` остаётся единственным владельцем движения. Presenter получает `grounded=false` после `move_and_slide()` и переключается на `Jump`. Позиция из анимации root/hips/pelvis по-прежнему не переносится в gameplay body.

## First-person shadow

Shadow Preservation не менялся. WORLD_PROXY использует тот же Mesh/Skin/Skeleton и поэтому автоматически повторяет `Jump` и crouch pose. В first person:

- world body не рисуется;
- shadow-only proxy остаётся активным;
- прыжок и присед должны быть видны по тени.

## Управление lab после fix2

```text
WASD   движение
Shift  бег
Ctrl   присед
Space  прыжок
C      first / third person
Mouse  камера
```

`V` больше не имеет пользовательского действия.

## Acceptance

До production integration требуется Windows graphical rerun с реальным Quaternius asset:

1. `Jump`, `Crouch_Idle`, `Crouch_Fwd` реально резолвятся из UAL1.
2. Прыжок показывает airborne animation.
3. Ctrl меняет pose, высоту камеры и capsule в lab.
4. В first person тело не появляется.
5. Тень сохраняется и повторяет jump/crouch animation.
6. В third person полное тело и тень остаются корректными.
7. `V` ничего не разворачивает.
8. Root motion остаётся выключен.
