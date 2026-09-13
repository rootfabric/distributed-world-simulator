"""R6 exact-tree and complete-suite controls using the actual verifier helpers."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("a7_r6_verifier", Path(__file__).with_name("verify.py"))
assert SPEC is not None and SPEC.loader is not None
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class ResourceGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="a7-r6-resource-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "A7 R6 test")
        self.git("config", "user.email", "a7-r6@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write("scripts/main.gd", 'extends RefCounted\nconst D = preload("res://scripts/dep.gd")\n')
        self.write("scripts/dep.gd", "extends RefCounted\n")
        self.git("add", ".")
        self.git("commit", "-m", "frozen resources")
        self.head = self.git("rev-parse", "HEAD")
        root_patch = patch.object(verify, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def git(self, *args: str) -> str:
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        p = subprocess.run(["git", *args], cwd=self.root, env=env, text=True,
                           capture_output=True, timeout=20, check=False)
        if p.returncode:
            self.fail(f"git {args}: {p.returncode}: {p.stderr}")
        return p.stdout.strip()

    def write(self, rel: str, text: str) -> None:
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def seal(self) -> None:
        self.git("add", ".")
        self.git("commit", "-m", "new fixture")
        self.head = self.git("rev-parse", "HEAD")

    def resource(self, rel: str) -> str:
        return verify.require_exact_resource(self.head, rel)

    def test_tracked_regular_resource_passes(self) -> None:
        self.assertEqual(self.resource("scripts/dep.gd"), self.git("rev-parse", self.head + ":scripts/dep.gd"))

    def test_missing_resource_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_IN_FROZEN_TREE"):
            self.resource("scripts/absent.gd")

    def test_untracked_resource_not_part_of_head(self) -> None:
        self.write("scripts/absent.gd", "extends RefCounted\n")
        self.assertTrue((self.root / "scripts/absent.gd").exists())
        self.assertFalse(self.git("status", "--porcelain", "--untracked-files=no"))
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_IN_FROZEN_TREE"):
            self.resource("scripts/absent.gd")

    def test_modified_tracked_bytes_rejected(self) -> None:
        self.write("scripts/dep.gd", "extends Node\n")
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_WORKTREE_BYTES_MISMATCH"):
            self.resource("scripts/dep.gd")

    def test_staged_only_resource_rejected(self) -> None:
        self.write("scripts/staged.gd", "extends RefCounted\n")
        self.git("add", "scripts/staged.gd")
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_IN_FROZEN_TREE"):
            self.resource("scripts/staged.gd")

    def test_tracked_symlink_rejected(self) -> None:
        (self.root / "scripts/link.gd").symlink_to("dep.gd")
        self.seal()
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_REGULAR_BLOB"):
            self.resource("scripts/link.gd")

    def test_worktree_parent_symlink_rejected(self) -> None:
        target = Path(self.tmp.name) / "moved-scripts"
        (self.root / "scripts").rename(target)
        (self.root / "scripts").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_WORKTREE_SYMLINK"):
            self.resource("scripts/dep.gd")

    def test_noncanonical_paths_rejected(self) -> None:
        for rel in ("", "../outside.gd", "/scripts/dep.gd", "scripts/../scripts/dep.gd",
                    "scripts//dep.gd", "scripts/./dep.gd", " scripts/dep.gd", "scripts\\dep.gd"):
            with self.subTest(rel=rel):
                with self.assertRaisesRegex(RuntimeError, "NONCANONICAL_RESOURCE_PATH"):
                    self.resource(rel)

    def test_git_error_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_TREE_READ_FAILED"):
            verify.require_exact_resource("0" * 40, "scripts/dep.gd")

    def test_directory_not_blob_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_REGULAR_BLOB"):
            self.resource("scripts")

    def test_transitive_closure_passes(self) -> None:
        self.write("scripts/dep.gd", 'extends RefCounted\nconst D = preload("res://scripts/deep.gd")\n')
        self.write("scripts/deep.gd", "extends RefCounted\n")
        self.seal()
        result = verify.require_source_closure(self.head, ["scripts/main.gd"])
        self.assertEqual(set(result["objects"]), {"scripts/main.gd", "scripts/dep.gd", "scripts/deep.gd"})
        self.assertEqual(result["references"], 2)
        self.assertEqual(result["authority"], "FROZEN_GIT_TREE_AND_WORKING_BYTES")

    def test_transitive_untracked_dependency_rejected(self) -> None:
        self.write("scripts/dep.gd", 'extends RefCounted\nconst D = preload("res://scripts/decoy.gd")\n')
        self.seal()
        self.write("scripts/decoy.gd", "extends RefCounted\n")
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_IN_FROZEN_TREE"):
            verify.require_source_closure(self.head, ["scripts/main.gd"])

    def test_cycle_terminates(self) -> None:
        self.write("scripts/dep.gd", 'extends RefCounted\nconst D = preload("res://scripts/main.gd")\n')
        self.seal()
        result = verify.require_source_closure(self.head, ["scripts/main.gd"])
        self.assertEqual(result["sources"], 2)
        self.assertEqual(result["references"], 2)

    def test_generated_script_not_exempted(self) -> None:
        self.write("scripts/main.gd", 'extends RefCounted\nconst D = preload("res://artifacts/a7/decoy.gd")\n')
        self.seal()
        self.write("artifacts/a7/decoy.gd", "extends RefCounted\n")
        with self.assertRaisesRegex(RuntimeError, "RESOURCE_NOT_IN_FROZEN_TREE"):
            verify.require_source_closure(self.head, ["scripts/main.gd"])

    def test_generated_report_explicitly_classified(self) -> None:
        self.write("scripts/main.gd", 'extends RefCounted\nconst D = load("res://artifacts/a7/capture-sources.json")\n')
        self.seal()
        result = verify.require_source_closure(self.head, ["scripts/main.gd"])
        self.assertEqual(result["generated_missing_allowed"],
                         [{"source": "scripts/main.gd", "target": "artifacts/a7/capture-sources.json"}])


class SuiteCompletenessTests(unittest.TestCase):
    @staticmethod
    def footer(count: int) -> str:
        return f"Ran {count} tests in 0.123s\n\nOK\n"

    def test_all_27_pass(self) -> None:
        self.assertEqual(verify.require_unittest_result(self.footer(27), 27), 27)
        self.assertEqual(verify.require_unittest_result(self.footer(21), 21), 21)

    def test_any_missing_test_rejected(self) -> None:
        for count in (0, 20, 26):
            with self.subTest(count=count):
                with self.assertRaisesRegex(RuntimeError, "MANDATORY_UNITTEST_SUITE_INCOMPLETE"):
                    verify.require_unittest_result(self.footer(count), 27)

    def test_extra_test_count_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "MANDATORY_UNITTEST_SUITE_INCOMPLETE"):
            verify.require_unittest_result(self.footer(28), 27)

    def test_skip_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "MANDATORY_UNITTEST_SUITE_INCOMPLETE"):
            verify.require_unittest_result(self.footer(27) + "OK (skipped=1)\n", 27)

    def test_errors_and_failures_rejected(self) -> None:
        for suffix in ("ERROR: test_broken\n", "FAIL: test_broken\n", "FAILED (failures=1)\n"):
            with self.subTest(suffix=suffix):
                with self.assertRaisesRegex(RuntimeError, "MANDATORY_UNITTEST_SUITE_INCOMPLETE"):
                    verify.require_unittest_result(self.footer(27) + suffix, 27)

    def test_missing_or_ambiguous_footer_rejected(self) -> None:
        for text in ("OK\n", self.footer(27) * 2, "Ran 27 tests in 1s\n", ""):
            with self.subTest(text=text):
                with self.assertRaisesRegex(RuntimeError, "MANDATORY_UNITTEST_SUITE_INCOMPLETE"):
                    verify.require_unittest_result(text, 27)


if __name__ == "__main__":
    unittest.main()
