"""Synthetic negative/assembly tests; these are not runtime acceptance evidence."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import audit_ci_packet as audit
import publish_d24_evidence as publish


class PacketPublicationTests(unittest.TestCase):
    def test_unsafe_paths_rejected(self):
        for path in ("../x", "/tmp/x", "a/../b", "a\\b", ".git/config", "C:/file"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                audit.safe_path(path)

    def test_duplicate_json_rejected(self):
        with self.assertRaisesRegex(ValueError, "DUPLICATE_JSON_KEY"):
            audit.parse(b'{"passed": false, "passed": true}')

    def test_bad_archive_digest_rejected(self):
        with tempfile.NamedTemporaryFile() as file:
            file.write(b"not-accepted"); file.flush()
            with self.assertRaisesRegex(ValueError, "ARCHIVE_SHA256_MISMATCH"):
                audit.load_zip(Path(file.name), "0" * 64)

    def test_unsafe_archive_member_rejected(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr("../escape", "fail")
        raw = stream.getvalue()
        with tempfile.NamedTemporaryFile() as file:
            file.write(raw); file.flush()
            with self.assertRaisesRegex(ValueError, "UNSAFE_ARTIFACT_PATH"):
                audit.load_zip(Path(file.name), hashlib.sha256(raw).hexdigest())

    def test_pending_or_failed_jobs_rejected(self):
        for status, conclusion in (("in_progress", None), ("completed", "failure")):
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, "JOB_NOT_SUCCESS"):
                publish.check_jobs([{"name": "exact-validation (world)", "id": 101741388863,
                                     "status": status, "conclusion": conclusion}])

    def test_only_complete_exact_jobs_accepted(self):
        publish.check_jobs(self.jobs())
        with self.assertRaises(ValueError):
            publish.check_jobs(self.jobs() + self.jobs())

    def test_artifact_identity_is_exact(self):
        item = {"name": "exact", "expired": False,
                "workflow_run": {"id": int(audit.RUN), "head_sha": audit.HEAD},
                "digest": "sha256:" + "1" * 64}
        self.assertEqual(publish.choose_artifact([item], "exact", int(audit.RUN)), item)
        with self.assertRaisesRegex(ValueError, "ARTIFACT_NOT_UNIQUE"):
            publish.choose_artifact([item, item], "exact", int(audit.RUN))
        item["workflow_run"]["head_sha"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "ARTIFACT_WRONG_SUBJECT"):
            publish.choose_artifact([item], "exact", int(audit.RUN))

    def test_unfinished_or_stale_world_packet_cannot_publish(self):
        with self.assertRaises((KeyError, ValueError)):
            publish.prepare_packet({"world": {}}, {}, self.jobs())

    def test_user_profile_is_not_exported(self):
        self.assertTrue(publish.selected_world("full-world-core.log"))
        self.assertTrue(publish.selected_world("test-results/world-regression-summary.json"))
        self.assertTrue(publish.selected_world("test-results/eg4-gateway-100/client-alpha.json"))
        self.assertFalse(publish.selected_world("test-results/world-profile-1/data/private.json"))
        self.assertFalse(publish.selected_world("test-results/eg4-gateway-100/user/cache.json"))

    @staticmethod
    def jobs():
        return [{"name": f"exact-validation ({name})", "id": job_id,
                 "status": "completed", "conclusion": "success"} for name, job_id in
                (("world", 101741388863), ("p7", 101741388945))]

    @staticmethod
    def command_fixture():
        log = b"SYNTHETIC_ASSEMBLY_FIXTURE_NOT_RUNTIME_EVIDENCE\n"
        command = {"command": ["synthetic-test-only"], "cwd": "/synthetic", "expected_exit": 0}
        result = {**command, "exit_code": 0, "fatal_matches": [],
                  "log_sha256": hashlib.sha256(log).hexdigest()}
        native = {"job": "synthetic", "runner": "synthetic", "run_id": audit.RUN,
                  "run_attempt": "1", "workflow_sha": audit.HEAD, "godot_sha256": audit.ENGINE}
        return {"step.command.json": publish.encoded(command), "step.result.json": publish.encoded(result),
                "step.log": log, "manifest.json": publish.encoded(native)}

    def test_assembly_preserves_failure_and_does_not_claim_acceptance(self):
        # Mocks isolate packaging only. Actual publisher never imports these mocks.
        world = self.command_fixture()
        native = audit.parse(world["manifest.json"])
        source = {"world": world, "p7": dict(world), "control": {"close-role.log": b"exit3\n"},
                  "pc0": {"a.json": b'{"overall_health":"YELLOW"}',
                          "b.json": b'{"overall_health":"YELLOW"}'}}
        with patch.object(publish, "audit_world", return_value={"synthetic": True}), \
             patch.object(publish, "audit_p7", return_value=native):
            files = publish.prepare_packet(source, {}, self.jobs())
        self.assertEqual(files["control/close-role.log"], b"exit3\n")
        readiness = audit.parse(files["readiness.v1.json"])
        self.assertFalse(readiness["canonical_acceptance"])
        self.assertFalse(readiness["overall_workflow_green"])
        self.assertIsNone(readiness["independent_verifier_verdict"])
        manifest = audit.parse(files["machine-evidence-manifest.v1.json"])
        for artifact in manifest["artifacts"]:
            raw = files[artifact["path"].removeprefix(publish.OUTPUT)]
            self.assertEqual(artifact["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(len(manifest["commands"]), 2)
        self.assertNotIn(publish.OUTPUT + "control/close-role.log", [a["path"] for a in manifest["artifacts"]])

    def test_tampered_command_rejected(self):
        files = self.command_fixture()
        files["step.log"] += b"tampered"
        with self.assertRaisesRegex(ValueError, "LOG_NOT_VALID"):
            audit.audit_command(files, "step")

    def test_wrong_exit_rejected(self):
        files = self.command_fixture()
        result = audit.parse(files["step.result.json"]); result["exit_code"] = 1
        files["step.result.json"] = publish.encoded(result)
        with self.assertRaisesRegex(ValueError, "EXIT_MISMATCH"):
            audit.audit_command(files, "step")


if __name__ == "__main__":
    unittest.main()
