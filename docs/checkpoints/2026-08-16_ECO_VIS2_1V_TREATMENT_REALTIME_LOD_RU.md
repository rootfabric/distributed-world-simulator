# ECO VIS2.1-V — Treatment Realtime LOD

Дата: 2026-08-16

Статус: **IMPLEMENTED_CANDIDATE**

## Validated base

VIS2.1 Windows-runtime-validated candidate:

`7ed945b037f9360fe0ba05dedd641e5bfa62c14c`

Этот base включает:

- Windows exact-engine automated VIS2.1 PASS;
- long smoke G20..G220 с rolling eviction;
- graphical CONTROL/TREATMENT confirmation;
- isolated graphical launcher repair;
- отдельный Windows validation checkpoint.

## Цель

Вернуть для единственной видимой TREATMENT population camera-distance LOD, не меняя causal simulation и не возвращая whole-field PH5 rebuild.

CONTROL остаётся data-only.

## Presentation tiers

VIS2.1-V использует те же читаемые distance bands, что ранний VIS1.4 visual field:

- NEAR: текущий realtime trunk + canopy, до 110 m;
- MID: упрощённый canopy proxy, 75..240 m;
- FAR: ещё более дешёвый canopy proxy, начиная с 190 m.

Диапазоны намеренно перекрываются и имеют visibility margins, чтобы переход не происходил в одной жёсткой точке.

Birth/death animation применяется к общему plant root, поэтому сохраняется для всех realtime LOD tiers.

## Архитектурные границы

VIS2.1-V не меняет:

- CONTROL runner;
- TREATMENT runner;
- common CRN derivation;
- TraceContract;
- Comparator;
- rolling caches;
- canonical comparison;
- Treatment environment forcing.

Новый renderer является presentation-only subclass существующего VIS1.8A realtime proxy renderer.

После fork:

- CONTROL = data-only;
- TREATMENT = единственный visible population;
- progressive PH5 = OFF;
- whole-field PH5 rebuild = 0;
- realtime LOD = near/mid/far.

## UI cleanup

После создания paired fork старый левый VIS2.0 source panel скрывается, потому что он показывает BASELINE source provider и визуально может быть ошибочно воспринят как текущий Treatment profile.

Основным post-fork UI остаётся VIS2.1 CONTROL vs TREATMENT comparison panel.

## Test contract

VIS2.1-V gate сначала повторно запускает полный validated VIS2.1 causal/boundedness gate, затем в отдельном isolated project проверяет:

- custom LOD renderer installed;
- paired fork работает;
- VIS2.0 source panel скрывается после fork;
- near/mid/far thresholds;
- три tiers присутствуют у каждого live Treatment proxy;
- camera movement не меняет canonical simulation traces;
- paired progression продолжает работать;
- CONTROL остаётся data-only;
- visible population field = 1;
- progressive/whole-field PH5 после fork отсутствует;
- LOD tiers следуют за turnover population;
- common CRN root сохраняется.

## Exact engine

Требуется:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

В agent environment выполнен exact-engine parser preflight новых renderer/lab/test surfaces на API-compatible local dependency stubs. Full Windows integrated gate остаётся обязательным.

## Следующий шаг

Запустить `RUN_ECO_VIS2_1V_TESTS.ps1` на Windows exact worktree. После PASS — `RUN_ECO_VIS2_1V_LAB.ps1` и визуально проверить реальные near/mid/far переходы при движении камеры вокруг новых Treatment plants.
