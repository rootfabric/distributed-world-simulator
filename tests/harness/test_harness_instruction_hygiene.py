from __future__ import annotations
import json, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(ROOT/"scripts"))
from harness.instruction_hygiene import audit, audit_rule_registry

class HarnessInstructionHygieneTests(unittest.TestCase):
    def test_current_repository_router_and_registry_are_clean(self): self.assertEqual([],audit(ROOT))
    def test_protected_rule_cannot_auto_retire(self):
        p={"rule_lifecycle":{"required_fields":["rule_id","class","source","trigger","enforcement","retirement"],"protected_classes":["SAFETY_INVARIANT"],"auto_retirement_forbidden":True}}
        r={"rules":[{"rule_id":"R1","class":"SAFETY_INVARIANT","source":"incident","trigger":"always","enforcement":"machine","retirement":"AUTO"}]}
        self.assertTrue(any(x.startswith("PROTECTED_RULE_AUTO_RETIREMENT") for x in audit_rule_registry(p,r)))
    def test_duplicate_rule_id_fails(self):
        p={"rule_lifecycle":{"required_fields":["rule_id","class","source","trigger","enforcement","retirement"],"protected_classes":[],"auto_retirement_forbidden":True}}
        rule={"rule_id":"R1","class":"PROCESS_GUARD","source":"x","trigger":"y","enforcement":"z","retirement":"review"}; self.assertIn("RULE_ID_DUPLICATE:R1",audit_rule_registry(p,{"rules":[rule,dict(rule)]}))
    def test_mutable_state_in_router_fails(self):
        with tempfile.TemporaryDirectory() as td:
            q=Path(td); (q/"config/control/harness").mkdir(parents=True); (q/"AGENTS.md").write_text("## Current harness gate\nH0.1\n",encoding="utf-8")
            p={"schema":"x","router_files":["AGENTS.md"],"budgets":{"AGENTS.md":{"max_lines":100,"max_bytes":1000}},"mutable_state_forbidden_in_router":["## Current harness gate"],"importance_markers":{"tokens":[],"warn_above_per_file":100},"rule_lifecycle":{"required_fields":["rule_id","class","source","trigger","enforcement","retirement"],"protected_classes":[],"auto_retirement_forbidden":True}}
            (q/"config/control/harness/instruction-hygiene-policy.v1.json").write_text(json.dumps(p)); (q/"config/control/harness/rule-registry.v1.json").write_text('{"rules":[]}')
            self.assertTrue(any(x.startswith("MUTABLE_STATE_IN_ROUTER") for x in audit(q)))
    def test_context_budget_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            q=Path(td); (q/"config/control/harness").mkdir(parents=True); (q/"AGENTS.md").write_text("rule\n"*20)
            p={"schema":"x","router_files":["AGENTS.md"],"budgets":{"AGENTS.md":{"max_lines":5,"max_bytes":1000}},"mutable_state_forbidden_in_router":[],"importance_markers":{"tokens":[],"warn_above_per_file":100},"rule_lifecycle":{"required_fields":["rule_id","class","source","trigger","enforcement","retirement"],"protected_classes":[],"auto_retirement_forbidden":True}}
            (q/"config/control/harness/instruction-hygiene-policy.v1.json").write_text(json.dumps(p)); (q/"config/control/harness/rule-registry.v1.json").write_text('{"rules":[]}')
            self.assertTrue(any(x.startswith("ROUTER_LINE_BUDGET_EXCEEDED") for x in audit(q)))

if __name__=="__main__": unittest.main()
