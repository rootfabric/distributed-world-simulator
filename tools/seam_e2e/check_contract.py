#!/usr/bin/env python3
"""Validate the SEAM-E2E *specification*, never runtime acceptance.

A successful exit establishes SPEC_CONTRACT_PASS only. Real multiservers,
graphics, inter-player canonical effects, faults and evidence are separate.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "config/testing/seam-e2e-r1-acceptance.v1.json"
GATES = {
    "S01_PHYSICAL_MULTISERVER_TOPOLOGY",
    "S02_SINGLE_CLIENT_WORLD_CONNECTION",
    "S03_A_B_C_B_A_AUTHORITY_CHAIN",
    "S04_SIMULTANEOUS_CROSS_BORDER_CO_PRESENCE",
    "S05_CROSS_OWNER_ITEM_EXCHANGE",
    "S06_CROSS_OWNER_CONSTRUCTION",
    "S07_CROSS_OWNER_MINING_AND_TERRAIN",
    "S08_CROSS_OWNER_PHYSICAL_INTERACTION",
    "S09_VISUAL_CAMERA_GEOMETRY_CONTINUITY",
    "S10_OWNERSHIP_FENCING_AND_EXACTLY_ONCE",
    "S11_SERVER_GATEWAY_CRASH_RECOVERY",
    "S12_WAN_PARTITION_AND_FAIRNESS",
    "S13_NORMATIVE_E2E_PERFORMANCE",
    "S14_THIRTY_MINUTE_MIXED_SOAK",
    "S15_CONTROL_FRESH_INDEPENDENT_REVIEW",
}
CROSS_OWNER = GATES - {
    "S01_PHYSICAL_MULTISERVER_TOPOLOGY",
    "S02_SINGLE_CLIENT_WORLD_CONNECTION",
    "S03_A_B_C_B_A_AUTHORITY_CHAIN",
    "S15_CONTROL_FRESH_INDEPENDENT_REVIEW",
}
MIN_TOPOLOGY = {
    "min_authority_processes": 3,
    "min_distinct_authority_ids": 3,
    "min_gateway_processes": 1,
    "min_graphical_game_clients": 2,
    "min_distinct_os_processes": 6,
    "min_distinct_physical_or_independent_vm_hosts": 2,
}
MIN_COVERAGE = {
    "min_crossings_per_directed_edge": 10,
    "min_distinct_player_owners_during_co_presence": 2,
    "min_distinct_players_interacting_across_authority_boundary": 2,
    "min_matched_windows_gui_runs": 3,
    "min_measured_seconds_per_gui_run": 108,
    "target_measured_seconds_per_gui_run": 120,
    "minimum_soak_seconds": 1800,
    "min_crash_fault_stage_types": 5,
    "min_negative_falsifiers": 8,
}
MAX_QUALITY = {
    "client_frame_p99_ms_max": 25,
    "client_frame_p999_ms_max": 50,
    "client_max_frame_gap_ms": 100,
    "seam_unexplained_input_blackout_ms_max": 100,
    "seam_unexplained_avatar_blackout_ms_max": 100,
    "seam_position_correction_m_max": 0.25,
    "seam_camera_angular_discontinuity_deg_max": 3,
    "lan_cross_owner_visibility_latency_p99_ms_max": 250,
}
ZERO = {
    "split_brain_canonical_write_count_max",
    "duplicate_canonical_effect_count_max",
    "lost_committed_operation_count_max",
    "early_ack_count_max",
    "phantom_or_missing_seam_tile_count_max",
    "conflicting_cross_server_collision_count_max",
}
MUST_INVARIANTS = {
    "ONE_CANONICAL_WRITER_PER_DOMAIN",
    "FENCED_OLD_WRITER_CANNOT_MUTATE",
    "ONE_CANONICAL_ITEM_GRAPH",
    "ONE_CANONICAL_CONSTRUCTION_TRUTH",
    "NO_DOUBLE_RESOURCE_OR_TERRAIN_TRUTH",
    "NO_GATEWAY_AUTHORITY_OR_GAMEPLAY_TRUTH",
    "STABLE_PLAYER_ENTITY_AND_ITEM_IDS",
    "STABLE_OPERATION_ID_AND_IDEMPOTENT_REPLAY",
    "DURABLE_BEFORE_ACK",
    "SHARED_CANONICAL_PHYSICS_AND_COLLISION_OUTCOMES",
    "PROJECTION_READ_ONLY_AOI_FENCED",
}
MUST_SUBSTITUTIONS = {
    "R31_INTERNAL_SEAM_AS_PHYSICAL_SERVER_HANDOFF",
    "TWO_AUTHORITY_SM1_LAB_AS_FULL_N_SERVER_ACCEPTANCE",
    "TWO_UNRELATED_SCENARIOS_AS_SINGLE_LIVE_WORLD_INTERACTION",
    "FAKE_ITEM_GRAPH_OR_TEST_ONLY_HANDOFF_PROTOCOL",
    "HEADLESS_ONLY_AS_GRAPHICAL_PRODUCT_ACCEPTANCE",
}
MUST_TOPOLOGY = {
    "remote_non_loopback_gateway_authority_path_required",
    "real_clients_must_use_earth_and_quaternius",
    "stable_world_id_required",
    "direct_client_simulation_server_transport_forbidden",
    "full_acceptance_on_one_host_forbidden",
    "full_acceptance_with_internal_primary_secondary_only_forbidden",
}
MUST_RELEASE = {
    "mandatory_all_gates_pass",
    "exact_product_head_tree_and_build_hash",
    "evidence_sha256_and_raw_traces",
    "project_control_non_red",
    "independent_reviewer_pass",
    "independent_verifier_pass",
    "human_merge_and_release_gate",
    "no_metric_waivers",
    "no_soak_before_exact_and_functional_green",
    "no_automatic_merge",
}
class ContractError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise ContractError(message)

def check_min(mapping, key, limit):
    val = mapping.get(key)
    require(type(val) in (int, float) and val >= limit,
            "requires %s >= %s" % (key, limit))

def check_max(mapping, key, limit):
    val = mapping.get(key)
    require(type(val) in (int, float) and 0 <= val <= limit,
            "requires %s <= %s" % (key, limit))

def validate_spec(doc):
    require(isinstance(doc, dict), "contract must be a JSON object")
    require(doc.get("schema") == "dws.seam_e2e.acceptance_contract.v1", "schema mismatch")
    require(doc.get("id") == "SEAM-E2E-R1", "id mismatch")
    require(doc.get("status") == "PROPOSED_CONTRACT_NOT_ACTIVATED",
            "a specification cannot declare a runtime acceptance PASS")
    for key in ("product_release_must_not_be_claimed_from_this_spec_alone",
                "same_live_topology_for_all_product_scenarios",
                "component_lab_evidence_only_as_regression"):
        require(doc.get(key) is True, "contract must keep %s" % key)
    topo = doc.get("topology", {})
    require(isinstance(topo, dict), "missing topology")
    for key, limit in MIN_TOPOLOGY.items():
        check_min(topo, key, limit)
    for key in MUST_TOPOLOGY:
        require(topo.get(key) is True, "missing topology invariant: %s" % key)
    require(topo.get("client_world_transports_during_normal_handoff_exact") == 1,
            "client must retain one gateway world transport")
    require(topo.get("max_canonical_writers_per_authority_domain") == 1,
            "exactly one writer per authority domain")
    for key in ("gateway_canonical_gameplay_writes_max",
                "warm_authority_canonical_writes_max"):
        check_max(topo, key, 0)
    coverage = doc.get("minimum_coverage", {})
    require(isinstance(coverage, dict), "missing coverage")
    for key, limit in MIN_COVERAGE.items():
        check_min(coverage, key, limit)
    require(coverage.get("directed_chain") == ["A->B", "B->C", "C->B", "B->A"],
            "three-authority bidirectional chain required")
    quality = doc.get("quality_targets", {})
    require(isinstance(quality, dict), "missing quality targets")
    for key, limit in MAX_QUALITY.items():
        check_max(quality, key, limit)
    for key in ZERO:
        check_max(quality, key, 0)
    check_min(quality, "authority_process_loop_hz_min", 59)
    require(quality.get("canonical_simulation_hz") == 20, "simulation rate changed")
    require(MUST_INVARIANTS <= set(doc.get("hard_invariants", [])),
            "missing one or more canonical world invariants")
    require(MUST_SUBSTITUTIONS <= set(doc.get("forbidden_substitutions", [])),
            "synthetic/one-server evidence could substitute for E2E")
    prior = doc.get("known_prior_evidence_not_substitute", [])
    require({"V0-SM1 R9", "NET-SMOOTH1 R31", "NET-SMOOTH1 R3C.4"} <= {
        row.get("source") for row in prior if isinstance(row, dict)},
        "historical tests cannot substitute for full product E2E")
    raw = doc.get("acceptance_gates", [])
    require(isinstance(raw, list) and len(raw) == len(GATES), "missing acceptance gates")
    keyed = {row.get("id"): row for row in raw if isinstance(row, dict)}
    require(len(keyed) == len(raw) and set(keyed) == GATES, "gate identity drift")
    proofs = set(doc.get("required_proof_types", []))
    for gate_id, gate in keyed.items():
        require(gate.get("required") is True, "nonblocking gate: "+gate_id)
        check_min(gate, "min_runs", 1)
        require(isinstance(gate.get("objective"), str) and len(gate["objective"]) > 25,
                "gate needs explicit objective: "+gate_id)
        available = gate.get("proof_types", [])
        require(isinstance(available, list) and len(available) >= 3 and
                len(set(available)) == len(available) and set(available) <= proofs,
                "insufficient evidence sources: "+gate_id)
        if gate_id in CROSS_OWNER:
            require({"authority_trace", "client_trace"} <= set(available),
                    "cross-owner needs both owner and client evidence: "+gate_id)
            if gate_id != "S14_THIRTY_MINUTE_MIXED_SOAK":
                check_min(gate, "min_runs", 3)
    require("process_manifest" in keyed["S01_PHYSICAL_MULTISERVER_TOPOLOGY"]["proof_types"],
            "no real process proof")
    for name in ("S04_SIMULTANEOUS_CROSS_BORDER_CO_PRESENCE",
                 "S09_VISUAL_CAMERA_GEOMETRY_CONTINUITY",
                 "S13_NORMATIVE_E2E_PERFORMANCE"):
        require("video_capture" in keyed[name]["proof_types"],
                "graphical gate cannot be headless-only: "+name)
    for name in ("S05_CROSS_OWNER_ITEM_EXCHANGE",
                 "S06_CROSS_OWNER_CONSTRUCTION",
                 "S07_CROSS_OWNER_MINING_AND_TERRAIN"):
        require("canonical_state_digest" in keyed[name]["proof_types"],
                "canonical source cannot be replaced by visual mirror: "+name)
    release = doc.get("release_decision", {})
    require(isinstance(release, dict), "release decision missing")
    for key in MUST_RELEASE:
        require(release.get(key) is True, "release gate disabled: "+key)
    return {"spec_verdict": "SPEC_CONTRACT_PASS", "product_verdict": "NOT_YET_PROVEN",
            "gates": len(GATES), "minimum_authority_processes":
            topo["min_authority_processes"], "minimum_hosts":
            topo["min_distinct_physical_or_independent_vm_hosts"]}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=SPEC)
    args = parser.parse_args()
    try:
        result = validate_spec(json.loads(args.spec.read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError) as exc:
        print(json.dumps({"spec_verdict": "SPEC_CONTRACT_FAIL",
                          "product_verdict": "NOT_YET_PROVEN", "cause": str(exc)}))
        return 1
    print(json.dumps(result))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
