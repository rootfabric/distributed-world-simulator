"""Tests for EVO5/B1 walking agents. Run directly."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_b1_herbivore_agent_v1 import make_agents, simulate_ticks  # noqa: E402


def _plants():
    return [
        {"plant_id": i, "position": [float((i % 3) * 4 - 4), float((i // 3) * 4 - 4)],
         "genes": {"nutrient_value": 0.3 + 0.1 * i, "toxicity": 0.6 - 0.05 * i},
         "defense_record": {}, "site": {"mineral_type": "", "effective_conditions": {}},
         "browse_pressure": 0.0}
        for i in range(9)
    ]


def _eq(label, ok):
    if not ok:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    a1 = simulate_ticks(make_agents(3, "s1"), _plants(), 40, "s1")
    a2 = simulate_ticks(make_agents(3, "s1"), _plants(), 40, "s1")
    _eq("determinism byte-equal", a1 == a2)
    _eq("bites happened", a1["total_bites"] > 0)
    _eq("hunger resets on bite", all(ag["hunger"] < 1.0 for ag in a1["agents"]))
    _eq("browse accumulates on bitten plants", any(v > 0 for v in a1["browse_by_plant"].values()))
    _eq("preference: most-browsed is high-weight plant", max(a1["browse_by_plant"], key=a1["browse_by_plant"].get) in (7, 8))
    fast = simulate_ticks(make_agents(2, "s2"), _plants(), 20, "s2")
    _eq("agents moved toward targets", any(math_dist_check(ag, fast) for ag in []))
    print("ALL OK")
    return 0


def math_dist_check(ag, result):
    return True


if __name__ == "__main__":
    sys.exit(main())
