#!/usr/bin/env python3
"""Bounded ACT0 R2 repair. Writes declared files only; never changes Git refs."""
from __future__ import annotations
import ast
from pathlib import Path
import subprocess

ROOT = Path.cwd()
BASE = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"
SUBJECT = "cb2710598503b5a5391b70c651453a3fcccf23d4"
DOC = "docs/control/mvp-act0-r1/"


def edit(path, transform):
    old = (ROOT/path).read_text(encoding="utf-8")
    expected = subprocess.check_output(["git","show",f"{SUBJECT}:{path}"]).decode()
    if old != expected:
        raise ValueError("R2_SUBJECT_DRIFT:" + path)
    new = transform(old)
    if old == new:
        raise ValueError("R2_NO_CHANGE:" + path)
    ast.parse(new)
    (ROOT/path).write_text(new, encoding="utf-8")


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("R2_ANCHOR_NOT_UNIQUE:" + old[:100])
    return text.replace(old,new,1)


def method(text, name, transform):
    node = next(n for n in ast.walk(ast.parse(text)) if isinstance(n,ast.FunctionDef) and n.name == name)
    lines = text.splitlines(keepends=True)
    old = ''.join(lines[node.lineno-1:node.end_lineno])
    new = transform(old)
    return ''.join(lines[:node.lineno-1]) + new + ''.join(lines[node.end_lineno:])


def overview_patch(text):
    start = text.index('    bundle = ContractBundle.load(', text.index('def canonical_reconciliation_route'))
    end = text.index('    acceptance = load_checkpoint_acceptance(', start)
    old_guard = text[start:end]
    helper = '\n\ndef _validate_canonical_product_snapshot(root: Path, head: str) -> None:\n' + old_guard
    text = text[:start] + '    _validate_canonical_product_snapshot(root, head)\n' + text[end:]
    activation = '''

def _validate_mvp_activation(root: Path, head: str, scheduler: dict[str, Any]) -> None:
    """Canonical activation binds the new execution; a candidate cannot mint it."""
    mvp = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
    routing = scheduler["v0_product_train_routing"]
    declared = routing.get("mvp_activation", {})
    path = declared.get("activation_record")
    if not isinstance(path, str) or not path.startswith("config/control/harness/activation/"):
        raise ContractValidationError("MVP_ACTIVATION_RECORD_REQUIRED")
    activation = read_control(root, path, head)
    base = declared.get("exact_execution_base")
    tree = declared.get("exact_execution_base_tree")
    if not isinstance(base, str) or not re.fullmatch(r"[0-9a-f]{40}", base):
        raise ContractValidationError("MVP_ACTIVATION_BASE_INVALID")
    code, actual_tree = _git(root, "rev-parse", "--verify", base + "^{tree}")
    if code or actual_tree != tree or activation.get("exact_successor_base_tree") != tree:
        raise ContractValidationError("MVP_ACTIVATION_TREE_MISMATCH")
    if _git(root, "merge-base", "--is-ancestor", base, head)[0]:
        raise ContractValidationError("MVP_ACTIVATION_BASE_NOT_CANONICAL_ANCESTOR")
    expected = {"checkpoint": mvp, "main_declared_exact_successor_base": base,
                "project_epoch": declared.get("project_epoch"),
                "work_order_id": declared.get("work_order_id"),
                "runtime_branch": declared.get("runtime_branch")}
    if any(activation.get(key) != value for key, value in expected.items()):
        raise ContractValidationError("MVP_ACTIVATION_IDENTITY_MISMATCH")
    if (routing.get("accepted_predecessor_checkpoint") != P7
            or routing.get("accepted_predecessor_base") != base
            or activation.get("accepted_predecessor", {}).get("checkpoint") != P7):
        raise ContractValidationError("MVP_ACCEPTED_PREDECESSOR_MISMATCH")
    if load_checkpoint_acceptance(root, P7, "main", canonical_head=head) is None:
        raise ContractValidationError("MVP_P7_ACCEPTANCE_REQUIRED")
    lease = scheduler["pre_h0_3_runtime_mutation_lease"]
    if (type(lease.get("capacity")) is not int or lease["capacity"] != 1
            or lease.get("holder_checkpoint") != mvp
            or lease.get("holder_branch") != declared.get("runtime_branch")):
        raise ContractValidationError("MVP_SINGLE_WORKER_LEASE_MISMATCH")
    epoch_id, wo_id = declared.get("project_epoch"), declared.get("work_order_id")
    if any(not isinstance(x, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", x) for x in (epoch_id, wo_id)):
        raise ContractValidationError("MVP_EXECUTION_IDENTITY_INVALID")
    prefix = "config/control/harness/executions/" + epoch_id
    epoch = read_control(root, prefix + "/project-epoch.v1.json", head)
    order = read_control(root, prefix + "/work-orders/" + wo_id + ".v1.json", head)
    if (epoch.get("base_sha") != base or epoch.get("epoch_id") != epoch_id
            or epoch.get("registry_generation") != lease.get("effective_registry_generation")
            or mvp not in epoch.get("eligible_checkpoints", [])
            or order.get("base_sha") != base or order.get("project_epoch") != epoch_id
            or order.get("work_order_id") != wo_id or order.get("goal_checkpoint") != mvp
            or order.get("branch") != lease.get("holder_branch")):
        raise ContractValidationError("MVP_CANONICAL_EPOCH_WORK_ORDER_MISMATCH")
'''
    text = once(text, '\ndef canonical_reconciliation_route(', helper + activation + '\n\ndef canonical_reconciliation_route(')
    text = once(text, '    if routing.get("current_phase") != HOLD:\n', '''    if routing.get("current_phase") != HOLD:
        mvp = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
        if routing.get("current_checkpoint") == mvp and checkpoint in (None, mvp):
            _validate_canonical_product_snapshot(root, head)
            _validate_mvp_activation(root, head, scheduler)
''')
    return text


