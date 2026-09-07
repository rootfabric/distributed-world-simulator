#!/usr/bin/env python3
"""Frozen-kernel HOLDOUT-R4 measurement and independent reference. Stdlib only.

Exit 0: all holdout obligations passed; 1: completed capability/physics FAIL;
2: invalid/incomplete protocol, missing provenance, transport or source mismatch.
A transport PASS and a correct safety rejection never imply generalization PASS.
"""
from __future__ import annotations

import argparse
import copy
from fractions import Fraction as F
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any

BASE = "fd6e83b35301d7a15e92c55939654f1f95729730"
TREE = "314330d717db059cd9b9db32c5d6150097e1f2c3"
FREEZE = "c73262adf568e2309fe5dd49a034812492566691"
ENGINE = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
E = {"material/rubber": 1e6, "material/steel": 2e11, "material/aluminum": 6.9e10, "material/copper": 1.1e11}
RHO = {"material/rubber": 1e13, "material/steel": 1.43e-7, "material/aluminum": 2.82e-8, "material/copper": 1.68e-8}
UNITS = {"m": 1.0, "cm": 0.01, "mm": 0.001}
FIELDS = {"id", "family", "expectation", "mechanical_nodes", "springs", "electrical_nodes", "resistors", "ports", "coupler_node", "coupling", "external_force_n", "length_unit", "material_mechanical", "material_electrical", "guard_fraction", "dt_s", "steps"}
ALLOWED = ("docs/research/FABRIC_HOLDOUT_R4_", "config/research/fabric-holdout-r4-", "scripts/research/fabric_holdout_r4/", "tests/research/fabric1/fabric_holdout_r4_", "validation/fabric-holdout-r4-", "RUN_FABRIC_HOLDOUT_R4_TESTS.sh", ".github/workflows/fabric-holdout-r4-linux-double.yml")
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Assertion failed|ERROR:|Segmentation fault", re.I)


def dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError(reason)


def number(value: Any) -> bool:
    return type(value) in (float, int) and math.isfinite(value)


