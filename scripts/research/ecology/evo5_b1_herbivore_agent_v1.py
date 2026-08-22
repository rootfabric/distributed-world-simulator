"""ECO.EVO5/B1 - Walking herbivore agent contract over the gene-level plot.

Agents: {position(x,y), hunger, appetite, mobility, preference}. Deterministic
sha256-keyed decisions. Each tick an agent moves toward its current target
(best w = nutrient_value - 0.8*toxicity within sense radius), bites when close
(target.browse_pressure += 1), retargets after each bite or on hunger>=1.
Pure research contract for the Godot plot lab; no population truth.
"""
from __future__ import annotations

import hashlib
import math

from evo5_genes_block_v1 import expressed  # noqa: F401  (contract surface parity)


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def make_agents(count: int, seed_base: str, plot_radius: float = 9.0) -> list[dict]:
    agents = []
    for i in range(count):
        angle = 2 * math.pi * _unit(f"{seed_base}|agent{i}|a")
        radius = plot_radius * math.sqrt(_unit(f"{seed_base}|agent{i}|r"))
        agents.append({
            "id": i,
            "position": [round(radius * math.cos(angle), 3), round(radius * math.sin(angle), 3)],
            "hunger": round(_unit(f"{seed_base}|agent{i}|h"), 3),
            "appetite": round(0.5 + 0.5 * _unit(f"{seed_base}|agent{i}|ap"), 3),
            "mobility": round(0.6 + 0.6 * _unit(f"{seed_base}|agent{i}|m"), 3),
            "target": None,
        })
    return agents


def _weight(plant: dict) -> float:
    genes = plant["genes"]
    return float(genes["nutrient_value"]) - 0.8 * float(genes["toxicity"]) + 0.05 if expressed(plant.get("defense_record", {}), plant.get("site", {})) else float(genes["nutrient_value"]) - 0.8 * float(genes["toxicity"])


def simulate_ticks(agents: list[dict], plants: list[dict], ticks: int, seed_base: str, step: float = 0.55):
    """plants: [{plant_id, position:[x,y], genes:{...}, defense_record, site, browse_pressure}]."""
    log = []
    for tick in range(ticks):
        for agent in agents:
            if agent["target"] is None or agent["target"] >= len(plants):
                candidates = [p for p in plants if math.dist(agent["position"], p["position"]) < 12.0] or plants
                best = max(candidates, key=_weight)
                agent["target"] = best["plant_id"]
            target = next(p for p in plants if p["plant_id"] == agent["target"])
            dx, dy = target["position"][0] - agent["position"][0], target["position"][1] - agent["position"][1]
            dist = math.hypot(dx, dy)
            speed = step * agent["mobility"] * (0.5 + agent["hunger"])
            if dist > 0.6:
                agent["position"][0] = round(agent["position"][0] + speed * dx / dist, 3)
                agent["position"][1] = round(agent["position"][1] + speed * dy / dist, 3)
                agent["hunger"] = round(min(1.0, agent["hunger"] + 0.01 * agent["appetite"]), 3)
            else:
                target["browse_pressure"] = round(target.get("browse_pressure", 0.0) + agent["appetite"], 3)
                agent["hunger"] = 0.0
                log.append({"tick": tick, "agent": agent["id"], "bite": target["plant_id"]})
                agent["target"] = None
    return {"agents": agents, "bites": log, "total_bites": len(log),
            "browse_by_plant": {p["plant_id"]: p.get("browse_pressure", 0.0) for p in plants}}