def project_fixture(text):
    text = once(text, '        cls.base = cls.git("rev-parse", "HEAD")', '''        # This suite exercises the P7 HOLD route, not mutable current MVP routing.
        # Code under test stays current; only disposable canonical control inputs
        # are pinned to the original accepted-P7 snapshot.
        for relative in (
            "config/control/project-program-registry.v1.json",
            "config/control/harness/scheduler-policy.v1.json",
            "config/control/harness/project-goals.v1.json",
            "config/control/harness/v0-product-train-policy.v1.json",
            "config/control/harness/v0-current-work-map.v1.json",
            "config/control/harness/checkpoint-catalog.v1.json",
        ):
            raw = subprocess.check_output(["git", "show", "3d7672cba293d8e7bd72427b803f73fc8fcee5da:" + relative], cwd=ROOT)
            (cls.root / relative).write_bytes(raw)
            cls.git("add", "--", relative)
        cls.git("commit", "-qm", "test-only pinned P7 hold controls")
        cls.base = cls.git("rev-parse", "HEAD")''')
    return text


def p7_history(text):
    text = once(text, '    return json.loads(path.read_text(encoding="utf-8"))', '''    # Explicit historical inputs preserve the P7 contract after lease rotation.
    relative = path.relative_to(ROOT).as_posix()
    raw = subprocess.check_output(["git", "show", "3d7672cba293d8e7bd72427b803f73fc8fcee5da:" + relative], cwd=ROOT)
    return json.loads(raw.decode("utf-8"))''')
    text = once(text, 'class V0ProductTrainPolicyTests', 'class HistoricalP7ProductTrainPolicyTests')
    text = once(text, '                    shutil.copy2(ROOT / relative, destination)', '''                    destination.write_bytes(subprocess.check_output(
                        ["git", "show", "3d7672cba293d8e7bd72427b803f73fc8fcee5da:" + relative], cwd=ROOT))''')
    return '"""Historical P7 regression; current MVP authority is tested in test_v0_mvp_act0."""\n' + text


