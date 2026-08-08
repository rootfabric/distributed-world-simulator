# CH5 — Full-Body First-Person

Ветка: `feature/ch5-full-body-first-person`

База: принятый CH4 `dc51a2d645e166b9a5d7985939cf1eb11056ef00`.

## Цель

Добавить в изолированную character-lab полноценный вид от первого лица, при котором локальный игрок продолжает видеть собственное тело. Production `LunarPlayer`, network runtime, inventory, prediction/reconciliation и collision-контракты на этом этапе не меняются.

## Архитектура

CH5 добавляет `FullBodyFirstPersonAdapter` поверх принятого CH4 `QuaterniusAvatarPresenter`.

Адаптер не владеет вводом, камерой, `CharacterBody3D`, collision или перемещением. Он отвечает только за локальную presentation-маску головы.

Для Quaternius используется bone-scale mask: ищется `Head` bone целевого `Skeleton3D`, в first-person его pose scale уменьшается до `0.001`, а в third-person восстанавливается исходное значение. Маска повторно применяется каждый кадр, поэтому animation pose не может вернуть голову в локальную камеру. Для процедурного fallback скрывается только узел `Head`.

Камера не является дочерним узлом `Head`/`Skeleton3D`. Она находится на отдельной стабильной высоте глаз `1.62 m`, поэтому walk/run animation не создаёт неконтролируемый head-bob.

## Camera rig

```text
CharacterBody3D
├── CollisionShape3D
├── AvatarPresentation
├── FullBodyFirstPersonAdapter
└── CameraYaw @ y=1.62
    └── CameraPitch
        ├── FirstPersonCamera
        └── ThirdPersonSpringArm
            └── ThirdPersonCamera
```

В third-person персонаж продолжает визуально ориентироваться по направлению движения. В first-person визуальное тело ориентируется по yaw камеры, поэтому `A/D` не разворачивают всё тело в сторону бокового перемещения.

## Управление lab

- `WASD` — движение.
- `Shift` — бег.
- `Space` — прыжок.
- мышь — yaw/pitch камеры.
- `C` — переключение first-person / third-person.
- `V` — разворот модели на 180° для диагностики forward axis.
- `Esc` — освободить мышь.

## Что должно быть видно в first-person

Тело остаётся включённым: корпус, руки и ноги продолжают рендериться и анимироваться. Локально маскируется только голова, чтобы камера не находилась внутри лица. На других клиентах в будущем должна оставаться полная модель с головой — это локальный presentation-state и он не должен синхронизироваться по сети.

## Тесты

Запуск:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_CH5_FULL_BODY_FIRST_PERSON_TESTS.ps1 `
    -GodotPath $Godot
```

Runner включает CH4 regression и CH5 focused tests.

Графическая проверка:

```powershell
.\PLAY_CH5_FULL_BODY_FIRST_PERSON_LAB.ps1 `
    -GodotPath $Godot
```

В HUD для first-person ожидаются:

```text
view: FIRST_PERSON
asset: QUATERNIUS_RETARGET
head mask: ON (BONE_SCALE)
matched bones: 65
```

Для third-person:

```text
view: THIRD_PERSON
head mask: OFF (BONE_SCALE)
```

## Acceptance gate

- CH4 presenter regression PASS.
- CH4 character lab regression PASS.
- CH5 adapter test PASS.
- CH5 lab test PASS.
- При установленных Quaternius assets используется `QUATERNIUS_RETARGET` или `QUATERNIUS_EMBEDDED`, а не fallback.
- Head bone найден, first-person mask = `BONE_SCALE`.
- Переключение `C` не скрывает весь avatar.
- Камера не является дочерней `Skeleton3D`/Head bone.
- Root motion остаётся выключенным.
- Third-person полностью восстанавливает голову.
- Production `LunarPlayer` пока не изменён.

## Не входит в CH5

CH5 не решает directional locomotion. При движении назад или боком пока используется базовая CH4 semantic-анимация `Walk/Run`. Отдельный следующий этап должен добавить forward/back/strafe blend или directional clips без изменения сетевого movement authority.

После принятия CH5 production-интеграцию следует делать отдельным небольшим этапом: заменить в `LunarPlayer` полное скрытие `visual_root` в first-person на локальный presentation adapter, сохранив существующие camera/controller/network границы.
