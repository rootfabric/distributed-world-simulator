# V0-CHAR1 R1 — Production Avatar

CHAR1 добавляет сменный presentation-слой персонажа поверх принятого USER1 main.

## Граница

Gameplay, movement authority, collision, M3 wire state, SM1 и persistence не зависят от конкретной модели.

```text
gameplay/player record
  -> EarthLocalAvatarPresenter
  -> PlayerAvatarHost
  -> AvatarProvider
  -> AvatarPresenter
```

Core AvatarDefinition содержит `provider_id`, semantic animation mapping, sockets и appearance, но не содержит scene/model/animation asset paths. Конкретные asset paths принадлежат provider implementation/options.\n\nComposition root тоже не `preload`-ит конкретные providers: `ProductionAvatarBootstrap` читает `avatar-provider-manifest.v1.json`, динамически создаёт фабрики и проверяет их через `AvatarProvider` interface. Новый provider добавляется manifest-записью + реализацией интерфейса, без изменения Earth/gameplay/bootstrap.

## Providers

- `avatar/quaternius` — использует существующий animated presenter; при отсутствии локальных внешних CC0 assets использует его встроенный fail-safe humanoid.
- `avatar/procedural_humanoid` — полностью встроенный Godot procedural humanoid.

## Runtime swap

- `character.avatar.list`
- `character.avatar.set <character-id>`
- `character.avatar.status`

Смена presenter выполняется внутри `PlayerAvatarHost`. Последние motion/action states и first-person mode переносятся на новый presenter.

## CHAR1 / CHAR2 boundary

CHAR1 выбирает и отображает локальный production avatar. Он не добавляет новый network protocol и не делает `character_id` каноническим сетевым состоянием.

Репликация выбора avatar и remote avatar binding относятся к CHAR2.
