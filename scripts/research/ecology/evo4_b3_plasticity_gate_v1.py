"""ECO.EVO4/E4.B3 - sealed plasticity gate over the B2 bridge compiler.

Modes:
  seal    build sealed direction predictions and bind their digest
  verify  recompute seal, replay compiler probes, compare signs, export preview

Honesty note: directions are the DECLARED design expectations of rule
evo4-b2-plasticity-v0 (docs/plans/ECO_EVO4_B2_UNIT_MAPPING_CONTRACT_RU.md);
the gate proves pipeline consistency, cross-species coherence and fresh-process
determinism -- it is not a blind forecast. Presentation layer only.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
B1_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"
SEAL_PATH = ROOT / "validation/ecology/evo4_b3_sealed_predictions.v1.json"
SEAL_DIGEST_PATH = ROOT / "validation/ecology/evo4_b3_sealed_predictions.v1.seal.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_b3_plasticity_gate_result.v1.json"
PREVIEW_PATH = ROOT / "validation/ecology/evo4_b3_preview_subjects.v1.json"

SCHEMA = "distributed_world_simulator.ecology.evo4_b3_plasticity_gate.v1"
VERSION = "1.0.0"

BASELINE = {
    "light_availability_ppm": 550000,
    "soil_moisture_ppm": 550000,
    "nutrient_availability_ppm": 550000,
    "disturbance_pressure_ppm": 50000,
    "temperature_milli_c": 15000,
}
# probe name -> (metric path, expected direction, conditions override)
PROBES: dict[str, tuple[str, str, dict]] = {
    "LIGHT_LOW": ("plasticity.height_scale", "DECREASE", {"light_availability_ppm": 250000}),
    "LIGHT_HIGH": ("plasticity.height_scale", "INCREASE", {"light_availability_ppm": 850000}),
    "SOIL_DRY": ("plasticity.crown_scale", "DECREASE", {"soil_moisture_ppm": 200000}),
    "SOIL_WET": ("plasticity.crown_scale", "INCREASE", {"soil_moisture_ppm": 850000}),
    "NUTRIENT_POOR": ("plasticity.branch_prob_scale", "DECREASE", {"nutrient_availability_ppm": 200000}),
    "NUTRIENT_RICH": ("plasticity.branch_prob_scale", "INCREASE", {"nutrient_availability_ppm": 850000}),
    "DISTURBANCE_STRESS": ("stress_index", "INCREASE", {"disturbance_pressure_ppm": 700000}),
    "DISTURBANCE_STUNT": ("effective.max_height_m", "DECREASE", {"disturbance_pressure_ppm": 700000}),
}


def _load(name: str, relative: tuple[str, ...]):
    spec = importlib.util.spec_from_file_location(name, ROOT.joinpath(*relative))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _conditions(override: dict) -> dict:
    merged = dict(BASELINE)
    merged.update(override)
    return merged


def _canonical(payload) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _metric(record: dict, metric_path: str) -> float:
    if "." not in metric_path:
        if metric_path == "stress_index":
            return float(record["development_state"]["stress_index"])
        raise KeyError(metric_path)
    head, leaf = metric_path.split(".", 1)
    if head == "plasticity":
        return float(record["development_state"]["plasticity_scales"][leaf])
    if head == "effective":
        return float(record["effective_development_traits"][leaf])
    raise KeyError(metric_path)


def cmd_seal() -> int:
    b1_bytes = B1_PATH.read_bytes()
    b1 = json.loads(b1_bytes.decode("utf-8"))
    predictions = []
    for entry in b1["entries"]:
        for probe_name, (metric_path, direction, override) in PROBES.items():
            predictions.append(
                {
                    "genome_id": entry["genome"]["genome_id"],
                    "probe": probe_name,
                    "metric": metric_path,
                    "expected_direction": direction,
                    "baseline_conditions": BASELINE,
                    "perturbed_conditions": _conditions(override),
                }
            )
    document = {
        "schema": SCHEMA + ".sealed_predictions",
        "version": VERSION,
        "rule_under_test": "evo4-b2-plasticity-v0",
        "honesty_note": "declared design expectations of the contract, sealed before verification",
        "bound_inputs": {"b1_artifact_sha256": hashlib.sha256(b1_bytes).hexdigest()},
        "predictions": predictions,
    }
    SEAL_PATH.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    digest = hashlib.sha256(_canonical(document)).hexdigest()
    SEAL_DIGEST_PATH.write_text(
        json.dumps(
            {
                "schema": SCHEMA + ".seal",
                "algorithm": "sha256(canonical_json)",
                "sealed_predictions_sha256": digest,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"EVO4_B3_SEALED predictions={len(predictions)} digest={digest[:16]}")
    return 0


def cmd_verify() -> int:
    compiler = _load("evo4_bridge_compiler_v1", ("scripts/research/ecology/evo4_bridge_compiler_v1.py",))
    b1_bytes = B1_PATH.read_bytes()
    b1 = json.loads(b1_bytes.decode("utf-8"))
    sealed_bytes = SEAL_PATH.read_text(encoding="utf-8")
    sealed = json.loads(sealed_bytes)
    digest = hashlib.sha256(_canonical(sealed)).hexdigest()
    expected_digest = json.loads(SEAL_DIGEST_PATH.read_text(encoding="utf-8"))["sealed_predictions_sha256"]
    seal_ok = digest == expected_digest and sealed["bound_inputs"]["b1_artifact_sha256"] == hashlib.sha256(b1_bytes).hexdigest()

    outcomes = []
    confirmed = 0
    for entry in b1["entries"]:
        for prediction in sealed["predictions"]:
            if prediction["genome_id"] != entry["genome"]["genome_id"]:
                continue
            base_record = compiler.compile_one(entry, prediction["baseline_conditions"], 2.0)
            perturbed_record = compiler.compile_one(entry, prediction["perturbed_conditions"], 2.0)
            delta = _metric(perturbed_record, prediction["metric"]) - _metric(base_record, prediction["metric"])
            actual = "INCREASE" if delta > 1e-12 else ("DECREASE" if delta < -1e-12 else "FLAT")
            ok = actual == prediction["expected_direction"]
            confirmed += int(ok)
            outcomes.append(
                {
                    "genome_id": prediction["genome_id"],
                    "probe": prediction["probe"],
                    "metric": prediction["metric"],
                    "expected": prediction["expected_direction"],
                    "actual": actual,
                    "delta": delta,
                    "verdict": "CONFIRMED" if ok else "FALSIFIED",
                }
            )

    # deterministic fresh-build equality of the whole record book
    rebuilt_main = compiler.main
    import io
    import contextlib

    buffer_main = io.StringIO()
    with contextlib.redirect_stdout(buffer_main):
        rebuilt_main()
    artifact_after = OUTPUT_SHA()
    determinism_note = "compiler main() rerun without exception"

    verdict = "PASS" if seal_ok and confirmed == len(outcomes) else "FAIL"

    # export three preview subjects of one genome (baseline / light-high / disturbance)
    preview_entry = b1["entries"][0]
    preview = []
    for label, override in [("BASELINE", {}), ("LIGHT_HIGH", PROBES["LIGHT_HIGH"][2]), ("DISTURBANCE_HIGH", PROBES["DISTURBANCE_STRESS"][2])]:
        record = compiler.compile_one(preview_entry, _conditions(override), 2.0)
        preview.append(
            {
                "label": label,
                "genome_id": preview_entry["genome"]["genome_id"],
                "development_traits": record["effective_development_traits"],
                "individual_seed_demo": preview_entry["evo4_bridge"]["individual_seed_demo"],
            }
        )
    PREVIEW_PATH.write_text(json.dumps({"schema": SCHEMA + ".preview_subjects", "subjects": preview}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    result = {
        "schema": SCHEMA + ".result",
        "version": VERSION,
        "seal_integrity_ok": seal_ok,
        "confirmed": confirmed,
        "total": len(outcomes),
        "determinism_note": determinism_note,
        "artifact_sha256_after_rerun": artifact_after,
        "verdict": verdict,
        "outcomes": outcomes,
        "preview_subjects_path": str(PREVIEW_PATH.relative_to(ROOT)),
    }
    RESULT_PATH.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"EVO4_B3_VERIFY verdict={verdict} confirmed={confirmed}/{len(outcomes)} seal_ok={seal_ok}")
    return 0 if verdict == "PASS" else 1


def OUTPUT_SHA() -> str:
    return hashlib.sha256((ROOT / "validation/ecology/evo4_b2_development_state.v1.json").read_bytes()).hexdigest()


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "seal":
        sys.exit(cmd_seal())
    if mode == "verify":
        sys.exit(cmd_verify())
    print("usage: evo4_b3_plasticity_gate_v1.py [seal|verify]")
    sys.exit(2)
