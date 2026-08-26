from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))

from evo5_rule_compiler_v1 import apply_rules, compile_rules  # noqa: E402
from evo6_water_fitness_v1 import evaluate, water_availability  # noqa: E402


def check(condition: bool, label: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    document = json.loads((ROOT / "config/ecology/research/evo6_water_rules.v1.json").read_text(encoding="utf-8"))
    rules = compile_rules(document["rules"])
    terrestrial = {"root_type": "terrestrial", "form": "low"}
    amphibious = {"root_type": "amphibious", "form": "low"}

    flooded = {"features": {"in_water": True, "water_dist_m": 0.0}, "effective_conditions": {"soil_moisture_ppm": 1_000_000}}
    riparian = {"features": {"water_dist_m": 1.5}, "effective_conditions": {"soil_moisture_ppm": 650_000}}
    saturated = {"features": {"water_dist_m": 0.5}, "effective_conditions": {"soil_moisture_ppm": 850_000}}
    dry = {"features": {"water_dist_m": 20.0}, "effective_conditions": {"soil_moisture_ppm": 180_000}}
    mesic = {"features": {"water_dist_m": 8.0}, "effective_conditions": {"soil_moisture_ppm": 400_000}}

    t_flood = apply_rules(rules, flooded, terrestrial)
    a_flood = apply_rules(rules, flooded, amphibious)
    check(t_flood["vitality"] <= -1.2 and t_flood["death_chance"] >= 0.18, "flood strongly rejects terrestrial plants")
    check(a_flood["vitality"] >= 1.0 and a_flood["seed_establishment"] >= 1.0, "flood strongly rewards amphibious plants")

    t_sat = apply_rules(rules, saturated, terrestrial)
    check(t_sat["vitality"] <= -0.7 and t_sat["seed_establishment"] <= -0.8, "saturated soil strongly stresses terrestrial plants")

    a_river = apply_rules(rules, riparian, amphibious)
    check(a_river["vitality"] >= 0.7 and a_river["seed_establishment"] >= 0.8, "riparian zone strongly rewards amphibious plants")

    a_dry = apply_rules(rules, dry, amphibious)
    t_dry = apply_rules(rules, dry, terrestrial)
    check(a_dry["vitality"] <= -1.0 and a_dry["death_chance"] >= 0.12, "drought strongly rejects amphibious plants")
    check(t_dry["vitality"] <= -0.25 and t_dry["seed_establishment"] <= -0.35, "drought is harsh for all plants")

    # Explicit comparator regression: '<' on effective conditions must not act like '>='.
    check(apply_rules(rules, mesic, amphibious)["death_chance"] == 0.0, "dry rule does not fire in mesic soil")

    wet_genome = {"water_preference": 0.85, "water_tolerance_width": 0.30, "root_depth_m": 0.85}
    dry_genome = {"water_preference": 0.20, "water_tolerance_width": 0.30, "root_depth_m": 2.5}
    shallow_dry = {"water_preference": 0.20, "water_tolerance_width": 0.30, "root_depth_m": 0.45}

    check(water_availability(flooded) == 1.0, "submerged water availability is 1")
    check(water_availability(riparian) > water_availability(mesic) > water_availability(dry), "water availability orders riparian > mesic > dry")
    check(evaluate(wet_genome, flooded)["fitness"] > evaluate(dry_genome, flooded)["fitness"] * 4.0, "wet genotype dominates under flood")
    check(evaluate(dry_genome, dry)["fitness"] > evaluate(wet_genome, dry)["fitness"] * 2.0, "dry genotype dominates under drought")
    check(evaluate(dry_genome, dry)["fitness"] > evaluate(shallow_dry, dry)["fitness"] * 1.5, "deep roots strongly help under drought")

    print("ECO.EVO6-WATER Python acceptance: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
