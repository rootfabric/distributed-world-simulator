"""Negative acceptance cases; run with python -O -m unittest discover ... ."""
import unittest

from visual_seam_check import VisualCheck, require


class VisualVerdictTests(unittest.TestCase):
    def fixture(self):
        check = VisualCheck.__new__(VisualCheck)
        check.initial_roundtrips = 0
        check.state = lambda role: {'seam_roundtrips': 1}
        check.samples = []
        for phase, semantic in [('idle', 'idle'), ('walk', 'walk'), ('run', 'run'), ('stopped', 'idle')]:
            for index in range(3):
                check.samples.append({'phase': phase, 'visual': {'animation': {
                    'semantic': semantic, 'animation_playing': True, 'target_bone_count': 65,
                    'target_pose_sha256': str(index), 'animation_position_seconds': index / 10,
                }}})
        return check

    def test_guard_is_not_disabled_by_optimization(self):
        with self.assertRaisesRegex(AssertionError, 'negative'):
            require(False, 'negative')

    def test_frozen_target_pose_is_rejected(self):
        check = self.fixture()
        for row in check.samples:
            row['visual']['animation']['target_pose_sha256'] = 'same-pose'
        with self.assertRaisesRegex(AssertionError, 'FROZEN_TARGET_POSE'):
            check.validate_samples()

    def test_missing_locomotion_phase_is_rejected(self):
        check = self.fixture()
        check.samples = [row for row in check.samples if row['phase'] != 'run']
        with self.assertRaisesRegex(AssertionError, 'ANIMATION_SEMANTIC_MISSING run'):
            check.validate_samples()

    def test_missing_roundtrip_is_rejected(self):
        check = self.fixture()
        check.state = lambda role: {'seam_roundtrips': 0}
        with self.assertRaisesRegex(AssertionError, 'ROUNDTRIP_MISSING'):
            check.validate_samples()


if __name__ == '__main__':
    unittest.main()
