from __future__ import annotations

import copy, json, sys, unittest
from pathlib import Path
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts' / 'control'))
import project_control as pc
R2 = 'GLOBAL-P0-2026-08-10-R2'
R3 = 'GLOBAL-P0-2026-08-12-R3-REFRESH-R1'
COMMIT = 'ce40dd075045078ed70924f8d5a1011eb3eff03d'
BLOB = '0cebf594ac7900292318d7533e4439cc7f3764d6'
PATH = 'config/control/architecture-ownership.v1.json'
BRANCH = 'feature/t1b-composition-failure-recovery'
PASSPORT = 'config/control/branches/t.json'
POLICY = {'passport_ownership_compatibility': {'mode': 'EXPLICIT_PER_PROGRAM_HISTORICAL_OWNERSHIP_TRANSITIONS', 'central_registry_field': 'historical_passport_ownership_transitions', 'architecture_compatibility_prerequisite': 'EXPLICIT_HISTORICAL_IDENTITY_ALLOWED', 'historical_canonical_ownership_source': {'architecture_revision': R2, 'commit_sha': COMMIT, 'path': PATH, 'blob_sha': BLOB}, 'required_transition_fields': ['program', 'architecture_revision', 'foundation', 'historical_owner', 'canonical_owner']}}
TRANS = [{'program': 'T', 'architecture_revision': R2, 'foundation': 'WORLD_QUERY_FABRIC', 'historical_owner': 'P1_FUTURE', 'canonical_owner': 'WQ'}, {'program': 'T', 'architecture_revision': R2, 'foundation': 'WORLD_TRANSACTION_MODEL', 'historical_owner': 'P0', 'canonical_owner': 'WT'}]
HIST = {'architecture_revision': R2, 'foundations': {'WORLD_QUERY_FABRIC': {'owner': 'P1_FUTURE'}, 'WORLD_TRANSACTION_MODEL': {'owner': 'P0'}, 'OTHER': {'owner': 'OLD'}}}
CURR = {'architecture_revision': R3, 'foundations': {'WORLD_QUERY_FABRIC': {'owner': 'WQ'}, 'WORLD_TRANSACTION_MODEL': {'owner': 'WT'}, 'OTHER': {'owner': 'NEW'}}}
PASSPORT_DOC = {'program': 'T', 'branch': BRANCH, 'architecture_revision': R2}


def base_result(extra=None, architecture=True):
    findings = [{'level': 'RED', 'code': 'FOUNDATION_OWNERSHIP_CONFLICT', 'detail': 'WORLD_QUERY_FABRIC: claimed=P1_FUTURE, canonical=WQ'}, {'level': 'RED', 'code': 'FOUNDATION_OWNERSHIP_CONFLICT', 'detail': 'WORLD_TRANSACTION_MODEL: claimed=P0, canonical=WT'}]
    findings.extend(extra or [])
    r = {'program': 'T', 'branch': BRANCH, 'passport_loaded': True, 'health_declared': 'GREEN', 'health': 'RED', 'findings': findings, 'ownership_claims': [{'foundation': 'WORLD_QUERY_FABRIC', 'claimed_owner': 'P1_FUTURE'}, {'foundation': 'WORLD_TRANSACTION_MODEL', 'claimed_owner': 'P0'}]}
    r['architecture_compatibility'] = {'compatible': architecture, 'mode': 'EXPLICIT_HISTORICAL_IDENTITY_ALLOWED' if architecture else 'STRICT_MISMATCH_HISTORICAL_IDENTITY_NOT_PINNED', 'matching_historical_identities': 1 if architecture else 0}
    return r