def unique(rows: list, size: int) -> bool:
    return isinstance(rows, list) and bool(rows) and len(rows) <= 64 and all(isinstance(r, list) and len(r) == size and isinstance(r[0], str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", r[0]) for r in rows) and len({r[0] for r in rows}) == len(rows)


def validate_case(case: dict) -> None:
    require(isinstance(case, dict) and set(case) == FIELDS, "CASE_FIELDS")
    require(isinstance(case["id"], str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", case["id"]) is not None, "CASE_ID")
    require(isinstance(case["family"], str) and 0 < len(case["family"]) < 128, "FAMILY")
    require(case["expectation"] in ("PHYSICS", "REJECT_INVALID", "FULL_ONLY"), "EXPECTATION")
    for name, size in (("mechanical_nodes", 4), ("springs", 6), ("electrical_nodes", 2), ("resistors", 5)):
        require(unique(case[name], size), "ROWS_" + name)
    for _, x, mass, anchor in case["mechanical_nodes"]:
        require(number(x) and number(mass) and mass > 0 and type(anchor) is bool, "MECHANICAL_NODE")
    require(all(number(n[1]) for n in case["electrical_nodes"]), "ELECTRICAL_NODE")
    for domain, edges in (("mechanical", "springs"), ("electrical", "resistors")):
        nodes = {r[0]: r[1] for r in case[domain + "_nodes"]}
        for edge in case[edges]:
            require(edge[1] in nodes and edge[2] in nodes and edge[1] != edge[2], "EDGE_ENDPOINTS")
            require(nodes[edge[1]] != nodes[edge[2]], "ZERO_LENGTH_INTERCHANGE")
            require(number(edge[3]) and edge[3] > 0, "POSITIVE_K_OR_R")
            if domain == "mechanical":
                require(number(edge[4]) and edge[4] >= 0 and number(edge[5]) and edge[5] > 0, "SPRING_PARAMETERS")
            else:
                require(edge[4] in ("SOURCE_RESISTANCE", "LOAD_RESISTANCE", "WIRE"), "RESISTOR_ROLE")
    ports = case["ports"]
    require(isinstance(ports, dict) and len(ports) >= 2 and set(ports) <= {n[0] for n in case["electrical_nodes"]} and all(number(v) for v in ports.values()), "PORTS")
    require(case["coupler_node"] in {n[0] for n in case["mechanical_nodes"] if not n[3]}, "COUPLER_NODE")
    require(case["length_unit"] in UNITS and case["material_mechanical"] in E and case["material_electrical"] in RHO, "UNIT_MATERIAL")
    require(all(number(case[k]) for k in ("coupling", "external_force_n", "guard_fraction", "dt_s")), "CONTROL_NUMBER")
    require(case["coupling"] > 0 and 0 < case["guard_fraction"] < 1 and 1e-7 <= case["dt_s"] <= .02, "CONTROL_ENVELOPE")
    require(type(case["steps"]) is int and 1 <= case["steps"] <= 500, "STEP_BUDGET")


def solve(matrix: list[list[F]], rhs: list[F]) -> list[F]:
    """Exact rational Gaussian elimination for the independent small oracle."""
    n = len(rhs)
    a = [list(row) + [value] for row, value in zip(matrix, rhs)]
    for k in range(n):
        pivot = next((i for i in range(k, n) if a[i][k]), None)
        if pivot is None:
            raise ValueError("SINGULAR_PHYSICS")
        a[k], a[pivot] = a[pivot], a[k]
        v = a[k][k]
        a[k] = [x / v for x in a[k]]
        for i in range(n):
            if i != k:
                v = a[i][k]
                a[i] = [x - v*y for x, y in zip(a[i], a[k])]
    return [row[-1] for row in a]


def condition_inf(matrix: list[list[F]]) -> float:
    if not matrix:
        return 1.0
    n = len(matrix)
    columns = [solve(matrix, [F(int(i == j)) for i in range(n)]) for j in range(n)]
    norm_a = max(sum(abs(x) for x in row) for row in matrix)
    norm_inverse = max(sum(abs(columns[j][i]) for j in range(n)) for i in range(n))
    return float(norm_a*norm_inverse)


def network(case: dict, boundary: dict | None = None) -> dict:
    boundary = case["ports"] if boundary is None else boundary
    nodes = sorted(n[0] for n in case["electrical_nodes"])
    free = [n for n in nodes if n not in boundary]
    index = {n: i for i, n in enumerate(free)}
    a = [[F(0) for _ in free] for _ in free]
    b = [F(0) for _ in free]
    for _, left, right, resistance, _ in case["resistors"]:
        g = 1/F(str(resistance))
        for x, y in ((left, right), (right, left)):
            if x in index:
                i = index[x]
                a[i][i] += g
                if y in index:
                    a[i][index[y]] -= g
                else:
                    b[i] += g*F(str(boundary[y]))
    voltage = {k: F(str(v)) for k, v in boundary.items()}
    voltage.update(zip(free, solve(a, b)))
    current = {n: F(0) for n in nodes}
    edge_current = {}
    heat = F(0)
    for name, left, right, resistance, _ in case["resistors"]:
        value = (voltage[left]-voltage[right])/F(str(resistance))
        edge_current[name] = value
        current[left] += value
        current[right] -= value
        heat += value*value*F(str(resistance))
    work = sum((voltage[n]*current[n] for n in boundary), F(0))
    require(all(current[n] == 0 for n in free) and work == heat, "ORACLE_KCL_OR_POWER")
    return {"potentials_v": {k: float(v) for k, v in voltage.items()}, "port_currents_a": {k: float(current[k]) for k in boundary}, "edge_currents_a": {k: float(v) for k, v in edge_current.items()}, "power_w": float(work), "kcl_exact": True, "power_exact": True, "condition_inf": condition_inf(a)}


def mechanics(case: dict) -> dict:
    free = sorted(n[0] for n in case["mechanical_nodes"] if not n[3])
    index = {n: i for i, n in enumerate(free)}
    matrix = [[F(0) for _ in free] for _ in free]
    for _, left, right, stiffness, _, _ in case["springs"]:
        k = F(str(stiffness))
        for x, y in ((left, right), (right, left)):
            if x in index:
                matrix[index[x]][index[x]] += k
                if y in index:
                    matrix[index[x]][index[y]] -= k
    load = [F(1) if n == case["coupler_node"] else F(0) for n in free]
    return {"mobile_nodes": free, "static_displacement_per_newton": dict(zip(free, map(float, solve(matrix, load)))), "well_posed": True, "condition_inf": condition_inf(matrix)}


def oscillator(case: dict) -> dict | None:
    mobile = [n for n in case["mechanical_nodes"] if not n[3]]
    if len(mobile) != 1 or len(case["ports"]) != 2:
        return None
    ports = sorted(case["ports"], key=lambda n: (-case["ports"][n], n))
    unit = network(case, {ports[0]: 1, ports[1]: 0})
    conductance = unit["port_currents_a"][ports[0]]
    require(conductance > 0, "NO_CONNECTED_POWER_PATH")
    coupling = case["coupling"]
    return {"m": mobile[0][2], "k": sum(e[3] for e in case["springs"] if mobile[0][0] in e[1:3]), "c": sum(e[4] for e in case["springs"] if mobile[0][0] in e[1:3]) + coupling*coupling*conductance, "drive": coupling*(case["ports"][ports[0]]-case["ports"][ports[1]])*conductance + case["external_force_n"], "g": coupling, "r": 1/conductance, "u": case["ports"][ports[0]]-case["ports"][ports[1]]}


def state(p: dict, t: float) -> tuple[float, float, float]:
    m, k, c, f = (p[n] for n in ("m", "k", "c", "drive"))
    alpha = c/(2*m)
    discriminant = alpha*alpha-k/m
    equilibrium = f/k
    if abs(discriminant) <= 1e-12*max(alpha*alpha, k/m):
        decay = math.exp(-alpha*t)
        x = equilibrium*(1-(1+alpha*t)*decay)
        v = equilibrium*alpha*alpha*t*decay
    elif discriminant < 0:
        w = math.sqrt(-discriminant)
        decay = math.exp(-alpha*t)
        x = equilibrium*(1-decay*(math.cos(w*t)+alpha/w*math.sin(w*t)))
        v = f/(m*w)*decay*math.sin(w*t)
    else:
        q = math.sqrt(discriminant)
        # Stable small root: -alpha+sqrt(alpha^2-k/m) loses precision.
        r1, r2 = -(k/m)/(alpha+q), -alpha-q
        x = equilibrium*(1+(r2*math.exp(r1*t)-r1*math.exp(r2*t))/(r1-r2))
        v = equilibrium*r1*r2*(math.exp(r1*t)-math.exp(r2*t))/(r1-r2)
    return x, v, (p["u"]-p["g"]*v)/p["r"]


def first_failure(case: dict, p: dict, end: float) -> dict | None:
    # Analytic extrema of k_i*x+c_i*v partition the reference trajectory.
    alpha = p["c"]/(2*p["m"])
    delta = alpha*alpha-p["k"]/p["m"]
    best = None
    for name, _, _, k, c, capacity in case["springs"]:
        cuts = [0.0, end]
        if delta < -1e-12*max(alpha*alpha, p["k"]/p["m"]):
            w = math.sqrt(-delta)
            phase = math.atan2(-c*w, k-c*alpha)
            start = math.floor(-phase/math.pi)-1
            for n in range(start, start+int(end*w/math.pi)+5):
                t = (phase+n*math.pi)/w
                if 0 < t < end:
                    cuts.append(t)
        elif delta > 1e-12*max(alpha*alpha, p["k"]/p["m"]):
            q = math.sqrt(delta)
            r1, r2 = -(p["k"]/p["m"])/(alpha+q), -alpha-q
            if (k+c*r1)*(k+c*r2) > 0:
                t = math.log((k+c*r2)/(k+c*r1))/(r1-r2)
                if 0 < t < end:
                    cuts.append(t)
        elif k-c*alpha != 0:
            t = -c/(k-c*alpha)
            if 0 < t < end:
                cuts.append(t)
        cuts.sort()
        def effort(t: float) -> float:
            x, v, _ = state(p, t)
            return k*x+c*v
        for sign in (-1, 1):
            for lo, hi in zip(cuts, cuts[1:]):
                if sign*effort(lo) < capacity <= sign*effort(hi):
                    for _ in range(60):
                        mid = (lo+hi)/2
                        if sign*effort(mid) >= capacity:
                            hi = mid
                        else:
                            lo = mid
                    candidate = {"bond_id": "bond/"+name, "time_s": hi}
                    if best is None or hi < best["time_s"]-1e-9 or (abs(hi-best["time_s"]) <= 1e-9 and candidate["bond_id"] < best["bond_id"]):
                        best = candidate
                    break
    return best


def graph_features(case: dict) -> dict:
    adjacency = {n[0]: set() for n in case["electrical_nodes"]}
    degree = {n: 0 for n in adjacency}
    for _, a, b, _, _ in case["resistors"]:
        adjacency[a].add(b); adjacency[b].add(a)
        degree[a] += 1; degree[b] += 1
    unseen = set(adjacency)
    components = 0
    while unseen:
        stack = [unseen.pop()]; components += 1
        while stack:
            for neighbor in adjacency[stack.pop()] & unseen:
                unseen.remove(neighbor); stack.append(neighbor)
    coefficients = [e[3] for e in case["resistors"]]
    springs = [e[3] for e in case["springs"]]
    return {"cycle_rank": len(case["resistors"])-len(adjacency)+components, "max_degree": max(degree.values()), "ports": len(case["ports"]), "mobile_nodes": sum(not n[3] for n in case["mechanical_nodes"]), "mechanical_nodes": len(case["mechanical_nodes"]), "components": components, "coefficient_ratio": max(max(coefficients)/min(coefficients), max(springs)/min(springs))}


def normalize(case: dict, variant: str = "original") -> dict:
    # Pure source translation, never solve or collapse input topology here.
    scale = UNITS[case["length_unit"]]
    positions = {domain: {n[0]: float(n[1])*scale for n in case[domain+"_nodes"]} for domain in ("mechanical", "electrical")}
    ports = {"part/"+n: float(v) for n, v in case["ports"].items()}
    result = {"id": case["id"]+"/"+variant, "ports": ports, "steps": case["steps"], "dt_s": case["dt_s"], "controls": {"source_voltage_v": max(ports.values())-min(ports.values()), "external_force_n": case["external_force_n"], "coupling_n_per_a": case["coupling"], "guard_fraction": case["guard_fraction"]}}
    for domain, edges in (("mechanical", "springs"), ("electrical", "resistors")):
        nodes = []
        for row in case[domain+"_nodes"]:
            pos = [positions[domain][row[0]], 0.0, 0.0]
            if variant == "rigid":
                pos = [3.0, pos[0]-2.0, 5.0] # Proper +90 degree z rotation + translation.
            node = {"id": "part/"+row[0], "position_m": pos, "mass_kg": row[2] if domain == "mechanical" else 1.0}
            if domain == "mechanical": node["anchored"] = row[3]
            nodes.append(node)
        output_edges = []
        for row in case[edges]:
            name, a, b, coefficient = row[:4]
            length = abs(positions[domain][a]-positions[domain][b])
            if domain == "mechanical":
                metadata = {"area_m2": coefficient*length/E[case["material_mechanical"]], "damping_ns_per_m": row[4]}
            else:
                metadata = {"area_m2": RHO[case["material_electrical"]]*length/coefficient, "composition_r3_role": "WIRE_RESISTANCE" if row[4] == "WIRE" else row[4]}
            output_edges.append({"id": "bond/"+name, "a": "part/"+a, "b": "part/"+b, "kind": "AXIAL_SPRING" if domain == "mechanical" else "ELECTRICAL_RESISTOR", "capacity_n": row[5] if domain == "mechanical" else 100.0, "metadata": metadata})
        result[domain] = {"nodes": nodes, "edges": output_edges, "material": case["material_"+domain]}
    return result


def variants(case: dict) -> list[tuple[str, dict]]:
    result = [("original", copy.deepcopy(case)), ("rigid", copy.deepcopy(case))]
    perm = copy.deepcopy(case)
    for key in ("mechanical_nodes", "electrical_nodes", "springs", "resistors"):
        perm[key].reverse()
    result.append(("permutation", perm))
    renamed = copy.deepcopy(case)
    mapping = {n[0]: "renamed_%03d" % i for i, n in enumerate(reversed(case["mechanical_nodes"]+case["electrical_nodes"]))}
    for key in ("mechanical_nodes", "electrical_nodes"):
        for row in renamed[key]: row[0] = mapping[row[0]]
    for key in ("springs", "resistors"):
        for i, row in enumerate(renamed[key]):
            row[0] = "renamed_"+key+"_%03d" % (len(renamed[key])-i)
            row[1], row[2] = mapping[row[1]], mapping[row[2]]
    renamed["coupler_node"] = mapping[renamed["coupler_node"]]
    renamed["ports"] = {mapping[k]: v for k, v in renamed["ports"].items()}
    result.append(("renaming", renamed))
    units = copy.deepcopy(case)
    for key in ("mechanical_nodes", "electrical_nodes"):
        for row in units[key]: row[1] *= UNITS[case["length_unit"]]/UNITS["mm"]
    units["length_unit"] = "mm"
    result.append(("si_units", units))
    scaled = copy.deepcopy(case)
    for key in ("mechanical_nodes", "electrical_nodes"):
        for row in scaled[key]: row[1] *= 2
    for row in scaled["springs"]: row[3] /= 2
    for row in scaled["resistors"]: row[3] *= 2
    result.append(("length_x2_fixed_area", scaled))
    split = copy.deepcopy(case)
    edge = next((e for e in split["resistors"] if e[4] == "WIRE"), None)
    if edge:
        nodes = dict(split["electrical_nodes"])
        new = "split_wire_node"
        require(new not in nodes, "RESERVED_SPLIT_NODE")
        split["electrical_nodes"].append([new, (nodes[edge[1]]+nodes[edge[2]])/2])
        split["resistors"].remove(edge)
        split["resistors"].extend([[edge[0]+"_a", edge[1], new, edge[3]/2, "WIRE"], [edge[0]+"_b", new, edge[2], edge[3]/2, "WIRE"]])
        result.append(("equivalent_wire_split", split))
    split = copy.deepcopy(case)
    edge = split["springs"].pop(0)
    split["springs"].extend([[edge[0]+"_a", edge[1], edge[2], edge[3]/2, edge[4]/2, edge[5]/2], [edge[0]+"_b", edge[1], edge[2], edge[3]/2, edge[4]/2, edge[5]/2]])
    result.append(("equivalent_parallel_split", split))
    return result


def near(a: float, b: float, tolerance: float = 1e-5) -> bool:
    return number(a) and number(b) and abs(a-b) <= tolerance*(1+abs(b))


def evaluate(case: dict, observed: dict, variant: str) -> dict:
    issues, checks = [], []
    reference = {}
    invalid = False
    try:
        reference = {"electrical": network(case), "mechanical": mechanics(case)}
    except ValueError as exc:
        invalid = True
        reference["error"] = str(exc)
    compiled = observed["compile"].get("success", False)
    if case["expectation"] == "REJECT_INVALID":
        if not invalid: issues.append("NEGATIVE_CASE_NOT_PROVEN_PHYSICALLY_INVALID")
        if compiled: issues.append("INVALID_PHYSICS_ACCEPTED")
        if observed.get("source_unchanged") is not True: issues.append("REJECTION_MUTATED_SOURCE")
        return {"id": observed["id"], "family": case["family"], "expectation": case["expectation"], "verdict": "FAIL" if issues else "PASS_REJECTION", "issues": issues, "reference": reference, "actual_error": observed["compile"].get("error_code", "")}
    if invalid: issues.append("AUTHOR_PHYSICAL_CASE_IS_UNDERDETERMINED")
    for key in ("r2_mechanical", "r2_electrical"):
        if not observed[key].get("success", False): issues.append(key.upper()+"_SOURCE_REJECTED")
    if not compiled:
        issues.append("VALID_PRIMITIVES_NOT_EXECUTABLE_IN_R3")
    elif len(case["ports"]) > 2:
        issues.append("INDEPENDENT_BOUNDARY_PORTS_NOT_REPRESENTED")
    if compiled:
        reference_model = oscillator(case) if not invalid else None
        original_end = case["steps"]*case["dt_s"]
        expected_failure = first_failure(case, reference_model, original_end) if reference_model else None
        reference["first_failure"] = expected_failure
        for mode in ("FULL", "BAKE"):
            run = observed["runs"].get(mode, {})
            samples = run.get("samples", [])
            if not samples: issues.append(mode+"_NO_SAMPLES"); continue
            if "advance_error" in run: issues.append(mode+"_ADVANCE_REJECTED:"+run["advance_error"].get("error_code", ""))
            if not run.get("rejection_atomic") or not run.get("wrong_owner_rejected") or not run.get("denied_rejected"):
                issues.append(mode+"_CANONICAL_FENCE_FAILED")
            final = run["final"]
            if reference_model:
                max_errors = [0.0, 0.0, 0.0]
                for sample in samples:
                    expected = state(reference_model, sample["time_s"])
                    actual = [sample["displacement_m"], sample["velocity_m_per_s"], sample["current_a"]]
                    max_errors = [max(old, abs(x-y)/(1+abs(y))) for old, x, y in zip(max_errors, actual, expected)]
                checks.append({"mode": mode, "normalized_max_errors_x_v_i": max_errors})
                if max(max_errors) > 1e-5: issues.append(mode+"_PHYSICAL_ORACLE_MISMATCH")
                pending = final["pending_proposal"]
                if bool(expected_failure) != bool(pending): issues.append(mode+"_FAILURE_PRESENCE_MISMATCH")
                if expected_failure and pending:
                    if abs(expected_failure["time_s"]-pending["time_s"]) > 1e-4: issues.append(mode+"_FIRST_CROSSING_TIME")
                    # Simultaneous equivalent split bonds may be chosen lexically.
                    if variant != "equivalent_parallel_split" and expected_failure["bond_id"] != pending["bond_id"]:
                        issues.append(mode+"_FIRST_CROSSING_IDENTITY")
                    if not run.get("denied_failure_atomic") or not run.get("denied_failure_rejected") or not run.get("commit_failure", {}).get("success") or not run.get("duplicate_rejected"):
                        issues.append(mode+"_FAILURE_CANONICAL_LIFECYCLE")
            scale = 1+abs(final.get("source_work_j", 0))+abs(final.get("external_work_j", 0))+abs(final.get("kinetic_j", 0))+abs(final.get("elastic_j", 0))
            if abs(final["energy_residual_j"])/scale > 1e-5: issues.append(mode+"_ENERGY_RESIDUAL")
            if case["expectation"] == "FULL_ONLY" and variant in ("original", "permutation", "renaming", "si_units", "rigid", "equivalent_wire_split", "equivalent_parallel_split"):
                if final["pending_proposal"] or run["bake_at_end"].get("success") or run["bake_at_end"].get("error_code") != "R3_GUARD_REQUIRES_FULL":
                    issues.append(mode+"_FULL_ONLY_REQUIREMENT")
        full = observed["runs"].get("FULL", {}).get("samples", [])
        bake = observed["runs"].get("BAKE", {}).get("samples", [])
        if len(full) != len(bake): issues.append("FULL_BAKE_SAMPLE_COUNT")
        for f, b in zip(full, bake):
            for field in ("time_s", "displacement_m", "velocity_m_per_s", "current_a", "energy_residual_j"):
                if not near(f[field], b[field], 1e-8): issues.append("FULL_BAKE_"+field)
    return {"id": observed["id"], "family": case["family"], "expectation": case["expectation"], "verdict": "FAIL" if issues else "PASS_PHYSICS", "issues": sorted(set(issues)), "checks": checks, "reference": reference, "actual_error": observed["compile"].get("error_code", ""), "features": graph_features(case)}


def git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE)


def freeze_check(root: Path) -> dict:
    require(git(root, "rev-parse", BASE+"^{tree}").decode().strip() == TREE, "FROZEN_TREE_ID")
    tree = git(root, "ls-tree", "-rz", BASE)
    count = 0
    for entry in tree.split(b"\0"):
        if not entry: continue
        metadata, path = entry.split(b"\t", 1)
        mode, kind, identity = metadata.split()
        if kind != b"blob": raise ValueError("UNSUPPORTED_SUBMODULE_IN_FREEZE")
        full = root/os.fsdecode(path)
        require(full.is_file() and not full.is_symlink(), "MISSING_FROZEN_FILE:"+os.fsdecode(path))
        data = full.read_bytes()
        actual = hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
        require(actual == identity.decode(), "FROZEN_SOURCE_MUTATED:"+os.fsdecode(path))
        count += 1
    changed = git(root, "diff", "--name-only", BASE).decode().splitlines()
    require(all(p.startswith(ALLOWED) for p in changed), "OUTSIDE_WORK_ORDER")
    return {"subject_head": BASE, "subject_tree": TREE, "baseline_files_verified": count}


def run_process(root: Path, out: Path, name: str, command: list[str], budget: int = 180) -> None:
    started = time.monotonic()
    log = out/(name+".log")
    # Stream durable logs while the child is active, including on interruption.
    with log.open("wb") as stream:
        process = subprocess.Popen(command, cwd=root, env={**os.environ, "BREAKPOINT_RUNTIME_DISABLED": "1"}, stdout=stream, stderr=subprocess.STDOUT)
        try:
            exit_code = process.wait(timeout=budget)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            stream.write(b"\nR4_PROCESS_TIMEOUT\n")
            exit_code = 124
    data = log.read_bytes()
    with (out/"commands.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(dumps({"name": name, "argv": command, "exit": exit_code, "seconds": time.monotonic()-started, "log_sha256": sha(data)})+"\n")
    require(exit_code == 0 and not FATAL.search(data.decode("utf-8", errors="replace")), "PROBE_FAILED:"+name)
    require(b"R4_PROBE_COMPLETED=" in data, "EMPTY_PROBE:"+name)


def sharded_probe(root: Path, out: Path, probe: list[str], mode: str, records: list, name: str) -> list:
    results = []
    for index, record in enumerate(records):
        prefix = "%s-%03d" % (name, index)
        source, target = out/(prefix+"-input.json"), out/(prefix+"-output.json")
        source.write_text(dumps([record])+"\n", encoding="utf-8")
        print("R4_SHARD="+prefix+" ID="+str(record["id"]), flush=True)
        run_process(root, out, prefix, probe+[mode, str(source), str(target)], 120)
        returned = json.loads(target.read_text())
        require(isinstance(returned, list) and len(returned) == 1 and returned[0]["id"] == record["id"], "SHARD_BINDING:"+prefix)
        results.extend(returned)
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    root, out = args.root.resolve(), args.out.resolve()
    try:
        out.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        print("HOLDOUT_R4_PROTOCOL_ERROR=OUTPUT_MUST_BE_NEW", file=sys.stderr)
        return 2
    try:
        binding = freeze_check(root)
        engine = args.godot.resolve()
        require(sha(engine.read_bytes()) == ENGINE, "GODOT_SHA256")
        require(subprocess.check_output([str(engine), "--version"], text=True).strip() == VERSION, "GODOT_VERSION")
        raw = args.cases.read_bytes()
        catalog = json.loads(raw)
        provenance = json.loads(args.provenance.read_text(encoding="utf-8"))
        require(set(catalog) == {"schema", "cases"} and catalog["schema"] == "fabric.holdout_r4.cases.v1", "BUNDLE_SCHEMA")
        cases = catalog["cases"]
        require(isinstance(cases, list) and 6 <= len(cases) <= 12, "CASE_COUNT")
        require(provenance["freeze_commit"] == FREEZE and provenance["cases_sha256"] == sha(raw) and provenance["author"] == "chatgpt-codex-connector[bot]" and provenance["source_comment_id"] > 0, "INDEPENDENT_PROVENANCE")
        author_raw = (root/provenance["raw_response_path"]).read_bytes()
        require(sha(author_raw) == provenance["raw_response_sha256"], "AUTHOR_RAW_DIGEST")
        match = re.search(r"```json\s*(.*?)```", author_raw.decode(), re.S)
        require(match is not None and json.loads(match.group(1)) == catalog, "CHALLENGE_NOT_EXACT_AUTHOR_PAYLOAD")
        for case in cases: validate_case(case)
        require(len({c["id"] for c in cases}) == len(cases), "DUPLICATE_CASE_ID")
        expanded = [(name, spec) for case in cases for name, spec in variants(case)]
        requests = [normalize(spec, name) for name, spec in expanded]
        request_path = out/"requests.json"
        request_path.write_text(dumps(requests)+"\n", encoding="utf-8")
        probe = [str(engine), "--headless", "--path", str(root), "--script", "res://tests/research/fabric1/fabric_holdout_r4_probe.gd", "--"]
        attempts = []
        for attempt in (1, 2):
            measured = sharded_probe(root, out, probe, "measure", requests, "measure-"+str(attempt))
            (out/("observed-%d.json" % attempt)).write_text(dumps(measured)+"\n", encoding="utf-8")
            attempts.append(measured)
        observations, second = attempts
        require(observations == second and len(observations) == len(requests), "FRESH_PROCESS_DETERMINISM")
        require([r["id"] for r in requests] == [r["id"] for r in observations], "OBSERVATION_BINDING")
        evaluated = [evaluate(case, obs, name) for (name, case), obs in zip(expanded, observations)]
        packages = [run["replay_package"] for obs in observations for run in obs.get("runs", {}).values() if "replay_package" in run]
        replay_matches = False
        if packages:
            (out/"replay-packages.json").write_text(dumps(packages)+"\n", encoding="utf-8")
            replay = sharded_probe(root, out, probe, "replay", packages, "cold-replay")
            (out/"cold-replay.json").write_text(dumps(replay)+"\n", encoding="utf-8")
            replay_matches = len(replay) == len(packages) and all(r["matches"] and r["result"].get("success") for r in replay)
        features = [graph_features(case) for case in cases if case["expectation"] != "REJECT_INVALID"]
        coverage = {"small": any(f["mechanical_nodes"] <= 6 for f in features), "branching": any(f["max_degree"] >= 3 for f in features), "loops_or_bridges": any(f["cycle_rank"] >= 1 for f in features), "multiport": any(f["ports"] >= 3 for f in features), "multimass": any(f["mobile_nodes"] >= 2 for f in features), "coefficient_disparity": any(f["coefficient_ratio"] >= 1e6 for f in features), "full_only_state": any(c["expectation"] == "FULL_ONLY" for c in cases), "invalid_physics": any(c["expectation"] == "REJECT_INVALID" for c in cases)}
        # Cross-variant comparison is separate from the independent physical oracle.
        original_observations = {o["id"].split("/")[0]: o for o in observations if o["id"].endswith("/original")}
        for (variant, case), observed, assessment in zip(expanded, observations, evaluated):
            if variant in ("original", "length_x2_fixed_area"):
                continue
            original = original_observations[case["id"]]
            if original["compile"].get("success") != observed["compile"].get("success"):
                assessment["issues"].append("METAMORPHIC_EXECUTABILITY_CHANGED")
            for mode in ("FULL", "BAKE"):
                a = original.get("runs", {}).get(mode, {}).get("samples", [])
                b = observed.get("runs", {}).get(mode, {}).get("samples", [])
                if len(a) != len(b):
                    assessment["issues"].append("METAMORPHIC_SAMPLE_COUNT")
                elif any(not near(x[k], y[k], 1e-8) for x, y in zip(a, b) for k in ("time_s", "displacement_m", "velocity_m_per_s", "current_a")):
                    assessment["issues"].append("METAMORPHIC_PHYSICAL_RESPONSE")
            assessment["issues"] = sorted(set(assessment["issues"]))
            if assessment["issues"]:
                assessment["verdict"] = "FAIL"
        original_refs = [r["reference"] for r in evaluated if r["id"].endswith("/original")]
        coverage["near_singular_matrix"] = any(max(r.get("electrical", {}).get("condition_inf", 0), r.get("mechanical", {}).get("condition_inf", 0)) >= 1e6 for r in original_refs)
        failures = [r for r in evaluated if r["verdict"] == "FAIL"]
        status = "EXPERIMENT_COMPLETED_FAIL" if failures or not replay_matches else "PASS"
        if not all(coverage.values()): status = "INCOMPLETE_COVERAGE"
        report = {"schema": "fabric.holdout_r4.result.v1", "freeze": binding, "freeze_commit": FREEZE, "generation": "G1", "evaluated_harness_head": git(root, "rev-parse", "HEAD").decode().strip(), "challenge_sha256": sha(raw), "provenance": provenance, "status": status, "holdout_r4_closed": False, "independent_acceptance": "PENDING", "scale_r5_unlocked": False, "main_acceptance": False, "coverage": coverage, "original_cases": len(cases), "original_families": len({c["family"] for c in cases}), "measurements": len(evaluated), "passed": len(evaluated)-len(failures), "failed": len(failures), "cold_replay_packages": len(packages), "cold_replay_matches": replay_matches, "fresh_processes_identical": True, "results": evaluated}
        freeze_check(root)
        report["semantic_sha256"] = sha(dumps({k: v for k, v in report.items() if k != "evaluated_harness_head"}).encode())
        (out/"result.json").write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)+"\n", encoding="utf-8")
        print("HOLDOUT_R4_STATUS="+status)
        print("HOLDOUT_R4_CASES=%d MEASUREMENTS=%d FAILURES=%d" % (len(cases), len(evaluated), len(failures)))
        return 2 if status.startswith("INCOMPLETE") else (1 if status.endswith("FAIL") else 0)
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, TypeError, ZeroDivisionError) as exc:
        (out/"protocol-error.json").write_text(dumps({"status": "INCOMPLETE_PROTOCOL_ERROR", "error": str(exc)})+"\n", encoding="utf-8")
        print("HOLDOUT_R4_PROTOCOL_ERROR="+str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
