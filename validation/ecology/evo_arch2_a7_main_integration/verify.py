#!/usr/bin/env python3
"""Fail-closed verifier for the fresh current-main A7 convergence candidate."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE_MAIN = "7dfc68ab5a1e90254a1b7039807f275b5da04eef"
ACCEPTED_REF = "refs/remotes/origin/acceptance/eco-evo-arch2-a7-r1"
ACCEPTED_A7 = "8eccf6304078bec3a3ccaa5860c5aab6ee311209"
ACCEPTED_TREE = "24e876b7377cb3e1e521f08ff9766331fe4e895a"
GODOT_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
PINNED_JSONSCHEMA = "4.25.1"
HARNESS_REPAIR_PATH = "tests/harness/test_v0_mvp_act0.py"
HARNESS_REPAIR_BLOB = "43db3ef992430802dab3b7c60b3bb7d2801205f0"
EXTERNAL_DEPS = {
    "scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd",
    "scripts/labs/ecology/evo_morphology_lab_v2_model.gd",
    "scripts/labs/ecology/evo_morphology_lab_v2_renderer.gd",
}
INTEGRATION_LOCAL_PATHS = {
    "config/ecology/evo-arch2-a7-main-integration-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION_R1_RU.md",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION_REPAIR_R1_RU.md",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION_REPAIR_R2_RU.md",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION_REPAIR_R3_RU.md",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION_REPAIR_R4_RU.md",
    "validation/ecology/evo_arch2_a7_main_integration/expected-transfer.v1.json",
    "validation/ecology/evo_arch2_a7_main_integration/verify.py",
}
GENERATED_RES_PREFIXES = ("artifacts/a7/",)
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|ERROR:|FAIL:")
RES_PATTERNS = [
    re.compile(r'(?:preload|load)\(\s*["\']res://([^"\']+)["\']\s*\)'),
    re.compile(r'path=["\']res://([^"\']+)["\']'),
]
RM = {11:9,12:29,13:13,14:21,15:12,16:10,17:13,18:12,19:10,20:12,21:8,22:13,
      23:16,25:11,26:11,27:13,28:12,29:9,30:7,32:12,33:17,34:19}
TRANSFER_PREFIXES = (
    "config/ecology/evo-arch2-a7-protocol.v1.json",
    "scripts/research/ecology/v2/",
    "scripts/labs/ecology/arch2_a7_",
    "scenes/labs/ecology/arch2_a7_",
    "tests/research/ecology/v2/",
    "validation/ecology/evo_arch2_a5/",
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def gp(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False)


def git(*args: str) -> str:
    p = gp(*args)
    if p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {p.stderr.strip()}")
    return p.stdout.strip()


def transferred(path: str) -> bool:
    return path in EXTERNAL_DEPS or any(path == p or path.startswith(p) for p in TRANSFER_PREFIXES)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", required=True, type=Path)
    ap.add_argument("--head", required=True)
    ap.add_argument("--tree", required=True)
    args = ap.parse_args()
    os.chdir(ROOT)
    out = ROOT / "artifacts/a7-main-integration/exact"
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    summary = {
        "subject_head": args.head,
        "subject_tree": args.tree,
        "base_main": BASE_MAIN,
        "accepted_transfer_ref": ACCEPTED_REF,
        "accepted_transfer_source": ACCEPTED_A7,
        "accepted_transfer_tree": ACCEPTED_TREE,
        "verdict": "FAIL",
        "checks": [],
        "repeat_pairs": [],
        "graphical_required": True,
        "main_owned_files_modified": [HARNESS_REPAIR_PATH],
        "unauthorized_main_owned_files_modified": False,
    }
    started = time.monotonic()

    def req(ok: bool, msg: str) -> None:
        if not ok:
            raise RuntimeError(msg)

    def run(name: str, cmd: list[str], marker: str = "", assertions: int = 0,
            timeout: int = 900, scan: bool = True) -> Path:
        log = out / f"{name}.log"
        with log.open("wb") as f:
            p = subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT,
                               timeout=timeout, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        req(p.returncode == 0 and (not scan or not ERRORS.search(text)) and (not marker or marker in text),
            f"{name}: exit={p.returncode} marker={marker!r}\n{text[-12000:]}")
        summary["checks"].append({"name": name, "result": "PASS", "exit_code": p.returncode,
                                  "assertions": assertions, "sha256": sha(log), "command": cmd})
        print(f"PASS {name} {marker}", flush=True)
        return log

    def gd(path: str, *extra: str) -> list[str]:
        return [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                "--script", "res://" + path, *extra]

    def twice(name: str, path: str, marker: str, n: int) -> None:
        a = run(name + "-1", gd(path), marker, n)
        b = run(name + "-2", gd(path), marker, n)
        req(a.read_bytes() == b.read_bytes(), "REPEAT_MISMATCH:" + name)
        summary["repeat_pairs"].append(name)

    try:
        req(shutil.which("xvfb-run") is not None, "XVFB_REQUIRED_FOR_INTEGRATION_GRAPHICS")
        req(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree,
            "EXACT_SUBJECT")
        req(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY")
        req(git("merge-base", BASE_MAIN, args.head) == BASE_MAIN, "NOT_CURRENT_MAIN_DESCENDANT")
        parents = git("rev-list", "--parents", "-n", "1", args.head).split()[1:]
        req(ACCEPTED_A7 not in parents, "RESEARCH_COMMIT_USED_AS_PARENT")

        req(gp("show-ref", "--verify", "--quiet", ACCEPTED_REF).returncode == 0,
            "ACCEPTED_REF_NOT_FETCHED")
        req(git("rev-parse", ACCEPTED_REF) == ACCEPTED_A7, "ACCEPTED_REF_HEAD_MISMATCH")
        req(git("rev-parse", ACCEPTED_REF + "^{tree}") == ACCEPTED_TREE, "ACCEPTED_REF_TREE_MISMATCH")
        req(gp("cat-file", "-e", ACCEPTED_A7 + "^{commit}").returncode == 0,
            "ACCEPTED_COMMIT_NOT_AVAILABLE")
        req(git("rev-parse", ACCEPTED_A7 + "^{tree}") == ACCEPTED_TREE,
            "ACCEPTED_COMMIT_TREE_MISMATCH")

        records = git("diff", "--name-status", BASE_MAIN, args.head).splitlines()
        req(bool(records), "EMPTY_DIFF")
        transfer_additions: list[str] = []
        integration_additions: list[str] = []
        modifications: list[str] = []
        forbidden = ("scripts/ecology/production/", "scripts/network/", "scripts/simulation/",
                     "config/control/", "config/architecture/")
        for rec in records:
            parts = rec.split("\t")
            req(len(parts) == 2, "UNSUPPORTED_DIFF_RECORD:" + rec)
            status, path = parts
            req(path != "project.godot" and not path.startswith(forbidden) and not path.startswith(".github/"),
                "MAIN_OWNERSHIP_VIOLATION:" + path)
            if status == "M":
                req(path == HARNESS_REPAIR_PATH, "UNAUTHORIZED_MODIFICATION:" + rec)
                modifications.append(path)
                continue
            req(status == "A", "NON_ADDITION_TRANSFER_CHANGE:" + rec)
            if path in INTEGRATION_LOCAL_PATHS:
                integration_additions.append(path)
                continue
            req(transferred(path), "OUT_OF_SCOPE_ADDITION:" + path)
            transfer_additions.append(path)

        req(modifications == [HARNESS_REPAIR_PATH], "HARNESS_REPAIR_PATH_SET_MISMATCH")
        req(set(integration_additions) == INTEGRATION_LOCAL_PATHS,
            "INTEGRATION_LOCAL_PATH_SET_MISMATCH")
        req(git("rev-parse", "HEAD:" + HARNESS_REPAIR_PATH) == HARNESS_REPAIR_BLOB,
            "HARNESS_REPAIR_BLOB_MISMATCH")
        req(gp("cat-file", "-e", BASE_MAIN + ":" + HARNESS_REPAIR_PATH).returncode == 0,
            "HARNESS_REPAIR_BASE_PATH_MISSING")
        req(bool(transfer_additions), "NO_TRANSFER_ADDITIONS")

        accepted_addition_objects = {}
        for path in transfer_additions:
            req(gp("cat-file", "-e", BASE_MAIN + ":" + path).returncode != 0,
                "TRANSFER_PATH_EXISTED_ON_MAIN:" + path)
            req(gp("cat-file", "-e", ACCEPTED_A7 + ":" + path).returncode == 0,
                "TRANSFER_PATH_MISSING_FROM_ACCEPTED_A7:" + path)
            head_obj = git("rev-parse", "HEAD:" + path)
            accepted_obj = git("rev-parse", ACCEPTED_A7 + ":" + path)
            req(head_obj == accepted_obj, "ACTUAL_TRANSFER_ADDITION_MISMATCH:" + path)
            accepted_addition_objects[path] = head_obj

        summary["transfer_additions"] = transfer_additions
        summary["integration_local_additions"] = integration_additions
        summary["bounded_modifications"] = modifications
        summary["actual_transfer_objects"] = accepted_addition_objects

        pins = json.loads((ROOT / "validation/ecology/evo_arch2_a7_main_integration/expected-transfer.v1.json").read_text())
        req(pins["base_main"] == BASE_MAIN and pins["accepted_ref"] == ACCEPTED_REF and
            pins["accepted_a7"] == ACCEPTED_A7 and pins["accepted_a7_tree"] == ACCEPTED_TREE,
            "TRANSFER_MANIFEST_IDENTITY")
        direct_objects = {}
        for path, want in {**pins["subtrees"], **pins["blobs"]}.items():
            head_obj = git("rev-parse", "HEAD:" + path)
            accepted_obj = git("rev-parse", ACCEPTED_A7 + ":" + path)
            req(head_obj == accepted_obj, "DIRECT_ACCEPTED_OBJECT_MISMATCH:" + path)
            req(head_obj == want, "REDUNDANT_PIN_MISMATCH:" + path)
            req(gp("cat-file", "-e", BASE_MAIN + ":" + path).returncode != 0,
                "TRANSFER_PATH_EXISTED_ON_MAIN:" + path)
            direct_objects[path] = head_obj
        req(set(pins["blobs"]).issuperset(EXTERNAL_DEPS), "EXTERNAL_DEPENDENCY_NOT_PINNED")
        summary["transfer_identity"] = "PASS_ALL_ACTUAL_ADDITIONS_DIRECT_ACCEPTED_REF"
        summary["base_absence_gate"] = "PASS_BY_GIT_EXIT_STATUS"
        summary["direct_accepted_objects"] = direct_objects

        sources = list((ROOT / "scripts/research/ecology/v2").glob("*.gd"))
        sources += list((ROOT / "scripts/labs/ecology").glob("arch2_a7_*.gd"))
        sources += list((ROOT / "tests/research/ecology/v2").glob("*.gd"))
        sources += list((ROOT / "validation/ecology/evo_arch2_a5").glob("*.gd"))
        sources += [ROOT / p for p in sorted(EXTERNAL_DEPS)]
        sources += [ROOT / "scenes/labs/ecology/arch2_a7_observatory.tscn"]
        refs = 0
        generated_refs = []
        for source in sources:
            text = source.read_text(encoding="utf-8-sig")
            for pattern in RES_PATTERNS:
                for m in pattern.finditer(text):
                    refs += 1
                    rel = m.group(1)
                    target = ROOT / rel
                    if target.exists():
                        continue
                    if any(rel.startswith(prefix) for prefix in GENERATED_RES_PREFIXES):
                        generated_refs.append({"source": source.relative_to(ROOT).as_posix(), "target": rel})
                        continue
                    req(False, f"TRANSITIVE_RES_PATH_MISSING:{source.relative_to(ROOT)}->{rel}")
        summary["res_path_closure"] = {"result": "PASS", "sources": len(sources),
                                       "references": refs, "generated_missing_allowed": generated_refs}

        try:
            jsonschema_version = importlib.metadata.version("jsonschema")
        except importlib.metadata.PackageNotFoundError as exc:
            raise RuntimeError("PINNED_JSONSCHEMA_MISSING") from exc
        req(jsonschema_version == PINNED_JSONSCHEMA,
            f"PINNED_JSONSCHEMA_VERSION_REQUIRED:{jsonschema_version}")
        summary["python_environment"] = {"executable": sys.executable,
                                         "jsonschema": jsonschema_version}

        args.godot = args.godot.resolve(strict=True)
        req(sha(args.godot) == GODOT_SHA, "GODOT_SHA")
        req(subprocess.check_output([str(args.godot), "--version"], text=True).strip() == GODOT_VERSION,
            "GODOT_VERSION")
        summary["godot"] = {"version": GODOT_VERSION, "sha256": GODOT_SHA}
        shutil.rmtree(ROOT / ".godot", ignore_errors=True)
        run("cold-import", [str(args.godot), "--headless", "--audio-driver", "Dummy", "--editor",
                            "--path", str(ROOT), "--import"], timeout=300)

        suites = [
            ("a7-protocol", "arch2_a7_protocol_guard.gd", "EVO_ARCH2_A7_PROTOCOL assertions=106 failed=0", 106),
            ("a7-core", "arch2_a7_acceptance.gd", "EVO_ARCH2_A7_EXACT assertions=158 failed=0", 158),
            ("a7-ui", "arch2_a7_ui.gd", "EVO_ARCH2_A7_UI assertions=30 failed=0", 30),
            ("a6-core", "arch2_a6_exact_acceptance.gd", "EVO_ARCH2_A6_EXACT assertions=77 failed=0", 77),
            ("a6-adversarial", "arch2_a6_adversarial.gd", "EVO_ARCH2_A6_ADVERSARIAL assertions=76 failed=0", 76),
            ("a6-lineage", "arch2_a6_lineage_energy.gd", "EVO_ARCH2_A6_LINEAGE assertions=11 failed=0", 11),
            ("a5-core", "arch2_a5_exact_acceptance.gd", "EVO_ARCH2_A5_EXACT assertions=69 failed=0", 69),
            ("a5-repairs", "arch2_a5_reviewer_repairs.gd", "EVO_ARCH2_A5_REPAIRS assertions=29 failed=0", 29),
            ("a4", "arch2_a4_exact_acceptance.gd", "EVO_ARCH2_A4_EXACT assertions=32 failed=0", 32),
            ("a03", "arch2_a03_exact_acceptance.gd", "EVO_ARCH2_A03_EXACT assertions=86 failed=0", 86),
        ]
        for name, file, marker, n in suites:
            twice(name, "tests/research/ecology/v2/" + file, marker, n)

        for stage in ("a7", "a6"):
            for rep in (1, 2):
                shutil.rmtree(ROOT / f"artifacts/{stage}/restart", ignore_errors=True)
                for phase in ("write", "read"):
                    run(f"{stage}-restart-{phase}-{rep}",
                        gd(f"tests/research/ecology/v2/arch2_{stage}_restart.gd", "--", phase),
                        f"EVO_ARCH2_{stage.upper()}_RESTART phase={phase} failed=0")
            for phase in ("write", "read"):
                a = out / f"{stage}-restart-{phase}-1.log"
                b = out / f"{stage}-restart-{phase}-2.log"
                req(a.read_bytes() == b.read_bytes(), f"RESTART_REPEAT:{stage}:{phase}")
                summary["repeat_pairs"].append(f"{stage}-restart-{phase}")

        for number, n in RM.items():
            files = list(ROOT.glob(f"validation/ecology/evo_arch2_a5/rm_a5_{number}_*.gd"))
            req(len(files) == 1, f"RM{number}_UNIQUE")
            twice(f"rm{number}", files[0].relative_to(ROOT).as_posix(),
                  f"EVO_ARCH2_A5_RM{number} assertions={n} failed=0", n)

        glog = run("a7-graphical",
            ["xvfb-run", "-a", "-s", "-screen 0 1600x1100x24", str(args.godot),
             "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--path", str(ROOT),
             "--script", "res://tests/research/ecology/v2/arch2_a7_ui.gd", "--", "--capture"],
            "EVO_ARCH2_A7_UI assertions=32 failed=0", 32, timeout=300)
        png = ROOT / "artifacts/a7/observatory.png"
        report = ROOT / "artifacts/a7/capture-sources.json"
        req(png.is_file() and report.is_file(), "GRAPHICAL_EVIDENCE_MISSING")
        summary.update(viewport_sha256=sha(png), viewport_source_report_sha256=sha(report),
                       graphical_log_sha256=sha(glog))

        hlog = run("main-harness-regression",
            [sys.executable, "-m", "unittest", "discover", "-s", "tests/harness",
             "-p", "test_*.py", "-v"], "OK", timeout=600, scan=False)
        htext = hlog.read_text(encoding="utf-8-sig", errors="replace")
        req("FAILED (" not in htext and "ERROR" not in htext, "HARNESS_REGRESSION_FAILURE")
        req("skipped=" not in htext, "HARNESS_SKIPS_NOT_ALLOWED")
        ran = re.search(r"Ran (\d+) tests", htext)
        req(ran is not None and int(ran.group(1)) >= 325, "HARNESS_DISCOVERY_INCOMPLETE")
        summary["harness"] = {"result": "PASS", "tests": int(ran.group(1)),
                              "jsonschema": jsonschema_version, "sha256": sha(hlog)}

        cdir = ROOT / "artifacts/a7-main-integration/control"
        cdir.mkdir(parents=True, exist_ok=True)
        controls = []
        for name, script, extra, artifact in [
            ("standard", "project_control.py", ["--no-fetch", "--no-fail-on-red"], "project-control-report.json"),
            ("directional", "project_control_directional_watch.py", ["--no-fail-on-red"], "directional-watch-report.json")]:
            log = run("control-" + name, [sys.executable, str(ROOT / "scripts/control" / script), *extra],
                      timeout=300, scan=False)
            src = ROOT / "artifacts/control" / artifact
            req(src.is_file(), "CONTROL_REPORT_MISSING:" + name)
            health = json.loads(src.read_text()).get("overall_health", "UNAVAILABLE")
            req(health != "RED", "CONTROL_RED:" + name)
            shutil.copyfile(src, cdir / artifact)
            shutil.copyfile(log, cdir / (name + ".log"))
            controls.append({"name": name, "overall_health": health,
                             "report_sha256": sha(src), "log_sha256": sha(log)})
        summary["control"] = controls

        req(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree,
            "FINAL_SUBJECT_MOVED")
        req(not git("status", "--porcelain", "--untracked-files=no"), "FINAL_TRACKED_DIRTY")
        summary["assertion_executions"] = sum(c["assertions"] for c in summary["checks"])
        summary["verdict"] = "PASS"
        print(f"SUBJECT_HEAD={args.head}\nSUBJECT_TREE={args.tree}\nVERDICT=PASS", flush=True)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        summary["error"] = str(exc)
        print("VERDICT=FAIL\n" + str(exc), file=sys.stderr, flush=True)
        return 1
    finally:
        summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
