# FPE-R2 S5 ACCEPTED → S6 HAND VISUAL PROVIDER BOUNDARY

Дата: 2026-08-12

Ветка: `research/first-person-embodiment-prototype`

База research lane остаётся frozen accepted CH9.6:

`e547ba52a440e72cc02c6bbe449edaf160bae7ab`

## S5 acceptance

Операторский focused run на `04976854` завершился полным PASS.

Ключевые gates:

- S2 item viewmodel catalog: PASS, 27 assertions;
- S3 hand pose catalog: PASS, 20;
- S3 articulated hand rig: PASS, 23;
- S3 posed viewmodel: PASS, 17;
- S4 two-hand grip contract: PASS, 20;
- S4 two-hand viewmodel: PASS, 36;
- S5 secondary-hand support: PASS, 33;
- S5 two-hand third-person presenter: PASS, 20;
- sandbox owner collision isolation: PASS, 30;
- performance gate: PASS, 10;
- graphical scene load: PASS, 22;
- final marker: `FirstPersonEmbodiment focused tests: PASS`.

Graphical evidence после Fix2 также закрывает реальную replica-identity дыру:

- slot 1 / beacon: `R: beacon_pinch`, S4 `FREE`, S5 world left `FREE`;
- slot 2 / replica `beacon_mount_base`: `R: bulky_carry`, `L: support_cradle`;
- S4: `ACTIVE`, profile `mount_base_two_hand`;
- S5: `ACTIVE`, current fallback mode `FALLBACK_PROCEDURAL_ARM`;
- third-person avatar визуально удерживает синий mount-base двумя руками;
- возврат на beacon освобождает secondary support.

Итог:

`FPE-R2 S5 RESEARCH ACCEPTED`.

Это research acceptance, не promotion в canonical runtime.

## S6 purpose

S3–S5 доказали pose/grip/two-hand contracts, но procedural palm/finger geometry была жёстко встроена в `ArticulatedFirstPersonHandRig`.

S6 вводит отдельную границу:

`17-bone hand skeleton + pose logic -> HandVisualProvider -> concrete hand geometry`.

Цель: будущая authored/skinned hand visual implementation должна заменяться без переписывания:

- Item Graph;
- hotbar selection;
- item visual/grip catalogs;
- finger pose catalog;
- first-person two-hand coordination;
- third-person secondary-hand support;
- network authority.

## S6 implementation

Добавлены:

- `scripts/characters/presentation/first_person_hand_visual_provider.gd`;
- `scripts/characters/presentation/substitutable_first_person_hand_rig.gd`;
- `scripts/characters/lab/quaternius_first_person_embodiment_fix14.gd`;
- `tests/characters/fpe_s6_synthetic_hand_visual_provider.gd`;
- `tests/characters/test_fpe_r2_s6_hand_visual_provider_boundary.gd`.

`PosedCataloguedFirstPersonEmbodiment` теперь использует substitutable rig.

Default provider намеренно воспроизводит существующие 16 procedural visuals, поэтому S6 не должен визуально менять уже принятую S3/S4 работу.

Synthetic provider test доказывает, что другое visual implementation может быть установлено на тот же 17-bone skeleton, после чего pose transition продолжает работать.

Provider является presentation-only и не владеет item/network/gameplay transform state.

## S6 gates

Mandatory focused gate:

`FPE R2 S6 hand visual provider boundary: PASS`

Graphical scene теперь использует Fix14 и должна показывать:

`S6 hand visuals: L:PROCEDURAL_SEGMENTS | R:PROCEDURAL_SEGMENTS | substitutable:YES`

При `1 -> 2 -> empty` должны сохраниться уже принятые свойства:

- beacon pinch;
- mount-base two-hand first-person support;
- S5 third-person secondary support;
- empty slot clears held presentation;
- no return of blocking hotbar path or owner self-push.

## Current decision

`S5 ACCEPTED`

`S6 IMPLEMENTED — OPERATOR FOCUSED/GRAPHICAL RERUN PENDING`

Production-quality skinned hand mesh остаётся asset substitution после доказательства S6 provider boundary; отсутствие внешнего `Male_Peasant.gltf` не блокирует этот gate.
