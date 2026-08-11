# ECO.P1C-S1 — Unlabeled Founder Pool and Shared-Field Competition Baseline — ACCEPTED

## Решение

`ACCEPTED` по exact-Windows evidence на Godot `4.7.1.stable.double.custom_build.a13da4feb`.

- focused: `116/116`;
- fresh-process replay: `5/5`;
- result: `cf3bd5f417c9a49dd1c5eac0d93ea736b02ec0be25afd4945b1424a8dbde3928`;
- uniform: `1c5128666314dfeec9ed09094931be58e76253f92bf9da50379a91eeb3b68a58`;
- alternate: `bded62e12ade0285c019d0dc2e4f77d0d6cb88431df7ade605160e0f18d82f8c`;
- founder pool: `77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38`.

## Что доказано

20 детерминированных unlabeled ancestral genomes конкурируют через принятую P1A resource/biomass/recruitment truth без species/biome ролей. На heterogeneous field сохраняются 15/20 founders и 5 разных top-1 winners, тогда как uniform control повторяет один и тот же retained set и одного top winner на всех patches.

Высокий static top-1 pressure `0.8367` не скрывается: S1 — baseline ранжирования, а не окончательное доказательство динамического coexistence. Это давление передано в P1C-S2.

## Следующий шаг

`ECO.P1C-S2 Dynamic Shared-Patch Abundance Competition`: заменить статический top-N snapshot на детерминированную динамику biomass shares во времени при том же founder pool и той же принятой P1A plant simulation truth.