def generation_guards(text):
    text = once(text, 'P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"', '''P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"
MVP = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
MVP_BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"''')
    text = text.replace('self.assertEqual(P7, lease["holder_checkpoint"])', 'self.assertEqual(MVP, lease["holder_checkpoint"])')
    text = text.replace('self.assertEqual(P7_BRANCH, lease["holder_branch"])', 'self.assertEqual(MVP_BRANCH, lease["holder_branch"])')
    text = text.replace('GLOBAL_MUTATION_SLOT_RESERVED_FOR:{P7}', 'GLOBAL_MUTATION_SLOT_RESERVED_FOR:{MVP}')
    text = text.replace('self.assertEqual("P7_MERGED_CLOSURE_RECONCILIATION", current_v0["stage_status"])', 'self.assertEqual("MVP_ACTIVATED_IMPLEMENTATION_DISPATCHED", current_v0["stage_status"])')
    text = text.replace('self.assertFalse(self.scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"])', 'self.assertTrue(self.scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"])')
    text = text.replace('for_current_p7', 'for_current_mvp').replace('for_p7_lease', 'for_mvp_lease')
    return text


def live_contract(text):
    text = text.replace('CURRENT_V0_BRANCH = "control/project-focus-harness-reconciliation-r1"', 'CURRENT_V0_BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"')
    text = text.replace('CURRENT_V0_PASSPORT = "config/control/branches/control__project-focus-harness-reconciliation-r1.v1.json"', 'CURRENT_V0_PASSPORT = "config/control/branches/feature__v0-mvp-playable-seamless-planet-r1.v1.json"')
    text = text.replace('P7_CONTROL_BASE = "5b4152958624be4e9cc40f2369ce32c4964f65c3"', 'MVP_CONTROL_BASE = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"')
    text = text.replace('self.assertEqual([P7], self.scheduler["parallel_product_checkpoints"]["checkpoints"])', 'self.assertEqual([MVP], self.scheduler["parallel_product_checkpoints"]["checkpoints"])')
    text = text.replace('self.assertFalse(self.scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"])', 'self.assertTrue(self.scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"])')
    text = text.replace('self.assertEqual("accepted SM1 product lineage", execution["branch"])', 'self.assertEqual("accepted P7 canonical main", execution["branch"])')
    text = text.replace('self.assertEqual(SM1_ACCEPTED_BASE, execution["sha"])', 'self.assertEqual(MVP_CONTROL_BASE, execution["sha"])')
    text = text.replace('self.assertTrue(execution["declares_checkpoint_acceptance"])', 'self.assertFalse(execution["declares_checkpoint_acceptance"])')
    text = text.replace('"config/control/harness/acceptance/V0-SM1-R1-CHECKPOINT-ACCEPTED-001.v1.json",\n            execution["acceptance_record"]', '"config/control/harness/acceptance/V0-P7-R1-CHECKPOINT-ACCEPTED-001.v1.json",\n            execution["acceptance_record"]')
    text = text.replace('self.assertEqual(P7_CONTROL_BASE, passport["base_commit"])', 'self.assertEqual(MVP_CONTROL_BASE, passport["base_commit"])')
    text = method(text, 'test_current_registry_and_current_passport_are_consistent', lambda s: s.replace(
        'self.assertEqual([], passport["runtime_paths"])', 'self.assertEqual(["scripts/runtime/networked_gameplay/mvp/**", "scripts/app/**", "scenes/labs/mvp/**"], passport["runtime_paths"])'))
    text = text.replace('self.assertEqual(P7, lease["holder_checkpoint"])', 'self.assertEqual(MVP, lease["holder_checkpoint"])')
    text = text.replace('self.assertEqual(P7_BRANCH, lease["holder_branch"])', 'self.assertEqual(CURRENT_V0_BRANCH, lease["holder_branch"])')
    text = text.replace('"RESERVED_P7_CLOSURE_NO_RUNTIME_MUTATION", lease["state"]', '"RESERVED_MVP_SINGLE_RUNTIME_WORKER", lease["state"]')
    text = text.replace('GLOBAL_MUTATION_SLOT_RESERVED_FOR:{P7}', 'GLOBAL_MUTATION_SLOT_RESERVED_FOR:{MVP}')
    text = text.replace('current_product_lane_to_p7', 'current_product_lane_to_mvp').replace('current_p7_control_frontier', 'current_mvp_control_frontier').replace('main_owned_p7_reserved_lease', 'main_owned_mvp_reserved_lease')
    return text


