"""R3C3 R2.1 frame-paced client presentation contracts (source-only).

These tests cannot prove GUI frame thresholds; pinned real Godot runtime and
real two-client traces remain mandatory before performance acceptance.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

WORLD=read("scripts/world/earth/procedural_earth_world.gd")
PLACE=read("scripts/world/vegetation/earth_placement_system.gd")
APP=read("scripts/app/earth_app.gd")
HARNESS=read("tools/net_smooth1/run_net_smooth1.py")
TEST=read("tests/runtime/test_net_smooth1_r42_r3c21_frame_paced_visual.gd")


def method(s, name):
    m = re.search(r"^func " + re.escape(name) + r"\(", s, re.M)
    if not m:
        raise ValueError("missing " + name)
    n = re.search(r"^func ", s[m.end():], re.M)
    return s[m.start():m.end()+n.start() if n else len(s)]


class R3C21Source(unittest.TestCase):
    def test_original_r2_publication_unchanged_by_default(self):
        setup = method(WORLD, "setup")
        self.assertIn("r3c21_frame_paced_presentation: bool = false", setup)
        self.assertIn("r3c3_staged_geometry and r3c21_frame_paced_presentation", setup)
        commit = method(PLACE, "commit_staged_generation")
        self.assertIn("if _r3c21_pre_attach_enabled:", commit)
        self.assertIn("_clear_instances()", commit)
        self.assertIn("instance.visible = true", commit)
        self.assertIn("add_child(instance)", commit)
        self.assertIn("R3C3R2_DOUBLE_COMMIT_SAME_REGION", commit)

    def test_only_client_owns_frame_paced_option(self):
        self.assertIn('runtime_role == "game-client"', APP)
        self.assertIn('DWS_NET_R3C21_FRAME_PACED_PRESENTATION', APP)
        self.assertIn("earth_world.setup(logger, staged_client_earth, frame_paced_visuals)", APP)
        self.assertIn("--r3c21-frame-paced-presentation", HARNESS)
        self.assertIn("if role in ('a','b') and args.r3c21_frame_paced_presentation:", HARNESS)
        self.assertIn("if args.r3c21_frame_paced_presentation and not args.r3c3_staged_earth:", HARNESS)
        self.assertNotIn('DWS_NET_R3C21_FRAME_PACED_PRESENTATION', read(
            "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"))

    def test_hidden_candidate_registration_one_per_frame(self):
        m = method(PLACE, "advance_staged_preattach")
        self.assertIn("max_nodes: int = 1", m)
        self.assertIn("_r3c21_preattached_count", m)
        self.assertIn("candidate.visible = false", m)
        self.assertIn("add_child(candidate)", m)
        self.assertIn("R3C21_STALE_PREATTACH_TOKEN", m)
        self.assertIn("R3C21_PREATTACH_BEFORE_UPLOAD_COMPLETE", m)
        self.assertIn("R3C21_PHASE_PREATTACHED", m)
        self.assertNotIn("instance.visible = true", m)
        self.assertNotIn("commit_staged_generation(", m)

    def test_commit_fails_closed_without_attached_full_set(self):
        m = method(PLACE, "commit_staged_generation")
        self.assertIn("R3C21_PREATTACH_NOT_COMPLETE", m)
        self.assertIn('R3C21_INCOMPLETE_HIDDEN_CANDIDATE', m)
        self.assertIn("if instance.get_parent() != self or instance.visible:", m)
        self.assertIn("_r3c21_retired_nodes.append(child)", m)
        self.assertIn("_rebuild_live_lists_from_children()", m)
        self.assertIn("_r3c3r2_phase = R3C3R2_PHASE_COMMITTED", m)

    def test_abort_invisible_candidates_and_drain_old_gpu(self):
        cancel=method(PLACE,"cancel_staged_generation")
        self.assertIn("instance.get_parent() == self", cancel)
        self.assertIn("remove_child(instance)",cancel)
        self.assertIn("instance.queue_free()",cancel)
        drain=method(PLACE,"drain_retired_visuals")
        self.assertIn("max_nodes: int = 1",drain)
        self.assertIn("_r3c21_retired_nodes.pop_front()",drain)
        self.assertIn("old.queue_free()",drain)
        self.assertNotIn("for child in get_children()",drain)

    def test_active_target_recenter_stable_until_out_of_region(self):
        m=method(WORLD,"update_for_view")
        self.assertIn("get_surface_point(_r3c3_requested_direction)",m)
        self.assertIn("(target_surface - pending_surface).length() <= local_recenter_distance_m",m)
        self.assertIn("_r3c21_last_recenter_dedup += 1",m)
        self.assertIn("prepare_surface_region(target_direction, false)",m)
        self.assertIn("rebuild_cooldown_sec = 0.75",m)
        self.assertIn("_r3c21_frame_paced_enabled",m)

    def test_cpu_time_budget_adapts_to_bad_previous_frame(self):
        p=method(WORLD,"_process")
        self.assertIn("if delta >= 0.025:",p)
        self.assertIn("cpu_budget = 600",p)
        self.assertIn("elif delta >= 0.020:",p)
        self.assertIn("cpu_budget = 1200",p)
        self.assertIn("R3C3R2_CPU_BUDGET_FIRST_REGION_US",p)
        self.assertIn("placement_system.drain_retired_visuals(1)",p)
        self.assertIn('SmoothTrace.emit("r3c21_first_visible_frame"',p)
        self.assertIn("R3C3_DEFAULT_MAX_STEPS_PER_FRAME", WORLD)

    def test_real_godot_r21_suite_has_stale_token_and_exact_parity(self):
        self.assertIn('EarthWorld.new()',TEST)
        self.assertIn('candidate.setup(null, true, true)',TEST)
        self.assertIn('Preattach.R3C21_PHASE_PREATTACH',TEST)
        self.assertIn('not child.visible',TEST)
        self.assertIn('wrong_token',TEST)
        self.assertIn('candidate.prepare_surface_region(direction_c, false)',TEST)
        self.assertIn('committed_transform_sources ==',TEST)
        self.assertIn('R3C21_WATCHDOG_OR_SCRIPT_ERROR',TEST)
        self.assertIn('quit(0 if failures.is_empty() else 1)',TEST)


if __name__ == "__main__":
    unittest.main()
