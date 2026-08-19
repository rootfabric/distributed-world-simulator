from __future__ import annotations
import json
import unittest
from pathlib import Path

class I23ContractTests(unittest.TestCase):
    def test_i2_3_inc_16_machine_contract_matches_candidate(self):
        contract_path = Path(__file__).resolve().parents[4] / 'config/research/seamless/i2/i2-3-incarnation-replacement-contract.v1.json'
        contract = json.loads(contract_path.read_text(encoding='utf-8'))
        self.assertEqual('SM1-I2.3', contract['checkpoint'])
        self.assertEqual('c09a53b5c7aba10c091e8cfb2ea8307d5f6b39da', contract['accepted_i2_2_base'])
        self.assertEqual('SM1_I2_2_FRESH_INDEPENDENT_REVIEW_PASS', contract['accepted_i2_2_review'])
        self.assertEqual('ACCEPTED_I2_1_DIRECTORY_COMPARE_AND_SWAP_ONLY', contract['canonical_mutation_path'])
        self.assertFalse(contract['production_activation'])
        self.assertTrue(contract['donor_only'])
        self.assertFalse(contract['ambiguous_response_contract']['second_rotation_on_exact_retry_allowed'])

if __name__ == '__main__':
    unittest.main()
