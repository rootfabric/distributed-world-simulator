"""R3C3 R1 opt-in Earth geometry architecture — source-only falsifiers.

Native Godot double numerical parity and GUI budgets are separate mandatory
gates. This does not assert or imply that staged vegetation/GPU upload is done.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

JOB = read("scripts/world/earth/earth_surface_build_job.gd")
WORLD = read("scripts/world/earth/procedural_earth_world.gd")
APP = read("scripts/app/earth_app.gd")
HARNESS = read("tools/net_smooth1/run_net_smooth1.py")
PARITY = read("tests/runtime/test_net_smooth1_r42_r3c3_staged_earth_geometry.gd")


def method(s: str, name: str) -> str:
    m = re.search(r"^func " + re.escape(name) + r"\(", s, re.M)
    if not m:
        raise ValueError("missing func " + name)
    n = re.search(r"^func ", s[m.end():], re.M)
    return s[m.start(): m.end()+n.start() if n else len(s)]


class R3C3R1SourceContract(unittest.TestCase):
    def test_pure_cpu_job_has_no_scene_gpu_worker_authority(self):
        self.assertIn("extends RefCounted", JOB)
        self.assertNotIn("extends Node", JOB)
        for token in ("ArrayMesh.new(", "MultiMesh.new(", "MeshInstance3D.new(",
                      "add_child(", "create_thread(", "Thread.new(", "RenderingServer.",
                      "OS.delay_msec(", "get_tree(", "authoritative_checkpoint",
                      "M6", "ack_delivered"):
            # The job comment may legitimately say M6; screen executable lines.
            code = "\n".join(x for x in JOB.splitlines() if not x.lstrip().startswith("#"))
            self.assertNotIn(token, code)
        self.assertIn("var _pipeline", JOB)

    def test_exact_legacy_geometry_functions_preserved(self):
        global_mesh = method(WORLD, "_build_global_mesh")
        local_mesh = method(WORLD, "_build_local_mesh")
        self.assertIn("pipeline.sample(direction, 2)", global_mesh)
        self.assertIn("pipeline.sample(direction, 0)", local_mesh)
        self.assertIn("var normals: PackedVector3Array = _build_normals", global_mesh)
        self.assertIn("var normals: PackedVector3Array = _build_normals", local_mesh)
        self.assertIn("placement_system.regenerate(", method(WORLD,"prepare_surface_region"))
        self.assertIn("global_earth.mesh = _build_global_mesh()", method(WORLD,"setup"))

    def test_client_only_optin_does_not_change_other_roles(self):
        self.assertIn('runtime_role == "game-client"', APP)
        self.assertIn('DWS_NET_R3C3_STAGED_EARTH', APP)
        # The stacked R2.1 product passes an independent client-only boolean.
        # Do NOT permit server/offline roles or a silently enabled R2.1.
        self.assertIn('earth_world.setup(logger, staged_client_earth, frame_paced_visuals)', APP)
        self.assertIn('DWS_NET_R3C21_FRAME_PACED_PRESENTATION', APP)
        self.assertIn('staged_client_earth\n\t\tand OS.get_environment(', APP)
        self.assertIn('r3c21_frame_paced_presentation: bool = false', WORLD)
        self.assertIn("var _r3c3_staged_geometry_enabled := false", WORLD)
        self.assertIn('if _r3c3_staged_geometry_enabled:', method(WORLD,"prepare_surface_region"))
        self.assertIn('--r3c3-staged-earth', HARNESS)
        self.assertIn("if role in ('a','b') and args.r3c3_staged_earth:", HARNESS)
        self.assertIn("r3c3_staged_earth=args.r3c3_staged_earth", HARNESS)

    def test_slice_is_bounded_and_in_process(self):
        proc = method(WORLD, "_process")
        self.assertIn("_r3c3_advance_job(", proc)
        self.assertIn("R3C3_DEFAULT_MAX_STEPS_PER_FRAME := 128", WORLD)
        self.assertIn("R3C3_DEFAULT_BUDGET_US := 2000", WORLD)
        adv = method(JOB, "advance")
        self.assertIn("done_units < max_units", adv)
        self.assertIn("Time.get_ticks_usec() - started_us >= budget_us", adv)
        self.assertNotIn("OS.delay_msec(", adv)
        self.assertIn("PHASE_NORMAL_TRIANGLES", adv)
        self.assertIn("PHASE_NORMAL_OUTPUT", adv)

    def test_initial_spawn_dedup_and_stale_region_fence(self):
        request = method(WORLD, "_r3c3_request_surface_region")
        self.assertIn("direction.is_equal_approx(_r3c3_requested_direction)", request)
        self.assertIn("_r3c3_stale_cancellations += 1", request)
        self.assertIn("_r3c3_token += 1", request)
        self.assertIn("_r3c3_requested_anchor = get_surface_point(direction)", request)
        self.assertIn("token != _r3c3_token", method(WORLD,"_r3c3_advance_job"))
        self.assertIn("job != _r3c3_local_job", method(WORLD,"_r3c3_advance_job"))
        self.assertIn("_r3c3_local_job == null", method(WORLD,"get_r3c3_staged_geometry_report"))
        self.assertIn("_r3c3_global_job == null", method(WORLD,"get_r3c3_staged_geometry_report"))

    def test_old_complete_mesh_untouched_until_full_ready(self):
        process = method(WORLD, "_r3c3_advance_job")
        self.assertIn("if not job.is_ready():", process)
        commit = method(WORLD, "_r3c3_commit_local_geometry")
        # R2: the geometry commit publishes NOTHING visual; the mesh is only
        # staged pending and vegetation moves to the staged CPU job.
        self.assertIn("job.get_arrays()", commit)
        self.assertNotIn("local_surface.mesh =", commit)
        self.assertNotIn("placement_system.regenerate(", commit)
        visual = method(WORLD, "_r3c3r2_commit_visual")
        # R2 atomic swap: vegetation commit precedes the terrain publication.
        self.assertLess(visual.index("commit_staged_generation("), visual.index("local_surface.mesh ="))
        self.assertIn("_r3c3_generation_committed = token", visual)
        self.assertIn("earth_rebuilt.emit(", visual)

    def test_explicit_r2_limits_and_no_false_perf_pass(self):
        report = method(WORLD, "get_r3c3_staged_geometry_report")
        # R2: staged vegetation/GPU upload are gated behind the same explicit
        # opt-in flag and must never claim an unconditional performance pass.
        self.assertIn('"vegetation_staged": _r3c3r2_enabled', report)
        self.assertIn('"gpu_upload_staged": _r3c3r2_enabled', report)
        self.assertIn('"visual_region_ready": (', report)
        self.assertIn('"last_slice_us"', report)
        self.assertIn('"last_commit_us"', report)
        self.assertNotIn("performance_pass", report.lower())

    def test_real_pinned_godot_parity_fixture_exists(self):
        self.assertIn("legacy.global_earth.mesh.surface_get_arrays(0)", PARITY)
        self.assertIn("staged.global_earth.mesh.surface_get_arrays(0)", PARITY)
        self.assertIn("legacy.local_surface.mesh.surface_get_arrays(0)", PARITY)
        self.assertIn("staged.local_surface.mesh.surface_get_arrays(0)", PARITY)
        self.assertIn("check(left == right", PARITY)
        self.assertIn("two", "two")  # avoid invoking pure-source fixture as a runtime result
        self.assertIn("TEST_WATCHDOG_SECONDS := 150.0", PARITY)
        self.assertIn('check(int(early.get("target_token", -1)) == 1', PARITY)
        self.assertIn("direction_b", PARITY)
        self.assertIn("direction_c", PARITY)
        self.assertIn("legacy.prepare_surface_region(direction_c, false)", PARITY)


if __name__ == "__main__":
    unittest.main()
