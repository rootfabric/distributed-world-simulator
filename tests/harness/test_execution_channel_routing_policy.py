"""R2: every declared recovery requirement must have an executable guard."""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError

ROUTE = "GITHUB_CONNECTOR_OR_NORMAL_GIT_WHEN_NETWORK_AND_AUTH_ARE_PROVEN_AVAILABLE"
POLICY = "config/control/harness/continuation-policy.v1.json"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "--no-replace-objects", *args], cwd=root,
        text=True, encoding="utf-8", stderr=subprocess.PIPE, timeout=30,
    ).strip()


def requirement_paths(value: dict, prefix: tuple = ()):
    """Enumerate dict fields and each required list member from actual policy."""
    for key, child in value.items():
        path = prefix + (key,)
        yield path
        if isinstance(child, dict):
            yield from requirement_paths(child, path)
        elif isinstance(child, list):
            for index in range(len(child)):
                yield path + (index,)


class ExecutionChannelRoutingPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)

    def test_repository_route_is_exact_typed_and_required(self) -> None:
        route = self.bundle.contracts["continuation_policy"]["execution_channel_recovery"]["github_source_routing"]
        self.assertEqual(ROUTE, route["repository_read_write"])
        for value in (None, "", "USE_GITHUB_ACTIONS_AS_GIT_TRANSPORT", "CONTAINER_DOWNLOAD",
                      "GITHUB_CONNECTOR", True, False, 0, 1, [], {}, [ROUTE]):
            with self.subTest(value=value):
                changed = copy.deepcopy(self.bundle.contracts)
                changed["continuation_policy"]["execution_channel_recovery"]["github_source_routing"]["repository_read_write"] = value
                with self.assertRaisesRegex(ContractValidationError, "CHANNEL_GITHUB_REPOSITORY_ROUTE_INVALID"):
                    ContractBundle(ROOT, changed).validate_integrity()
        changed = copy.deepcopy(self.bundle.contracts)
        del changed["continuation_policy"]["execution_channel_recovery"]["github_source_routing"]["repository_read_write"]
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_GITHUB_REPOSITORY_ROUTE_INVALID"):
            ContractBundle(ROOT, changed).validate_integrity()

    def test_every_declared_recovery_requirement_rejects_omission(self) -> None:
        recovery = self.bundle.contracts["continuation_policy"]["execution_channel_recovery"]
        paths = list(requirement_paths(recovery))
        self.assertIn(("github_source_routing", "repository_read_write"), paths)
        self.assertIn(("recovery_anchor_requires", 0), paths)
        for path in paths:
            with self.subTest(requirement=path):
                changed = copy.deepcopy(self.bundle.contracts)
                target = changed["continuation_policy"]["execution_channel_recovery"]
                for key in path[:-1]:
                    target = target[key]
                del target[path[-1]]
                with self.assertRaises(ContractValidationError):
                    ContractBundle(ROOT, changed).validate_integrity()

    def test_drive_and_close_mission_reject_committed_forbidden_route(self) -> None:
        subject = git(ROOT, "rev-parse", "HEAD")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            # Local existing CI checkout only; no external network or bootstrap.
            git(ROOT, "clone", "--no-hardlinks", "--no-checkout", str(ROOT), str(root))
            git(root, "checkout", "-B", "main", subject)
            policy = json.loads((root / POLICY).read_text(encoding="utf-8"))
            policy["execution_channel_recovery"]["github_source_routing"]["repository_read_write"] = "USE_GITHUB_ACTIONS_AS_GIT_TRANSPORT"
            (root / POLICY).write_text(json.dumps(policy), encoding="utf-8")
            git(root, "add", POLICY)
            git(root, "-c", "user.name=Harness fixture", "-c", "user.email=harness@example.invalid",
                "commit", "-m", "negative control: forbidden repository route")
            git(root, "update-ref", "refs/remotes/origin/main", git(root, "rev-parse", "HEAD"))
            env = dict(os.environ, PYTHONPATH=str(ROOT / "scripts"))
            for mode in ("drive", "close-mission"):
                with self.subTest(mode=mode):
                    run = subprocess.run(
                        [sys.executable, "-m", "harness.cli", mode, "--root", str(root)],
                        cwd=root, env=env, capture_output=True, text=True,
                        encoding="utf-8", check=False, timeout=30,
                    )
                    self.assertEqual(3, run.returncode, run.stderr or run.stdout)
                    payload = json.loads(run.stdout.strip().splitlines()[-1])
                    self.assertFalse(payload["ok"])
                    self.assertIn("CHANNEL_GITHUB_REPOSITORY_ROUTE_INVALID", payload["error"]["detail"])


if __name__ == "__main__":
    unittest.main()
