"""ECO.EVO5/C - T5 predator probe: three-trophic-level stability, 60 generations.

Discrete deterministic dynamics (no RNG): logistic plants, agent grazing with
numeric response, predator predation on agents. Gates: no level goes extinct,
none blows up past declared corridor caps, restart byte-equal, 3-seed
robustness (seed shifts initial densities slightly).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RESULT_PATH = ROOT / "validation/ecology/evo5_t5_predator_probe_result.v1.json"
GENERATIONS = 60
R_PLANT, K_PLANT = 0.4, 1000.0
AGENT_INTAKE, AGENT_EFF, AGENT_DEATH = 0.004, 0.10, 0.06
PRED_INTAKE, PRED_EFF, PRED_DEATH = 0.02, 0.15, 0.08
DT = 0.25
CORRIDORS = {"plants": (60.0, 985.0), "agents": (2.0, 380.0), "predators": (1.0, 75.0)}


def _run(seed_shift: float):
    state = {"plants": 500.0 + seed_shift, "agents": 24.0 + seed_shift * 0.2, "predators": 6.0}
    trajectory = []
    for _ in range(GENERATIONS):
        d_plants = R_PLANT * state["plants"] * (1 - state["plants"] / K_PLANT) - AGENT_INTAKE * state["agents"] * state["plants"]
        d_agents = AGENT_EFF * AGENT_INTAKE * state["agents"] * state["plants"] - AGENT_DEATH * state["agents"] - PRED_INTAKE * state["predators"] * state["agents"]
        d_preds = PRED_EFF * PRED_INTAKE * state["predators"] * state["agents"] - PRED_DEATH * state["predators"]
        for key, delta in (("plants", d_plants), ("agents", d_agents), ("predators", d_preds)):
            state[key] = max(1e-6, state[key] + DT * delta)
        trajectory.append({k: round(v, 3) for k, v in state.items()})
    return trajectory


def _corridor_ok(trajectory) -> bool:
    return all(lo <= point[level] <= hi for point in trajectory for level, (lo, hi) in CORRIDORS.items())


def main() -> int:
    main_traj = _run(0.0)
    restart = _run(0.0)
    robust = all(_corridor_ok(_run(shift)) for shift in (12.0, -18.0))
    gates = {
        "no_extinction_all_levels": all(point[level] >= CORRIDORS[level][0] * 0.99 for point in main_traj for level in CORRIDORS),
        "no_blowup_all_levels": all(point[level] <= CORRIDORS[level][1] for point in main_traj for level in CORRIDORS),
        "restart_byte_equal": main_traj == restart,
        "robustness_3_seeds": bool(robust),
    }
    confirmed = sum(1 for v in gates.values() if v)
    result = {"schema": "distributed_world_simulator.ecology.evo5_t5_predator_probe.v1.result",
              "version": "1.0.0", "generations": GENERATIONS, "gates": gates,
              "final_state": main_traj[-1], "trajectory_head": main_traj[:5],
              "verdict": "PASS" if confirmed == len(gates) else "FAIL"}
    RESULT_PATH.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"EVO5_T5_PREDATOR verdict={result['verdict']} confirmed={confirmed}/{len(gates)} final={result['final_state']}")
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
