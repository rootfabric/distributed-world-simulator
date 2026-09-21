# FABRIC R5.2 / T8 — Active Cooling Loop

**Статус:** implementation; first exact gate pending.

## Цель

T8 делает cooling отдельной собираемой подсистемой, а не готовым коэффициентом:

```text
64 parallel coolant lanes

each lane:
cold plate
hot coolant volume
radiator
cold coolant volume

= 256 detailed thermal states
        ↓ exact symmetric compile
4 caller-owned temperatures
```

Входной heat может приходить от T6 Power Stage. Mass flow — внешний hydraulic boundary, но его стоимость не бесплатна: dynamic viscosity + channel area/diameter/length дают pressure drop и hydraulic pump power.

Pump hydraulic energy учитывается как viscous heat в coolant и входит в общий energy audit.

## Physical floor

Generic Matter уже даёт density, heat capacity, thermal conductivity и phase temperatures. Coolant profile добавляет только отсутствующие свойства: dynamic viscosity, ambient-side heat-transfer coefficient и bounded laminar Reynolds limit. Profile привязан к canonical coolant Matter checksum.

## Thermal model

Compact state: plate temperature, hot coolant temperature, radiator temperature, cold coolant temperature.

```text
source heat
  ↓
plate --conductance--> hot coolant
                         |
                         | m_dot * Cp
                         ↓
                      cold coolant --conductance--> radiator --ambient G--> world
```

Hydraulic dissipation делится между hot/cold coolant nodes.

## Exact reduction

64 lanes обязаны иметь одинаковую geometry/material/quality derivation. Тогда каждая lane остаётся на одинаковой trajectory и 256 detailed state scalars точно редуцируются в 4.

Asymmetric lane остаётся физически исполняемой detailed model, но compiler возвращает COOLING_LANE_SYMMETRY_BROKEN: это NO_SAFE_BAKE, не invalid physics.

## T6 composition

Acceptance генерирует conduction + switching heat реальным merged T6 Power Stage и подаёт один и тот же heat trace в active loop с mass flow и zero-flow loop. Active loop обязан закончить с более низкой plate temperature, а pump hydraulic energy должна быть ненулевой и отдельно учтённой.

## Bounded claim

T8 использует laminar lumped-flow floor. Он не заявляет turbulence/CFD, cavitation, pump electrical efficiency, boiling/phase change, flexible hoses или fan aerodynamics. Эти fidelity layers можно добавить поверх стабильного thermal/hydraulic boundary.
