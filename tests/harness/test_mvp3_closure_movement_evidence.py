"""Synthetic validator tests only; real graphical evidence comes from processes."""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "tests/integration/test_v0_mvp3_graphical_process_roundtrip.py"
SPEC = importlib.util.spec_from_file_location("mvp3_graphical_evidence", PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def player(actor: str, x: float, sequence: int) -> dict:
    return {"logical_player_id": actor, "player_entity_id": "player/" + actor,
            "transport_session_id": "transport-session/synthetic/" + actor,
            "ownership_epoch": 1, "position": {"x": x, "y": 0.0, "z": 0.0},
            "last_input_sequence": sequence, "state_revision": sequence + 10}


def fixture() -> tuple[dict, dict]:
    step = {"fixed_tick": True, "delta_seconds": 1 / 60}
    transfers = []
    for sequence, (source, target) in enumerate((("authority/a", "authority/b"), ("authority/b", "authority/a")), 2):
        transfers.append({"actor": "a", "source": source, "target": target,
                          "before": player("a", 0.0, sequence), "after": player("a", 0.1, sequence + 1),
                          "post_activation_server_simulation": dict(step),
                          "post_activation_operation_id": "operation/synthetic/" + str(sequence),
                          "post_activation_server_tick": sequence + 1})
    gateway = {"sequences": {"a": 4, "b": 4}, "transfers": transfers,
               "input_observations": {actor: [{"before": player(actor, 0.0, 1),
                                              "after": player(actor, 0.1, 2),
                                              "server_simulation": dict(step)}] for actor in ("a", "b")}}
    clients = {actor: {"fixed_input_receipts": 4, "input_sequence": 4, "manual_input_events": 0} for actor in ("a", "b")}
    return gateway, clients


class MVP3ClosureMovementEvidenceTests(unittest.TestCase):
    def test_complete_synthetic_fixture_is_accepted_by_reducer_only(self):
        gateway, clients = fixture()
        self.assertTrue(all(MODULE.movement_evidence_checks(gateway, clients).values()))

    def test_route_only_or_missing_post_activation_state_is_rejected(self):
        gateway, clients = fixture()
        for transfer in gateway["transfers"]:
            transfer.pop("after")
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])

    def test_neutral_command_with_new_sequence_cannot_complete_crossing(self):
        gateway, clients = fixture()
        gateway["transfers"][0]["after"]["position"] = copy.deepcopy(gateway["transfers"][0]["before"]["position"])
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])

    def test_rebound_identity_cannot_complete_crossing(self):
        gateway, clients = fixture()
        gateway["transfers"][1]["after"]["transport_session_id"] += "-reconnected"
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])

    def test_stale_input_despite_displacement_is_rejected(self):
        gateway, clients = fixture()
        gateway["transfers"][0]["after"]["last_input_sequence"] = gateway["transfers"][0]["before"]["last_input_sequence"]
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])

    def test_nonfixed_receipt_and_nan_cannot_prove_motion(self):
        gateway, clients = fixture()
        gateway["transfers"][0]["post_activation_server_simulation"]["fixed_tick"] = False
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])
        gateway, clients = fixture()
        gateway["transfers"][1]["after"]["position"]["x"] = float("nan")
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["post_activation_movement"])

    def test_observer_without_own_movement_is_not_independent_player(self):
        gateway, clients = fixture()
        gateway["input_observations"]["b"][0]["after"]["position"]["x"] = 0.0
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["both_players_independent"])

    def test_missing_client_receipt_fails_closed(self):
        gateway, clients = fixture()
        clients["b"]["fixed_input_receipts"] = 0
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients)["canonical_fixed_receipts"])

    def test_automatic_workload_is_not_manual_input_evidence(self):
        gateway, clients = fixture()
        self.assertFalse(MODULE.movement_evidence_checks(gateway, clients, manual=True)["manual_input_proven_when_requested"])
        for report in clients.values():
            report["manual_input_events"] = 2
        self.assertTrue(MODULE.movement_evidence_checks(gateway, clients, manual=True)["manual_input_proven_when_requested"])


if __name__ == "__main__":
    unittest.main()
