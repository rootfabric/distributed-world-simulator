import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROADMAP_PATH = ROOT / "docs/plans/seamless-world-sm1-roadmap.v2.json"
INCUBATION_PATH = ROOT / "docs/plans/seamless-world-pre-p6-incubation.v1.json"
CURRENT_PATH = ROOT / "docs/architecture/SEAMLESS_WORLD_CURRENT_RU.md"

R1_CURRENT_TREE_FORBIDDEN = [
    ROOT / "docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md",
    ROOT / "docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_RU.md",
    ROOT / "docs/plans/seamless-world-sm1-roadmap.v1.json",
    ROOT / "docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_RU.md",
]


class SeamlessWorldResearchPlanContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roadmap = json.loads(ROADMAP_PATH.read_text(encoding="utf-8"))
        cls.incubation = json.loads(INCUBATION_PATH.read_text(encoding="utf-8"))
        cls.current = CURRENT_PATH.read_text(encoding="utf-8")

    def test_machine_documents_are_objects_and_research_only(self):
        self.assertIsInstance(self.roadmap, dict)
        self.assertIsInstance(self.incubation, dict)
        self.assertEqual(self.roadmap["status"], "RESEARCH_NOT_ACTIVATED")
        self.assertFalse(self.roadmap["activation"]["production_sm1_active"])
        self.assertEqual(
            self.incubation["status"], "RESEARCH_PRE_ACTIVATION_NOT_PRODUCTION"
        )
        self.assertFalse(self.incubation["production_activation"])

    def test_research_and_production_runtime_gates_are_distinct(self):
        activation = self.roadmap["activation"]
        self.assertNotIn("required_before_first_runtime_work", activation)
        self.assertIn("research_semantic_runtime_gate", activation)
        self.assertIn("required_before_first_production_runtime_work", activation)

        research_gate = activation["research_semantic_runtime_gate"]
        self.assertEqual(
            research_gate["plan"],
            "docs/plans/seamless-world-pre-p6-incubation.v1.json",
        )
        self.assertEqual(
            research_gate["required_before_i2_or_later"],
            ["PR_137_REPAIRED_HEAD_FRESH_INDEPENDENT_ARCHITECTURE_REVIEW_PASS"],
        )
        self.assertFalse(research_gate["production_acceptance_claim_allowed"])

        production = set(activation["required_before_first_production_runtime_work"])
        required = {
            "V0_P6_ACCEPTED_ON_MAIN_LINEAGE",
            "MAIN_RECORDS_ACTIVATE_V0_SM1",
            "MAIN_DECLARES_EXACT_SM1_SUCCESSOR_BASE",
            "FRESH_SM1_EPOCH_AND_WORK_ORDER_EXISTS",
            "RUNTIME_MUTATION_LEASE_ROTATED_TO_SM1_IF_REQUIRED",
            "DIRECTOR_DISPATCHES_SM1_H0",
        }
        self.assertEqual(production, required)

        self.assertEqual(
            self.incubation["start_rule"]["semantic_runtime_after"],
            ["PR_137_REPAIRED_HEAD_FRESH_INDEPENDENT_ARCHITECTURE_REVIEW_PASS"],
        )
        self.assertIn("P6_ACCEPTED", self.incubation["start_rule"]["production_runtime_after"])

    def test_current_repair_overlays_exist_and_are_routed(self):
        for key in ("architecture", "architecture_repair", "validation_strategy", "validation_repair"):
            path = ROOT / self.roadmap[key]
            self.assertTrue(path.is_file(), f"missing current contract: {path}")
            self.assertIn(str(self.roadmap[key]), self.current)

    def test_incarnation_fencing_is_first_class(self):
        invariants = set(self.roadmap["global_invariants"])
        self.assertIn("AUTHORITY_INCARNATION_CURRENT_FOR_CANONICAL_MUTATION", invariants)
        self.assertIn(
            "SAME_AUTHORITY_ID_REPLACEMENT_ROTATES_DIRECTORY_FENCE_AND_GENERATION",
            invariants,
        )
        h1 = self._by_id(self.roadmap["milestones"], "SM1-H1")
        self.assertIn("STALE_SAME_AUTHORITY_ID_INCARNATION_FENCED", h1["critical_oracles"])
        i2 = self._by_id(self.incubation["stages"], "I2")
        self.assertIn(
            "stale_same_authority_id_incarnation_fenced", i2["must_prove"]
        )
        self.assertEqual(
            self.incubation["global_oracles"]["stale_incarnation_mutations_accepted"],
            0,
        )

    def test_dependency_graphs_are_unique_resolved_and_acyclic(self):
        self._assert_graph(self.roadmap["milestones"])
        self._assert_graph(self.incubation["stages"])

    def test_required_milestone_ordering(self):
        deps = {node["id"]: set(node.get("depends_on", [])) for node in self.roadmap["milestones"]}
        self.assertTrue(self._depends_transitively(deps, "SM1-H5", "SM1-H2A"))
        self.assertTrue(self._depends_transitively(deps, "SM1-H5", "SM1-H2B"))
        self.assertTrue(self._depends_transitively(deps, "SM-D1", "SM1-H12"))
        self.assertTrue(self._depends_transitively(deps, "SM-D2", "SM1-H12"))
        self.assertTrue(self._depends_transitively(deps, "SM-D3", "SM1-H12"))
        for dynamic_id in ("SM-D1", "SM-D2", "SM-D3"):
            node = self._by_id(self.roadmap["milestones"], dynamic_id)
            self.assertFalse(node["active_before_h12"])

    def test_r1_implementation_candidates_are_not_in_current_tree(self):
        for path in R1_CURRENT_TREE_FORBIDDEN:
            self.assertFalse(path.exists(), f"stale R1 current candidate still present: {path}")
        self.assertIn("preserved in Git history", self.current)

    @staticmethod
    def _by_id(nodes, node_id):
        return next(node for node in nodes if node["id"] == node_id)

    def _assert_graph(self, nodes):
        ids = [node["id"] for node in nodes]
        self.assertEqual(len(ids), len(set(ids)), "duplicate milestone/stage id")
        known = set(ids)
        deps = {node["id"]: set(node.get("depends_on", [])) for node in nodes}
        for node_id, required in deps.items():
            self.assertTrue(required <= known, f"unresolved dependency for {node_id}: {required - known}")
        visiting = set()
        visited = set()

        def visit(node_id):
            if node_id in visiting:
                self.fail(f"dependency cycle at {node_id}")
            if node_id in visited:
                return
            visiting.add(node_id)
            for dependency in deps[node_id]:
                visit(dependency)
            visiting.remove(node_id)
            visited.add(node_id)

        for node_id in ids:
            visit(node_id)

    @staticmethod
    def _depends_transitively(deps, start, target):
        stack = list(deps[start])
        seen = set()
        while stack:
            current = stack.pop()
            if current == target:
                return True
            if current in seen:
                continue
            seen.add(current)
            stack.extend(deps.get(current, ()))
        return False


if __name__ == "__main__":
    unittest.main()
