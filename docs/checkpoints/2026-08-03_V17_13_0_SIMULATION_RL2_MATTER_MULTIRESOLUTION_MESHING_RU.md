# v17.13.0 — RL2 Matter Multiresolution Meshing and Cross-level Transitions

```text
checkpoint: v17.13.0-simulation-rl2-matter-multiresolution-meshing
build_id:   rl2-matter-multiresolution-meshing-transitions
base:       v17.12.0-simulation-mw10-cross-region-matter-transactions (ACCEPTED)
branch:     feature/rl2-matter-multiresolution-meshing
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- exact RL1 summary + leaf snapshot source sets;
- deterministic 1/8/64 snapshot topology для LOD0/LOD1/LOD2;
- fixed-resolution coarse SDF fields над увеличивающимися octree scopes;
- Freudenthal marching-tetrahedra meshes;
- content-addressed DETAIL, SIMPLIFIED_MESH и MACRO_PROXY artifacts;
- same-level boundary segment verification;
- deterministic `FINE_BOUNDARY_SKIRT_V1` cross-level artifacts;
- maximum neighbor LOD delta 1 и deterministic balancing;
- exact invalidation projection на affected scopes;
- Godot ArrayMesh/collision/presenter factory вне canonical contracts;
- synthetic nonlinear fixture и реальный fixed-seed asteroid fixture.

## Focused topology

```text
contracts/synthetic: 153 assertions
real asteroid:        44 assertions
combined:            197 assertions
```

## Обязательная независимая матрица

```text
RL2 runner:       197/197 PASS
MW10 regression: 235/235 PASS
MW9 regression:  240/240 PASS
RL1 regression:  245/245 PASS
RL0 regression:   92/92 PASS
MW8 regression:   98/98 PASS
MW7 regression:  114/114 PASS
git diff --check: PASS
```

Известные ObjectDB/resource warnings старого MW7 runner после успешного маркера остаются неблокирующими и не относятся к RL2.

## Не входит в checkpoint

- RL3 network artifact streaming;
- RL5 cache/scheduler;
- Transvoxel;
- Construction HLOD;
- production Moon/world changes.

## Следующий этап

```text
RL3 — Representation-aware Network Streaming
```
