"""Focused migration falsifiers; no product test is replaced by these checks."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('migration', ROOT/'scripts/devflow/apply_optimization.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def workflow(tests, *, pin='a'*64, env=None, fail_marker=True):
    runs='\n'.join(f'"$godot" --headless --path . --script res://tests/{name}.gd > /tmp/{name}.log\ngrep -Fx "ECO_ARCH2_{name.upper()} PASS" /tmp/{name}.log' for name in tests)
    value={'name':'exact', 'on':{'push':{'branches':['feature/eco']}, 'pull_request':{'paths':['scripts/ecology/**']}, 'workflow_dispatch':None},
           'permissions':{'contents':'read'}, 'jobs':{'exact':{'runs-on':['self-hosted','Linux'], 'steps':[{'shell':'bash','env':env or {},'run':f'# {pin}\n'+runs}]}}}
    return m.dump_yaml(value)


class MigrationTests(unittest.TestCase):
    def test_yaml_on_is_not_boolean(self):
        self.assertIn('on',m.load_yaml('on:\n  push:\npermissions:\n  contents: read\n'))
    def test_yaml_real_booleans_preserved(self):
        self.assertIs(m.load_yaml('concurrency:\n  cancel-in-progress: true\n')['concurrency']['cancel-in-progress'],True)
    def test_pc_only_duplicate_discovery_modules_removed(self):
        cfg={'on':{'pull_request':None}, 'jobs':{'control':{'steps':[
            {'name':'duplicates','run':'python3 -m unittest tests.harness.test_a tests.harness.test_b'},
            {'name':'nonduplicate','run':'python3 -m unittest tests.network.test_c'},
            {'name':'sideeffect','run':'python3 -m unittest tests.harness.test_d\necho important'},
            {'name':'all','run':"python3 -m unittest discover -s tests/harness -p 'test_*.py' -v"}]}}}
        out,receipt=m.transform({m.PC:m.dump_yaml(cfg)})
        steps=m.load_yaml(out[m.PC])['jobs']['control']['steps']
        self.assertEqual([s['name'] for s in steps],['nonduplicate','sideeffect','all'])
        self.assertEqual(receipt['notes'][0]['project_control_duplicate_module_calls_removed'],2)
    def test_no_discovery_no_removal(self):
        cfg={'jobs':{'x':{'steps':[{'run':'python3 -m unittest tests.harness.test_a'}]}}}
        out,_=m.transform({m.PC:m.dump_yaml(cfg)})
        self.assertEqual(len(m.load_yaml(out[m.PC])['jobs']['x']['steps']),1)
    def test_live_docs_and_pr_scoped_concurrency(self):
        cfg={'on':{'pull_request':{'branches':['main']}},'jobs':{}}
        out,_=m.transform({m.LIVE:m.dump_yaml(cfg)})
        value=m.load_yaml(out[m.LIVE])
        self.assertIn('docs/**',value['on']['pull_request']['paths-ignore'])
        self.assertIn('github.event.pull_request.number',value['concurrency']['group'])
        self.assertEqual(value['on']['pull_request']['branches'],['main'])
    def test_live_existing_positive_paths_preserved(self):
        cfg={'on':{'pull_request':{'paths':['scripts/**']}},'jobs':{}}
        out,_=m.transform({m.LIVE:m.dump_yaml(cfg)})
        pr=m.load_yaml(out[m.LIVE])['on']['pull_request']
        self.assertEqual(pr,{'paths':['scripts/**']})
    def test_union_retains_jobs_and_manual_history(self):
        files={m.ECO[0]:workflow(['a']),m.ECO[1]:workflow(['a','b'])}
        out,_=m.transform(files)
        self.assertEqual(m.load_yaml(out[m.ECO[0]])['on'],{'workflow_dispatch':None})
        self.assertEqual(m.load_yaml(out.get(m.ECO[1], files[m.ECO[1]]))['jobs'],m.load_yaml(files[m.ECO[1]])['jobs'])
    def test_union_preserves_missing_scenario(self):
        files={m.ECO[0]:workflow(['a','unique']),m.ECO[1]:workflow(['a','b'])}
        out,receipt=m.transform(files)
        self.assertNotIn(m.ECO[0],out)
        self.assertNotIn(m.ECO[1],out)
        self.assertIn('RETAINED_ORIGINAL',json.dumps(receipt))
    def test_different_engine_is_not_deduplicated(self):
        files={m.ECO[0]:workflow(['a'],pin='b'*64),m.ECO[1]:workflow(['a','b'])}
        out,_=m.transform(files)
        self.assertNotIn(m.ECO[0],out)
    def test_different_env_is_not_deduplicated(self):
        files={m.ECO[0]:workflow(['a'],env={'MODE':'special'}),m.ECO[1]:workflow(['a','b'])}
        out,_=m.transform(files)
        self.assertNotIn(m.ECO[0],out)
    def test_different_flags_are_not_deduplicated(self):
        old=workflow(['a']).replace('--headless --path','--headless --fixed-fps 30 --path')
        out,_=m.transform({m.ECO[0]:old,m.ECO[1]:workflow(['a','b'])})
        self.assertNotIn(m.ECO[0],out)
    def test_missing_pass_marker_blocks_union(self):
        old=workflow(['a']).replace('ECO_ARCH2_A PASS','ECO_ARCH2_SPECIAL PASS')
        out,_=m.transform({m.ECO[0]:old,m.ECO[1]:workflow(['a','b'])})
        self.assertNotIn(m.ECO[0],out)
    def test_docs_keep_original_contents(self):
        out,_=m.transform({'AGENTS.md':'# Existing\nPreserve me\n'})
        self.assertTrue(out['AGENTS.md'].endswith('# Existing\nPreserve me\n'))
    def test_transform_is_idempotent(self):
        files={m.ECO[0]:workflow(['a']),m.ECO[1]:workflow(['a','b']), 'AGENTS.md':'# Existing\n'}
        out,_=m.transform(files); files.update(out)
        again,_=m.transform(files)
        self.assertEqual(again,{})
    def test_existing_risk_contract_not_mutated(self):
        path='config/control/harness/risk-policy.v1.json'
        out,_=m.transform({path:'{"keep":"all roles"}'})
        self.assertNotIn(path,out)
    def test_continuation_advice_preserves_gates(self):
        text='from .mission import mission_from_state\ndef build(work_order,state):\n    mission = mission_from_state(state)\n    if state["blocked"]: raise ValueError("BLOCKED")\n    return mission\n'
        out,_=m.transform({m.CONTINUATION:text})
        self.assertIn('review_execution_plan',out[m.CONTINUATION])
        self.assertIn('if state["blocked"]: raise ValueError("BLOCKED")',out[m.CONTINUATION])
        compile(out[m.CONTINUATION],m.CONTINUATION,'exec')
    def test_unknown_legacy_continuation_preserved(self):
        out,receipt=m.transform({m.CONTINUATION:'legacy = True\n'})
        self.assertNotIn(m.CONTINUATION,out)
        self.assertIn('LEGACY_SHAPE',json.dumps(receipt))
    def test_added_module_conservative_for_unknown_risk(self):
        ns={}; exec(m.MODULE_TEXT,ns)
        for risk in ['HIGH','CRITICAL','UNKNOWN','low','']:
            plan=ns['execution_plan']({'risk_class':risk,'required_review_roles':['IMPLEMENTER','VERIFIER']})
            self.assertFalse(plan['same_independent_actor_may_cover_reviewer_and_verifier'])
            self.assertFalse(plan['implementer_self_acceptance_allowed'])
    def test_low_medium_may_batch_but_do_not_remove_roles(self):
        ns={}; exec(m.MODULE_TEXT,ns)
        for risk in ['LOW','MEDIUM']:
            wo={'risk_class':risk,'required_review_roles':['IMPLEMENTER','REVIEWER','VERIFIER']}
            saved=json.dumps(wo,sort_keys=True)
            plan=ns['execution_plan'](wo)
            self.assertTrue(plan['same_independent_actor_may_cover_reviewer_and_verifier'])
            self.assertEqual(json.dumps(wo,sort_keys=True),saved)
    def test_explicit_independent_execution_preserved(self):
        ns={}; exec(m.MODULE_TEXT,ns)
        for key in ['independent_execution_required','separate_machine_required','human_review_required']:
            wo={'risk_class':'MEDIUM','required_review_roles':['IMPLEMENTER','VERIFIER'],key:True}
            self.assertFalse(ns['execution_plan'](wo)['same_independent_actor_may_cover_reviewer_and_verifier'])
    def test_malformed_roles_do_not_enable_batch(self):
        ns={}; exec(m.MODULE_TEXT,ns)
        for roles in [[], 'VERIFIER', ['IMPLEMENTER','DIRECTOR'], [{}], [None]]:
            self.assertFalse(ns['execution_plan']({'risk_class':'MEDIUM','required_review_roles':roles})['same_independent_actor_may_cover_reviewer_and_verifier'])
    def test_branch_plan_preserves_parent_and_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def g(*args): return m.git(*args,cwd=root)
            g('init'); g('config','user.name','Test');g('config','user.email','test@example.invalid')
            (root/'runtime.gd').write_text('unchanged\n')
            g('add','.');g('commit','-m','base'); parent=g('rev-parse','HEAD')
            g('update-ref','refs/remotes/origin/main',parent)
            output=root/'receipt.json'; report=m.plan_branches(root,output)
            row=report['rows'][0]
            self.assertEqual(g('rev-parse',row['after']+'^'),parent)
            self.assertEqual(g('rev-parse',parent+':runtime.gd'),g('rev-parse',row['after']+':runtime.gd'))
            self.assertEqual(g('rev-parse','refs/remotes/origin/main'),parent)
            self.assertEqual(row['status'],'PREPARED_NOT_PUBLISHED')
    def test_publish_has_no_force_or_history_rewrite(self):
        import inspect
        text=inspect.getsource(m.publish)
        self.assertNotIn("'--force'",text)
        self.assertNotIn("'--force-with-lease'",text)
        self.assertIn('REMOTE_MOVED_NOT_UPDATED',text)

if __name__=='__main__': unittest.main()
