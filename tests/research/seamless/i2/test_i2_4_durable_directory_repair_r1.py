from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

from tools.research.seamless.i2.durable_directory import (
    DurableDirectoryCorruption,
    DurableOwnershipDirectory,
)


class I24DurableDirectoryRepairR1Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "ownership-directory.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _valid_record() -> dict[str, object]:
        return {
            "subject_or_domain_id": "domain/player-42",
            "owner_authority_id": "authority-a",
            "authority_epoch": 10,
            "fencing_token": 50,
            "directory_generation": 1,
            "authority_incarnation": 1,
            "state_revision": 200,
            "lease_state": "ACTIVE",
            "route_revision": 30,
        }

    def _write_checksum_valid_snapshot(self, raw_record: dict[str, object]) -> None:
        body = {
            "schema": DurableOwnershipDirectory.SNAPSHOT_SCHEMA,
            "storage_revision": 1,
            "records": [raw_record],
        }
        envelope = {
            **body,
            "checksum_sha256": DurableOwnershipDirectory._checksum_body(body),
        }
        self.path.write_bytes(DurableOwnershipDirectory._canonical_json(envelope))

    def test_i2_4_repair_r1_strict_checksum_valid_invalid_record_payloads_fail_closed(self) -> None:
        valid = self._valid_record()
        self._write_checksum_valid_snapshot(valid)
        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual("domain/player-42", reopened.lookup("domain/player-42").subject_or_domain_id)

        invalid_cases: list[tuple[str, dict[str, object]]] = []

        value = copy.deepcopy(valid)
        value["subject_or_domain_id"] = None
        invalid_cases.append(("null_subject", value))

        value = copy.deepcopy(valid)
        value["authority_epoch"] = "10"
        invalid_cases.append(("numeric_string_epoch", value))

        value = copy.deepcopy(valid)
        value["authority_epoch"] = 10.9
        invalid_cases.append(("floating_epoch", value))

        value = copy.deepcopy(valid)
        value["authority_epoch"] = True
        invalid_cases.append(("boolean_epoch", value))

        value = copy.deepcopy(valid)
        value["fencing_token"] = "50"
        invalid_cases.append(("numeric_string_fence", value))

        value = copy.deepcopy(valid)
        value["state_revision"] = 200.0
        invalid_cases.append(("floating_state_revision", value))

        value = copy.deepcopy(valid)
        value["lease_state"] = 1
        invalid_cases.append(("non_string_lease_state", value))

        value = copy.deepcopy(valid)
        del value["route_revision"]
        invalid_cases.append(("missing_field", value))

        value = copy.deepcopy(valid)
        value["unexpected"] = 1
        invalid_cases.append(("extra_field", value))

        for name, raw_record in invalid_cases:
            with self.subTest(name=name):
                self._write_checksum_valid_snapshot(raw_record)
                with self.assertRaises(DurableDirectoryCorruption):
                    DurableOwnershipDirectory(self.path)


if __name__ == "__main__":
    unittest.main()