class HistoricalOwnershipCompatibilityTests(unittest.TestCase):

    def run_case(self, central=None, policy=None, current=None, hist=None, result=None, git_overrides=None, passport=None):
        central = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': copy.deepcopy(TRANS)} if central is None else central
        policy = copy.deepcopy(POLICY if policy is None else policy)
        current = copy.deepcopy(CURR if current is None else current)
        hist = copy.deepcopy(HIST if hist is None else hist)
        result = copy.deepcopy(base_result() if result is None else result)
        passport = copy.deepcopy(PASSPORT_DOC if passport is None else passport)

        def git(*args, allow_fail=False):
            key = args
            if git_overrides and key in git_overrides:
                return git_overrides[key]
            if key == ('rev-parse', '--verify', f'{COMMIT}^{{commit}}'):
                return COMMIT
            if key == ('rev-parse', '--verify', f'{COMMIT}:{PATH}'):
                return BLOB
            if key == ('show', f'{COMMIT}:{PATH}'):
                return json.dumps(hist)
            return ''
        with patch.object(pc, '_ARCHITECTURE_AUDIT_PROGRAM', return_value=result), patch.object(pc._core, 'load_branch_json', return_value=passport), patch.object(pc._core, 'git', side_effect=git):
            return pc.audit_program('T', copy.deepcopy(central), {'architecture_revision': R3}, policy, current)

    def conflicts(self, r):
        return [f for f in r['findings'] if f.get('code') == 'FOUNDATION_OWNERSHIP_CONFLICT']

    def test_a_exact(self):
        r = self.run_case()
        self.assertEqual([], self.conflicts(r))
        self.assertEqual('GREEN', r['health'])
        self.assertEqual(2, len(r['ownership_compatibility']['authorized_conflicts']))

    def test_b_no_list(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT}
        r = self.run_case(central=c)
        self.assertEqual(2, len(self.conflicts(r)))

    def test_c_only_wq(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [TRANS[0]]}
        r = self.run_case(central=c)
        self.assertEqual(['WORLD_TRANSACTION_MODEL: claimed=P0, canonical=WT'], [f['detail'] for f in self.conflicts(r)])

    def test_d_only_wt(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [TRANS[1]]}
        r = self.run_case(central=c)
        self.assertEqual(['WORLD_QUERY_FABRIC: claimed=P1_FUTURE, canonical=WQ'], [f['detail'] for f in self.conflicts(r)])

    def test_e_wrong_hist_owner(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(TRANS[0], historical_owner='P0'), TRANS[1]]}
        self.assertTrue(self.conflicts(self.run_case(central=c)))

    def test_f_wrong_canonical(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(TRANS[0], canonical_owner='X'), TRANS[1]]}
        self.assertTrue(self.conflicts(self.run_case(central=c)))

    def test_g_wrong_foundation(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(TRANS[0], foundation='OTHER'), TRANS[1]]}
        self.assertTrue(self.conflicts(self.run_case(central=c)))

    def test_h_wrong_program(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(TRANS[0], program='G'), TRANS[1]]}
        self.assertTrue(self.conflicts(self.run_case(central=c)))

    def test_i_duplicate(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [TRANS[0], TRANS[0], TRANS[1]]}
        r = self.run_case(central=c)
        self.assertEqual(2, len(self.conflicts(r)))
        self.assertEqual('OWNERSHIP_TRANSITION_AMBIGUOUS', r['ownership_compatibility']['reason'])

    def test_j_missing_policy(self):
        self.assertEqual(2, len(self.conflicts(self.run_case(policy={}))))

    def test_j2_wrong_mode_fails_closed(self):
        p = copy.deepcopy(POLICY)
        p['passport_ownership_compatibility']['mode'] = 'RELAXED'
        self.assertEqual(2, len(self.conflicts(self.run_case(policy=p))))

    def test_j3_malformed_transition_record_fails_closed(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [{'program': 'T'}]}
        r = self.run_case(central=c)
        self.assertEqual(2, len(self.conflicts(r)))
        self.assertEqual('OWNERSHIP_TRANSITION_RECORD_MALFORMED', r['ownership_compatibility']['reason'])

    def test_j4_historical_source_path_missing_fails_closed(self):
        o = {('show', f'{COMMIT}:{PATH}'): ''}
        r = self.run_case(git_overrides=o)
        self.assertEqual(2, len(self.conflicts(r)))
        self.assertEqual('HISTORICAL_OWNERSHIP_SOURCE_PATH_MISSING', r['ownership_compatibility']['reason'])

    def test_k_bad_registry_field(self):
        for v in (None, 7, 'wrong'):
            p = copy.deepcopy(POLICY)
            p['passport_ownership_compatibility']['central_registry_field'] = v
            self.assertEqual(2, len(self.conflicts(self.run_case(policy=p))))

    def test_l_wrong_source_commit(self):
        p = copy.deepcopy(POLICY)
        p['passport_ownership_compatibility']['historical_canonical_ownership_source']['commit_sha'] = '1' * 40
        self.assertEqual(2, len(self.conflicts(self.run_case(policy=p))))

    def test_m_wrong_source_path(self):
        p = copy.deepcopy(POLICY)
        p['passport_ownership_compatibility']['historical_canonical_ownership_source']['path'] = 'x'
        self.assertEqual(2, len(self.conflicts(self.run_case(policy=p))))

    def test_n_wrong_source_blob(self):
        p = copy.deepcopy(POLICY)
        p['passport_ownership_compatibility']['historical_canonical_ownership_source']['blob_sha'] = '2' * 40
        self.assertEqual(2, len(self.conflicts(self.run_case(policy=p))))

    def test_o_historical_owner_source_mismatch(self):
        h = copy.deepcopy(HIST)
        h['foundations']['WORLD_QUERY_FABRIC']['owner'] = 'P0'
        self.assertTrue(self.conflicts(self.run_case(hist=h)))

    def test_p_current_owner_mismatch(self):
        c = copy.deepcopy(CURR)
        c['foundations']['WORLD_QUERY_FABRIC']['owner'] = 'WRONG'
        self.assertTrue(self.conflicts(self.run_case(current=c)))

    def test_q_arch_identity_absent(self):
        r = base_result(architecture=False)
        out = self.run_case(result=r)
        self.assertEqual(r, out)
        self.assertNotIn('ownership_compatibility', out)

    def test_r_commit_missing(self):
        o = {('rev-parse', '--verify', f'{COMMIT}^{{commit}}'): ''}
        self.assertEqual(2, len(self.conflicts(self.run_case(git_overrides=o))))

    def test_s_blob_moved(self):
        o = {('rev-parse', '--verify', f'{COMMIT}:{PATH}'): '9' * 40}
        self.assertEqual(2, len(self.conflicts(self.run_case(git_overrides=o))))

    def test_t_other_program(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(x, program='G') for x in TRANS]}
        self.assertEqual(2, len(self.conflicts(self.run_case(central=c))))

    def test_u_current_canonical_arch_never_activates(self):
        r = base_result()
        r['architecture_compatibility'] = {'compatible': True, 'mode': 'EXACT_CANONICAL_REVISION', 'matching_historical_identities': 0}
        out = self.run_case(result=r, passport=dict(PASSPORT_DOC, architecture_revision=R3))
        self.assertEqual(2, len(self.conflicts(out)))
        self.assertNotIn('ownership_compatibility', out)

    def test_v_heuristics_irrelevant(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'role': 'MAGIC', 'current_stage': 'ACCEPTED', 'stage_status': 'PASS', 'blockers': []}
        self.assertEqual(2, len(self.conflicts(self.run_case(central=c))))

    def test_w_unrelated_conflict(self):
        r = base_result(extra=[{'level': 'RED', 'code': 'FOUNDATION_OWNERSHIP_CONFLICT', 'detail': 'OTHER: claimed=OLD, canonical=NEW'}])
        r['ownership_claims'].append({'foundation': 'OTHER', 'claimed_owner': 'OLD'})
        out = self.run_case(result=r)
        self.assertEqual(['OTHER: claimed=OLD, canonical=NEW'], [f['detail'] for f in self.conflicts(out)])

    def test_x_other_red_survives(self):
        r = base_result(extra=[{'level': 'RED', 'code': 'CRITICAL_DEPENDENCY_DRIFT', 'detail': 'x'}])
        out = self.run_case(result=r)
        self.assertEqual('RED', out['health'])
        self.assertTrue(any((f['code'] == 'CRITICAL_DEPENDENCY_DRIFT' for f in out['findings'])))

    def test_wildcard_malformed(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': [dict(TRANS[0], foundation='*'), TRANS[1]]}
        r = self.run_case(central=c)
        self.assertEqual(2, len(self.conflicts(r)))
        self.assertEqual('OWNERSHIP_TRANSITION_RECORD_MALFORMED', r['ownership_compatibility']['reason'])

    def test_nonlist_malformed(self):
        c = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': 'bad'}
        r = self.run_case(central=c)
        self.assertEqual(2, len(self.conflicts(r)))

    def test_exact_metadata(self):
        m = self.run_case()['ownership_compatibility']
        self.assertEqual(COMMIT, m['historical_source_commit_sha'])
        self.assertEqual(BLOB, m['historical_source_blob_sha'])
        self.assertEqual([{'foundation': 'WORLD_QUERY_FABRIC', 'historical_owner': 'P1_FUTURE', 'canonical_owner': 'WQ'}, {'foundation': 'WORLD_TRANSACTION_MODEL', 'historical_owner': 'P0', 'canonical_owner': 'WT'}], m['authorized_conflicts'])

    def _synthetic_six(self, transitions=None, current=None, t_result=None):
        transitions = copy.deepcopy(TRANS if transitions is None else transitions)
        current = copy.deepcopy(CURR if current is None else current)
        programs = {}
        for key in ('G', 'ECO', 'T', 'CH', 'DOCTRINE', 'NX'):
            if key == 'T':
                central = {'program': 'T', 'branch': BRANCH, 'passport_path': PASSPORT, 'historical_passport_ownership_transitions': transitions}
                programs[key] = self.run_case(central=central, current=current, result=t_result)
            else:
                programs[key] = {'program': key, 'health': 'GREEN', 'blocks_global_progress': key != 'ECO', 'architecture_compatibility': {'compatible': True, 'mode': 'EXPLICIT_HISTORICAL_IDENTITY_ALLOWED', 'matching_historical_identities': 1}, 'findings': []}
        blocking = [r for r in programs.values() if r.get('blocks_global_progress', True)]
        standard = 'RED' if any((r.get('health') == 'RED' for r in blocking)) else 'NON_RED'
        return (programs, standard)

    def test_y_synthetic_proposed_r3_six_passports_non_red(self):
        programs, standard = self._synthetic_six()
        t = programs['T']
        self.assertEqual('NON_RED', standard)
        self.assertNotEqual('RED', t['health'])
        self.assertEqual('EXPLICIT_HISTORICAL_IDENTITY_ALLOWED', t['architecture_compatibility']['mode'])
        self.assertEqual(1, t['architecture_compatibility']['matching_historical_identities'])
        self.assertEqual(2, len(t['ownership_compatibility']['authorized_conflicts']))
        self.assertFalse(self.conflicts(t))

    def test_z_remove_one_transition_restores_t_red(self):
        programs, standard = self._synthetic_six(transitions=[TRANS[0]])
        self.assertEqual('RED', programs['T']['health'])
        self.assertEqual('RED', standard)

    def test_aa_change_one_target_r3_owner_restores_t_red(self):
        cur = copy.deepcopy(CURR)
        cur['foundations']['WORLD_QUERY_FABRIC']['owner'] = 'WQ_CHANGED'
        programs, standard = self._synthetic_six(current=cur)
        self.assertEqual('RED', programs['T']['health'])
        self.assertEqual('RED', standard)

    def test_ab_duplicate_transition_restores_t_red(self):
        programs, standard = self._synthetic_six(transitions=[TRANS[0], TRANS[0], TRANS[1]])
        self.assertEqual('RED', programs['T']['health'])
        self.assertEqual('RED', standard)

    def test_ac_refreshed_r2_identity_never_activates(self):
        r = base_result(architecture=False)
        r['architecture_compatibility'] = {'compatible': False, 'mode': 'STRICT_MISMATCH_HISTORICAL_IDENTITY_NOT_PINNED', 'matching_historical_identities': 0, 'observed_head_sha': '3' * 40, 'observed_passport_blob_sha': '4' * 40}
        out = self.run_case(result=r)
        self.assertEqual(r, out)
        self.assertNotIn('ownership_compatibility', out)


if __name__ == '__main__':
    unittest.main()
