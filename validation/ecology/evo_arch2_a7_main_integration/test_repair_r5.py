"""Focused R5 controls for the production integration verifier; no Godot stubs."""
from __future__ import annotations

import importlib.metadata
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("a7_integration_verifier", Path(__file__).with_name("verify.py"))
assert SPEC is not None and SPEC.loader is not None
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)
CHECKOUT_ROOT = verify.ROOT


class HistoryGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="a7-r5-history-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "A7 R5 test")
        self.git("config", "user.email", "a7-r5@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.base = self.commit("base")
        self.accepted = self.commit("accepted research")
        self.research = self.commit("research descendant")
        self.distant = self.commit("research grandchild")
        self.git("checkout", "--detach", self.base)
        self.clean = self.commit("fresh main convergence")
        self.root_patch = patch.object(verify, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def process(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        # Construction/probe deliberately sees replace refs; the verifier must not.
        env.pop("GIT_NO_REPLACE_OBJECTS", None)
        return subprocess.run(["git", *args], cwd=self.root, env=env, text=True,
                              capture_output=True, check=False, timeout=20)

    def git(self, *args: str) -> str:
        p = self.process(*args)
        if p.returncode:
            self.fail(f"git {args}: {p.returncode}: {p.stderr}")
        return p.stdout.strip()

    def commit(self, message: str) -> str:
        self.git("commit", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def check(self, head: str) -> dict:
        return verify.require_research_free_history(head, self.base, self.accepted)

    def test_clean_convergence_passes(self) -> None:
        result = self.check(self.clean)
        self.assertEqual(result["result"], "PASS")
        self.assertEqual(result["accepted_is_ancestor_exit"], 1)
        self.assertFalse(result["shallow"])
        self.assertTrue(result["replace_objects_disabled"])

    def test_direct_research_parent_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "RESEARCH_COMMIT_IN_CANDIDATE_ANCESTRY"):
            self.check(self.research)

    def test_distant_research_ancestor_rejected(self) -> None:
        self.assertNotIn(self.accepted, self.git("rev-list", "--parents", "-n", "1", self.distant).split()[1:])
        with self.assertRaisesRegex(RuntimeError, "RESEARCH_COMMIT_IN_CANDIDATE_ANCESTRY"):
            self.check(self.distant)

    def test_merge_side_research_ancestor_rejected(self) -> None:
        self.git("merge", "--no-ff", self.distant, "-m", "merge-side research")
        head = self.git("rev-parse", "HEAD")
        self.assertNotIn(self.accepted, self.git("rev-list", "--parents", "-n", "1", head).split()[1:])
        with self.assertRaisesRegex(RuntimeError, "RESEARCH_COMMIT_IN_CANDIDATE_ANCESTRY"):
            self.check(head)

    def test_accepted_head_itself_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "RESEARCH_COMMIT_IN_CANDIDATE_ANCESTRY"):
            self.check(self.accepted)

    def test_missing_accepted_object_is_not_non_ancestry(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "HISTORY_COMMIT_NOT_AVAILABLE"):
            verify.require_research_free_history(self.clean, self.base, "0" * 40)

    def test_missing_candidate_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "HISTORY_COMMIT_NOT_AVAILABLE"):
            self.check("0" * 40)

    def test_unrelated_main_rejected(self) -> None:
        self.git("checkout", "--orphan", "unrelated")
        unrelated = self.commit("different main")
        with self.assertRaisesRegex(RuntimeError, "NOT_CURRENT_MAIN_DESCENDANT"):
            verify.require_research_free_history(self.clean, unrelated, self.accepted)

    def test_shallow_history_rejected(self) -> None:
        shallow = Path(self.tmp.name) / "shallow"
        self.git("clone", "--depth", "1", self.root.as_uri(), str(shallow))
        with patch.object(verify, "ROOT", shallow):
            with self.assertRaisesRegex(RuntimeError, "SHALLOW_HISTORY_NOT_ALLOWED"):
                self.check(self.clean)

    def test_replace_cannot_hide_research_ancestry(self) -> None:
        self.git("replace", "--graft", self.research, self.base)
        self.assertEqual(self.process("merge-base", "--is-ancestor", self.accepted, self.distant).returncode, 1)
        with self.assertRaisesRegex(RuntimeError, "RESEARCH_COMMIT_IN_CANDIDATE_ANCESTRY"):
            self.check(self.distant)

    def test_legacy_grafts_rejected(self) -> None:
        grafts = self.root / ".git/info/grafts"
        grafts.write_text(f"{self.research} {self.base}\n", encoding="ascii")
        with self.assertRaisesRegex(RuntimeError, "GRAFTED_HISTORY_NOT_ALLOWED"):
            self.check(self.distant)

    def test_git_error_is_not_non_ancestry(self) -> None:
        original = verify.gp
        def command(*args: str) -> subprocess.CompletedProcess[str]:
            if args == ("merge-base", "--is-ancestor", self.accepted, self.clean):
                return subprocess.CompletedProcess(args, 128, "", "injected Git read failure")
            return original(*args)
        with patch.object(verify, "gp", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "RESEARCH_ANCESTRY_INDETERMINATE:exit=128"):
                self.check(self.clean)


class DependencyGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="a7-r5-dependency-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.requirements = self.root / "scripts/harness/requirements.txt"
        self.requirements.parent.mkdir(parents=True)
        self.requirements.write_text("jsonschema==4.22.0\n", encoding="utf-8")
        root_patch = patch.object(verify, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def test_canonical_version_passes(self) -> None:
        with patch.object(verify.importlib.metadata, "version", return_value="4.22.0"):
            self.assertEqual(verify.require_harness_dependency(), "4.22.0")

    def test_r4_incorrect_version_rejected(self) -> None:
        with patch.object(verify.importlib.metadata, "version", return_value="4.25.1"):
            with self.assertRaisesRegex(RuntimeError, "PINNED_JSONSCHEMA_VERSION_REQUIRED:4.25.1"):
                verify.require_harness_dependency()

    def test_old_executor_version_rejected(self) -> None:
        with patch.object(verify.importlib.metadata, "version", return_value="4.10.3"):
            with self.assertRaisesRegex(RuntimeError, "PINNED_JSONSCHEMA_VERSION_REQUIRED:4.10.3"):
                verify.require_harness_dependency()

    def test_missing_distribution_rejected(self) -> None:
        with patch.object(verify.importlib.metadata, "version", side_effect=importlib.metadata.PackageNotFoundError):
            with self.assertRaisesRegex(RuntimeError, "PINNED_JSONSCHEMA_MISSING"):
                verify.require_harness_dependency()

    def test_conflicting_canonical_pin_rejected(self) -> None:
        self.requirements.write_text("jsonschema==4.25.1\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "CANONICAL_HARNESS_DEPENDENCY_PIN_MISMATCH"):
            verify.require_harness_dependency()

    def test_duplicate_declaration_rejected(self) -> None:
        self.requirements.write_text("jsonschema==4.22.0\njsonschema==4.22.0\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "CANONICAL_HARNESS_DEPENDENCY_PIN_MISMATCH"):
            verify.require_harness_dependency()

    def test_missing_declaration_rejected(self) -> None:
        self.requirements.write_text("# no pin\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "CANONICAL_HARNESS_DEPENDENCY_PIN_MISMATCH"):
            verify.require_harness_dependency()

    def test_missing_requirements_file_rejected(self) -> None:
        self.requirements.unlink()
        with self.assertRaises(FileNotFoundError):
            verify.require_harness_dependency()

    def test_actual_checkout_and_interpreter_agree(self) -> None:
        with patch.object(verify, "ROOT", CHECKOUT_ROOT):
            self.assertEqual(verify.require_harness_dependency(), "4.22.0")


class ControlHealthGuardTests(unittest.TestCase):
    def test_green_passes(self) -> None:
        self.assertEqual(verify.require_control_health("GREEN"), "GREEN")

    def test_yellow_preserved(self) -> None:
        self.assertEqual(verify.require_control_health("YELLOW"), "YELLOW")

    def test_red_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "CONTROL_HEALTH_NOT_EXPLICIT_NON_RED"):
            verify.require_control_health("RED")

    def test_missing_health_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "CONTROL_HEALTH_NOT_EXPLICIT_NON_RED"):
            verify.require_control_health(None)

    def test_unknown_health_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "CONTROL_HEALTH_NOT_EXPLICIT_NON_RED"):
            verify.require_control_health("UNAVAILABLE")

    def test_wrong_type_rejected(self) -> None:
        for value in (False, 0, {}, [], ["GREEN"]):
            with self.subTest(value=value):
                with self.assertRaisesRegex(RuntimeError, "CONTROL_HEALTH_NOT_EXPLICIT_NON_RED"):
                    verify.require_control_health(value)


if __name__ == "__main__":
    unittest.main()
