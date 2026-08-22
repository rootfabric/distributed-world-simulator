"""ECO.EVO4/E4.T0 - trophic payoff probe (sealed directions).

Derives a v0 defense proxy per bridge species from metabolic fields, then
verifies the DECLARED coevolution expectation over an herbivory pressure sweep:
at low pressure undefended payoff >= defended payoff (defense must cost),
at high pressure defended payoff > undefended (defense must pay off).
Presentation-side research only; no ecology truth claims. Pure stdlib.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
B2_PATH = ROOT / "validation/ecology/evo4_b2_development_state.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_t0_payoff_probe_result.v1.json"
SCHEMA = "distributed_world_simulator.ecology.evo4_t0_payoff_probe.v1"


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def main() -> int:
    data = json.loads(B2_PATH.read_text(encoding="utf-8"))
    species: dict[str, dict] = {}
    for record in data["records"]:
        gid = str(record["genome_id"])
        traits = record["effective_development_traits"]
        root_norm = _clamp(float(record.get("root_depth_proxy", 0.5)), 0.0, 1.0)
        shade = _clamp(float(traits["apical_dominance"]), 0.0, 1.0)
        # v0 defense proxy: declared derivation (documented honesty: not new genes)
        defense = round(_clamp(0.55 * shade + 0.45 * root_norm + 0.10 * (_unit(gid) - 0.5), 0.05, 0.95), 4)
        vigor = round(_clamp(float(traits["max_height_m"]) / 40.0 + 0.3, 0.3, 1.0), 4)
        species.setdefault(gid, {"defense": defense, "vigor": vigor})

    DEFENSE_COST = 0.35
    HERBIVORY_GAIN = 0.85
    probes = []
    for label, pressure, expect_defended_wins in [("LOW_PRESSURE", 0.15, False), ("HIGH_PRESSURE", 0.80, True)]:
        for gid, s in sorted(species.items()):
            undefended = s["vigor"] - HERBIVORY_GAIN * pressure
            defended = s["vigor"] - DEFENSE_COST * s["defense"] - HERBIVORY_GAIN * pressure * (1.0 - s["defense"])
            ok = (defended > undefended) if expect_defended_wins else (undefended >= defended - 1e-9)
            probes.append({
                "probe": label, "genome_id": gid,
                "defense": s["defense"], "payoff_undefended": round(undefended, 5),
                "payoff_defended": round(defended, 5), "verdict": "CONFIRMED" if ok else "FALSIFIED",
            })
    confirmed = sum(1 for p in probes if p["verdict"] == "CONFIRMED")
    digest = hashlib.sha256(json.dumps(probes, sort_keys=True).encode("utf-8")).hexdigest()
    result = {
        "schema": SCHEMA + ".result", "version": "1.0.0",
        "rule": "evo4-t0-defense-proxy-v0",
        "species_count": len(species), "probes": len(probes), "confirmed": confirmed,
        "sealed_directions_sha256": digest,
        "verdict": "PASS" if confirmed == len(probes) else "FAIL",
        "details": probes,
    }
    RESULT_PATH.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"EVO4_T0_PAYOFF_PROBE verdict={result['verdict']} confirmed={confirmed}/{len(probes)} digest={digest[:16]}")
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
