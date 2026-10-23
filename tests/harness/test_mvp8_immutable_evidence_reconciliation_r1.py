"""Focused fail-closed tests for immutable MVP8 legacy evidence quarantine.

Canonical evidence history remains unchanged; the per-epoch reconciliation
manifest is the only new authorization filter. These tests run against an
exact Git checkout, not copied fixture claims.
"""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.state_builder import _load_evidence_maps, _select_authoritative_evidence_paths
import harness.state_builder as state_builder

EPOCH = ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
MANIFEST = EPOCH / "evidence-ledger-reconciliation.v1.json"
PRELIM = EPOCH / "evidence/MVP8-EVIDENCE-MAP-90BC1026-R1.v1.json"
VALID = EPOCH / "evidence/MVP7-EVIDENCE-MAP-AD48B24D-R1.v1.json"
WORK_ORDER = "V0-MVP-R1-WO-001"
PIN = "9d6d6c676fdca3501ec35b8962c8dca36eaccfd7"


class TestImmutableMvp8EvidenceReconciliation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bundle = ContractBundle.load(ROOT)
        cls.manifest = read_json(MANIFEST)
        cls.prelim = read_json(PRELIM)

    def test_history_preserved_and_exact_pin(self) -> None:
        self.assertTrue(PRELIM.is_file())
        self.assertEqual(
            subprocess.check_output(
                ["git", "rev-parse", "HEAD:" + PRELIM.relative_to(ROOT).as_posix()],
                cwd=ROOT, text=True,
            ).strip(), PIN)
        history = subprocess.check_output(
            ["git", "log", "--format=%H", "--", PRELIM.relative_to(ROOT).as_posix()],
            cwd=ROOT, text=True,
        ).strip().splitlines()
        self.assertEqual(len(history), 1)
        self.assertEqual(self.manifest["quarantined_evidence"][0]["git_blob_sha"], PIN)

    def test_raw_claim_still_rejected_by_unmodified_schema(self) -> None:
        # RED control: the historical file is invalid, and quarantine must
        # not silently translate PENDING to PASS or soften schema enums.
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID"):
            self.bundle.validate("evidence_map_schema", self.prelim, "raw-historical")

    def test_authoritative_selection_excludes_only_pinned_history(self) -> None:
        selected = _select_authoritative_evidence_paths(
            self.bundle, EPOCH / "evidence", WORK_ORDER)
        self.assertNotIn(PRELIM, selected)
        self.assertIn(VALID, selected)
        maps = _load_evidence_maps(self.bundle, EPOCH / "evidence", WORK_ORDER)
        self.assertTrue(maps)
        for item in maps:
            self.bundle.validate("evidence_map_schema", item, "selected")
            self.assertNotEqual(item.get("evidence_head_sha"), self.prelim["evidence_head_sha"])
        self.assertEqual(
            self.bundle.contracts["evidence_map_schema"]["properties"]["pc0"]["enum"],
            ["NON_RED", "RED", "NOT_RUN"])

    def test_tampered_blob_pin_fails_closed(self) -> None:
        bad = copy.deepcopy(self.manifest)
        bad["quarantined_evidence"][0]["git_blob_sha"] = "0" * 40
        original = state_builder.read_json

        def substitute(path: Path):
            return bad if path.resolve() == MANIFEST.resolve() else original(path)

        with mock.patch.object(state_builder, "read_json", side_effect=substitute):
            with self.assertRaisesRegex(
                ContractValidationError, "EVIDENCE_RECONCILIATION_BLOB_MISMATCH"
            ):
                _select_authoritative_evidence_paths(
                    self.bundle, EPOCH / "evidence", WORK_ORDER)

    def test_wildcard_or_missing_quarantine_refused(self) -> None:
        for kind in ("wildcard", "empty"):
            with self.subTest(kind=kind):
                bad = copy.deepcopy(self.manifest)
                if kind == "wildcard":
                    bad["quarantined_evidence"][0]["path"] += "*"
                    expected = "EVIDENCE_RECONCILIATION_RECORD_INVALID"
                else:
                    bad["quarantined_evidence"] = []
                    expected = "EVIDENCE_RECONCILIATION_QUARANTINE_EMPTY"
                original = state_builder.read_json

                def substitute(path: Path):
                    return bad if path.resolve() == MANIFEST.resolve() else original(path)

                with mock.patch.object(state_builder, "read_json", side_effect=substitute):
                    with self.assertRaisesRegex(ContractValidationError, expected):
                        _select_authoritative_evidence_paths(
                            self.bundle, EPOCH / "evidence", WORK_ORDER)


if __name__ == "__main__":
    unittest.main()
