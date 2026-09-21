# FABRIC R5.2 / T8 — Active Cooling Loop

**Статус:** Repair R2 authoritative exact 3/3 PASS; exact-head closure/review/verifier pending.

## Результат

```text
subject = b5c8078edb66901be8d8c235a11bce53df44e894
tree    = 68b0e716c6885a5d1c75a5dfc3e763fd503fc104
run     = 35659249681
samples = 3/3 PASS
assertions/sample = 4145

deterministic hash =
eba45c45ef855367ee0c99a730fcea48ad5df172e5db21e5ecb67c942a82ae29

evidence hash =
55c468a1e3f2b78dd8746b818368f6a6fdc909561b19877753c3c0ff8f335a78

aggregate artifact = 10667390015
digest = sha256:10d65ffdb0c667411a6930266c100ad08476868582f1cb611ad87f4e61ac07c5
```

64 одинаковых coolant lanes содержат plate/hot-coolant/radiator/cold-coolant узлы: 256 detailed thermal states компилируются в 4 caller-owned температуры.

```text
1536 source operations
→ 32 compiled operations
compression = 48x
runtime source traversals/execute = 0
```

Detailed reference за 2048 шагов делает 524,288 thermal-node traversals. Максимальная температурная ошибка ≈5.12e-13 K, state error = 0, energy residual ≈8.31e-11 J.

## Hydraulic floor

Mass flow — boundary input, но hydraulic cost не бесплатен. Dynamic viscosity плюс channel geometry выводят pressure drop и hydraulic power; эта энергия возвращается как viscous heat и входит в energy audit. Laminar descriptor ограничен Re ≤ 2300.

Water-like → glycol-like profile при той же geometry даёт pump-energy ratio ≈3.227.

## T6 composition

Реальный T6 Power Stage генерирует conduction + switching heat. За composition sequence:

```text
T6 heat = 4751.015 J
T8 hydraulic pump energy = 7.154 J
active-flow plate advantage vs zero-flow = 3.398 K
```

## Repairs

R0 исправил ошибку tree lineage: T8 заново наложен только поверх точного T7 merge tree. Финальный PR снова additive, deletions=0.

R1 убрал повторную статическую derivation Matter/geometry из каждого detailed tick. FullReference.prepare выводит коэффициенты всех 64 lanes один раз, но каждый execute по-прежнему обновляет все 256 detailed thermal states. Acceptance и source-traversal semantics не ослаблены.

R2 закрыл state/projector trust boundary: NaN и finite out-of-domain state отвергаются отдельно в projector и reference. Rehashed descriptor также не может поднять laminar limit выше 2300 или нарушить relation max-flow.

Asymmetric lane остаётся физически исполняемой detailed model, но compact compiler возвращает COOLING_LANE_SYMMETRY_BROKEN — это NO_SAFE_BAKE, а не invalid physics.

## Ограничения

T8 — laminar lumped-flow floor. CFD/turbulence, cavitation, boiling/phase change, pump electrical efficiency, flexible-hose dynamics и fan aerodynamics не заявляются и остаются последующими fidelity layers.
