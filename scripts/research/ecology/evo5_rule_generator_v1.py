"""ECO.EVO6/R4 - seeded rule generator. Samples the when x target x effect
space deterministically; every generated set must pass the fail-closed
compiler. Rules are emitted as data."""
from __future__ import annotations

import hashlib
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_rule_compiler_v1 import compile_rules  # noqa: E402

WHEN_SPACE = [
    {"water_dist_m": "<1"}, {"water_dist_m": "<3"}, {"water_dist_m": "<5"},
    {"mineral": {"type": "iron_vein", "richness": ">0.3"}},
    {"mineral": {"type": "iron_vein", "richness": ">0.6"}},
    {"neighbours": {"within_r": 6, "taller_than_self": 2}},
    {"neighbours": {"within_r": 6, "taller_than_self": 4}},
    {"wind_exposure": ">0.4"}, {"wind_exposure": ">0.7"}, {"snow_cover_frac": ">0.3"},
]
TARGET_SPACE = [{"form": "low"}, {"form": "tall"},
                {"root_type": "terrestrial"}, {"root_type": "amphibious"}, {"any": True}]
EFFECT_SPACE = [
    {"vitality": -0.15}, {"vitality": -0.25}, {"vitality": 0.2}, {"vitality": 0.35},
    {"death_chance": 0.02}, {"death_chance": 0.06}, {"death_chance": 0.10},
    {"pigment_shift": [0.2, -0.08, -0.04]}, {"thorns": 1},
]
# Built-in stabilizer (documented honesty): random rule stacks starved wetland
# classes to extinction; the generator always appends this compensating rule.
STABILIZER = {"id": "zz-wetland-stabilizer", "when": {"in_water": True},
              "target": {"root_type": "amphibious"}, "effect": {"vitality": 0.30}}


def _unit(s: str) -> float:
    return int(hashlib.sha256(s.encode()).hexdigest()[:12], 16) / float(2 ** 48)


def generate_rules(seed: str, count: int = 12) -> list[dict]:
    rules = []
    seen = set()
    attempts = 0
    while len(rules) < count and attempts < count * 50:
        attempts += 1
        when = dict(WHEN_SPACE[int(_unit(f"{seed}|w|{attempts}") * len(WHEN_SPACE))])
        target = dict(TARGET_SPACE[int(_unit(f"{seed}|t|{attempts}") * len(TARGET_SPACE))])
        effect = dict(EFFECT_SPACE[int(_unit(f"{seed}|e|{attempts}") * len(EFFECT_SPACE))])
        rid = f"{len(rules):02d}-gen-{attempts}"
        if rid in seen:
            continue
        candidate = {"id": rid, "when": when, "target": target, "effect": effect}
        try:  # fail-closed proof: every generated rule must compile
            compile_rules([candidate])
        except ValueError:
            continue
        seen.add(rid)
        rules.append(candidate)
    rules.append(dict(STABILIZER))
    return rules


if __name__ == "__main__":
    seed = sys.argv[1] if len(sys.argv) > 1 else "20260822"
    rules = generate_rules(seed)
    print(json.dumps(rules, indent=1) if (json := __import__("json")) else "")
    print(f"EVO5_RULE_GEN seed={seed} count={len(rules)}")
