# CHAR1 R1 — сменные визуальные аватары

Основа: USER1, main 53567c0b98d032260dfe81df4bd43a131e32da54.

## Границы

- `AvatarVisualPort`: Node3D, `apply_avatar_state(state, delta)`, `get_avatar_report()`.
- `AvatarRegistry`: идентификатор внешности → PackedScene, с безопасным fallback.
- `RemotePlayerPresenter`: отвечает за интерполяцию, позицию и heading. Графика создаётся через реестр.
- `HumanoidAvatarVisual`: заменяемый procedural fallback с головой/туловищем/руками/ногами, idle/walk/run, фонарём.
- `TrainingAvatarVisual`: альтернативная сцена, подтверждающая независимость реализации.

Визуальный слой **не создаёт** movement authority, PlayerRegistry, Item Graph, Construction, persistence и network protocol. Нельзя делать визуал каноническим владельцем. Параметры сцены не передаются как сетевые объекты.

## Интеграция собственной модели

Создать `PackedScene` с корнем `Node3D` и двумя методами порта. Зарегистрировать её:

```gdscript
presenter.register_appearance_scene("suit_red", "res://scenes/avatars/suit_red.tscn")
presenter.set_appearance("suit_red")
```

Сетевая snapshot-interpolation продолжает обновлять presenter; реализация получает состояние скорости, yaw и фонаря. Ключ `appearance_id` при setup опционален и по умолчанию равен `default`. Для произвольного персистентного выбора скина игроком потребуется отдельный CHAR2-compatible appearance selection contract: **не вводить** новый wire-field без согласованной версионизации протокола.

## Ограничения R1

Это интеграционный первый срез для remote player. Local first-person camera не превращается в третье лицо. Внешняя импортированная модель не была найдена в составе текущего main: CHAR1 не содержит чужой asset. Обязательны cold Godot import, test_v0_char1_avatar_registry и существующие multiplayer/UX0 acceptance gates до merge.
