# CHAR2 R1 — Real Multiplayer Avatar / Host and Join

Основа: CHAR1 #745 + реалистичный preview #747, текущая CHAR2 feature-ветка. Не изменять main до свежего Windows GUI acceptance.

## Реальный игровой сценарий

Не используйте отдельную CHAR1 viewer-сцену: она **не сетевой клиент**.

Нужен Windows ZIP, собранный через `BUILD_CHAR1_WITH_AVATAR.cmd` **из exact CHAR2 HEAD**. Архив должен содержать настоящий Superhero_Male_FullBody, UAL1 animation pack и Godot 4.7.1.double; пакеты с прежними HEAD показывают капсулу у удалённых игроков.

1. Распаковать ZIP в записываемый каталог, например `C:\DWS-CHAR2-Network\`.
2. Запустить `START_NETWORK_CHAR1.cmd` в корне `CHAR1_REALISTIC_WITH_AVATAR`. Он проверяет встроенный Godot, проверяет Quaternius, импортирует сцену и запускает настоящий UX0 Product Shell.
   **Упрощённый вариант:** запустить `START_TWO_CLIENTS_CHAR1.cmd` вместо Product Shell. Он сам поднимет dedicated server на свободном UDP 24580, дождётся его готовности и откроет client A и client B в окнах 900×600 рядом. Не закрывает чужие процессы и отказывает, если порт занят.
3. В Product Shell нажать **Host World**. World = Earth, player = **a**, port = **24580**, слот = **char2-smoke**. Это запускает dedicated server и GUI client A.
4. Вернуться в Product Shell, нажать **Join World**. Server = **127.0.0.1**, port = **24580**, player = **b**. Появится отдельный GUI client B, подключённый к тому же серверу.
5. Поставить клиентские окна рядом. В обоих клиентах увидеть **полноценную** модель другого игрока (Quaternius, а не Mesh Capsule), Idle/Walk/Run при его движении.
6. **V** или **F7** в фокусе клиента переключает first-/third-person. First-person: **локальное** тело невидимо; remote всегда виден. Third-person: локальное и удалённое тела видны.
7. **F1**: `character.camera.status`, `character.avatar.status`, `character.remote.status`; `network.jitter.snapshot` показывает NX5. В статусе удалённого игрока ожидаются `provider_id=avatar/quaternius`, `asset_mode=QUATERNIUS_RETARGET`, `legacy_capsule_visible=false`, `input_authority=false`. Переход через seam A→B→A и восстановление/reconnect не должны разрушать аватар другого клиента.

Управление W/A/S/D, Shift run, пробел jump, Esc освободить курсор; инструменты/инвентарь наследуются от USER1. Пользователь видит модель B из окна A, а модель A из окна B.

## Архитектура

```text
dedicated server → M3/SM1 canonical snapshots
    ├─ client A
    │   ├─ local camera EarthExplorer → first/third-person
    │   └─ EarthNetworkAvatarPresenter(B) → NX5 interpolation
    │          → PlayerAvatarHost → Quaternius provider → B's model
    └─ client B
        ├─ local camera EarthExplorer → first/third-person
        └─ EarthNetworkAvatarPresenter(A) → NX5 interpolation
               → PlayerAvatarHost → Quaternius provider → A's model
```

- `earth_app.gd` introduces a **visual-only** factory hook to preserve historical presenter default for all inherited worlds.
- `earth_char1_avatar_app.gd` supplies the specialized remote wrapper; Quaternius selection remains a provider implementation detail, not a network field.
- `earth_network_avatar_presenter.gd` inherits the exact accepted NX5 interpolator and Earth projection. It hides *only the already-unneeded legacy capsule* when a provider has initialized successfully; spotlight and interpolation keep working.
- `earth_local_avatar_presenter.gd`: local first-person hides its own avatar root; remote visual tree remains separate. V/F7 uses a second camera child under the EarthExplorer frame; no second controller.
- Player `character_id` is **not yet replicated independently**. Each client can choose its own local display profile; per-player network avatar selection is a future versioned contract. The server does not store GLB paths, skeletons or renderer state.

## Hard verification

`tests/characters/test_char2_network_avatar_client_presentation.gd` checks real provider instantiation on the remote NX5 wrapper, no capsule, canonical snapshot-clock preservation, floating-origin shift, walk→run→reconnect idle, no input authority, local third-person visibility and first-person isolation.

Inherited: `test_nx5_remote_snapshot_interpolation_integration.gd`, `test_v0_sp1_remote_earth_render_frame.gd`, USER1 seam+slice, UX0, CHAR1.

**Windows GUI manual gate** must confirm two independent GUI clients, both CONNECTED, two remote bodies visible, move animations, V/F7 and reconnect/seam. An automated headless PASS is not equivalent to real two-client graphical acceptance.

## Release status

CHAR2 is intentionally a stacked feature branch on top of #747 → #745, not in main. Build a new ZIP from CHAR2 HEAD before user test. Do not re-use the previous CHAR1 ZIP whose exact source predates this remote-model adapter.