def mvp_tests(text):
    text = once(text, 'self.assertEqual("DIRECTOR", payload["next"]["next_actor"])', 'self.assertEqual("INTEGRATOR", payload["next"]["next_actor"])')
    new = '''
    def commit_fixture(self, root, relative, value):
        path = root / relative
        path.write_text(json.dumps(value) + "\\n", encoding="utf-8")
        git(root, "add", "--", relative)
        git(root, "-c", "user.name=ACT0 fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test-only canonical fault")
        git(root, "update-ref", "refs/remotes/origin/main", git(root, "rev-parse", "HEAD"))

    def test_mvp_canonical_lease_and_mirror_faults_block_execution(self):
        faults = [
            (H + "scheduler-policy.v1.json", "LEASE_GENERATION_MISMATCH", "lease"),
            (H + "v0-product-train-policy.v1.json", "CURRENT_PHASE_MISMATCH", "phase"),
            (H + "activation/V0-MVP-R1-ACTIVATION-001.v1.json", "MVP_ACTIVATION_TREE_MISMATCH", "tree"),
            (H + "event.schema.v1.json", "JSON_SCHEMA_INVALID", "schema"),
        ]
        for relative, expected, kind in faults:
            with self.subTest(kind=kind), self.fixture(adopted=True) as root:
                value = json.loads((root / relative).read_text())
                if kind == "lease":
                    value["pre_h0_3_runtime_mutation_lease"]["effective_registry_generation"] -= 1
                elif kind == "phase":
                    value["current_phase"] = "INVALID_PHASE"
                elif kind == "tree":
                    value["exact_successor_base_tree"] = "f" * 40
                else:
                    value["type"] = "invalid-schema-type"
                self.commit_fixture(root, relative, value)
                code, result = self.cli(root, "drive")
                self.assertEqual(3, code, result)
                self.assertIn(expected, result["error"]["detail"])

    def test_current_product_sequence_is_unique(self):
        policy = read(H + "v0-product-train-policy.v1.json")
        ids = [item["id"] for item in policy["checkpoint_sequence"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual([P7, MVP, "V0_P8_FIRST_MOBILE_CONSTRUCT"], ids[-3:])

'''
    return once(text, '\n\nif __name__ == "__main__":', '\n' + new + '\nif __name__ == "__main__":')


def main():
    if subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip() != BASE:
        raise ValueError('R2_MAIN_MOVED')
    edit('scripts/harness/project_overview.py', overview_patch)
    edit('tests/harness/test_project_control_validation.py', project_fixture)
    edit('tests/harness/test_v0_product_train_policy.py', p7_history)
    edit('tests/harness/test_v0_generation80_safety_guards.py', generation_guards)
    edit('tests/harness/test_v0_s1_networked_checkpoint_contract.py', live_contract)
    edit('tests/harness/test_harness_evidence_provenance.py', lambda s: once(s,
        '"registry_generation": 81, "architecture_revision": "TEST",',
        '"registry_generation": self.read("config/control/project-program-registry.v1.json")["registry_generation"], "architecture_revision": "TEST",'))
    edit('tests/harness/test_v0_mvp_act0.py', mvp_tests)
    print('ACT0_R2_PATCH_APPLIED_NOT_ACCEPTED')


if __name__ == '__main__':
    main()
