# FABRIC R5.2 / T3 — Battery from Cells + Materials

## Цель

T3 — первый полноценный functional assembly:

```text
Matter materials
      ↓ characterized electrochemical profile
cell geometry + manufacturing quality
      ↓
96 real cell components (12S8P)
      ↓ compile
12 series-group states + common temperature
      ↓
Battery BehaviorCapsule
```

Battery не получает готовые gameplay stats. Capacity/resistance/current/mass/thermal behavior выводятся из materials + geometry + quality.

## Simulation floor

T3 намеренно не моделирует атомы/электрохимию ab initio. Используется characterized electrochemical profile, привязанный к canonical Matter material checksum:

- voltage window;
- specific charge capacity;
- effective electronic conductivity;
- contact resistivity;
- maximum current density;
- resistance temperature coefficient;
- safe temperature domain.

Это versioned physical primitive, а не rarity bonus.

## Cell derivation

```text
active mass = material density × active volume

capacity =
  active mass
  × specific_capacity
  × quality

base resistance =
  path_length / (conductivity × electrode_area)
  + contact_resistivity / electrode_area

cell resistance =
  base resistance / quality

max current =
  current_density_limit
  × electrode_area
  × quality

thermal capacity =
  active mass × active-material Cp
  + case mass × case-material Cp

passive thermal conductance =
  case k × surface_area / wall_thickness
```

Manufacturing quality changes utilization/contact/current capability, but does not invent or remove mass.

## Why 12 state charges, not one magic SOC

Each parallel group can aggregate to one charge state if all enabled cells share the same chemistry and have compatible conductance/capacity scaling.

```text
8 parallel cells → one group charge
×
12 series groups
=
12 charge states
+ 1 pack temperature
```

This lets one damaged/disabled cell change only its affected series group while remaining far cheaper than 96 per-cell states.

Compiler refuses unsafe reduction when:

- mixed electrochemical profiles occur inside one parallel group;
- geometry makes conductance/capacity ratios incompatible;
- a complete series group is electrically open.

## Runtime

Prepared capsule stores only group aggregates:

- capacity;
- equivalent resistance;
- OCV voltage window;
- current limit;
- temperature coefficient.

Each execute receives caller-owned state and returns next state. Capsule does not own persistent canonical charge.

Energy audit uses midpoint OCV for the linear voltage curve so:

```text
chemical energy decrease
=
electrical energy delivered
+
resistive heat
```

within floating-point tolerance.

## Material / quality / damage tests

T3 compares:

1. LFP-like characterized active material;
2. NMC-like characterized active material;
3. same pack with lower manufacturing quality;
4. same pack with one electrically-disabled cell.

Expected derived consequences:

- chemistry changes voltage and specific energy;
- lower quality lowers capacity/current and increases resistance, without changing mass;
- disabled cell lowers affected group capacity/current and raises resistance; old capsule becomes invalid.

## Non-claims

T3 does not yet claim:

- atom-level electrochemistry;
- dynamic SOH/cycle aging;
- cell thermal gradients;
- active pump/radiator cooling;
- arbitrary mixed-chemistry parallel aggregation;
- runaway/venting chemistry.

Those are downstream fidelity layers. T3 proves component/material/quality → compact stateful battery behavior.
