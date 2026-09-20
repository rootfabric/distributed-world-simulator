#!/usr/bin/env python3
"""FABRIC R4.2 preregistered topology + dynamic holdout generator/oracle.

Stdlib-only. This file intentionally contains the complete case grammar,
deterministic generator and independent numerical/reference oracle. Product
runtime code is never imported.
"""
from __future__ import annotations

from fractions import Fraction as F
import argparse, copy, hashlib, json, math, re
from pathlib import Path
from typing import Any

SCHEMA = "fabric.holdout_r4_2.cases.v1"
PREREG_SCHEMA = "fabric.holdout_r4_2.preregistration.v1"
GENERATOR_VERSION = "r42-generator-oracle-v1"
STEEL_E = 2.0e11
COPPER_RHO = 1.68e-8
FAMILIES = (
    "electrical_chain_2port",
    "electrical_branch_3port",
    "electrical_cycle_4port",
    "mechanics_multi_dof",
    "near_singular_supported",
    "coupled_dynamic_trajectory",
    "canonical_lifecycle_rebake",
    "reject_floating_electrical",
    "reject_underdetermined_mechanics",
    "reject_noncollinear_mechanics",
)
POSITIVE = set(FAMILIES[:7])
NEGATIVE = set(FAMILIES[7:])


def dumps(v: Any) -> str:
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha(v: Any) -> str:
    b = v if isinstance(v, (bytes, bytearray)) else dumps(v).encode()
    return hashlib.sha256(b).hexdigest()


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def finite(x: Any) -> bool:
    return type(x) in (int, float) and math.isfinite(x)


class Stream:
    """Version-stable SHA256 counter stream; avoids Python random-version drift."""
    def __init__(self, seed: str):
        require(isinstance(seed, str) and len(seed) >= 16, "SEED")
        self.seed = seed.encode()
        self.counter = 0

    def _word(self) -> int:
        h = hashlib.sha256(self.seed + b"|" + str(self.counter).encode()).digest()
        self.counter += 1
        return int.from_bytes(h[:8], "big")

    def unit(self) -> float:
        return (self._word() >> 11) / float(1 << 53)

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self.unit()

    def randint(self, a: int, b: int) -> int:
        return a + self._word() % (b - a + 1)

    def choice(self, seq):
        return seq[self._word() % len(seq)]

    def shuffle(self, seq):
        out = list(seq)
        for i in range(len(out) - 1, 0, -1):
            j = self._word() % (i + 1)
            out[i], out[j] = out[j], out[i]
        return out


def solve_float(matrix: list[list[float]], rhs: list[float]) -> list[float]:
    a = [list(r) + [rhs[i]] for i, r in enumerate(matrix)]
    n = len(rhs)
    for k in range(n):
        pivot = max(range(k, n), key=lambda i: abs(a[i][k]))
        if not math.isfinite(a[pivot][k]) or abs(a[pivot][k]) <= 1e-18:
            raise ValueError("SINGULAR")
        a[k], a[pivot] = a[pivot], a[k]
        p = a[k][k]
        for j in range(k, n + 1):
            a[k][j] /= p
        for i in range(n):
            if i == k:
                continue
            q = a[i][k]
            for j in range(k, n + 1):
                a[i][j] -= q * a[k][j]
    return [a[i][-1] for i in range(n)]


def solve_fraction(matrix: list[list[F]], rhs: list[F]) -> list[F]:
    n = len(rhs)
    a = [list(r) + [rhs[i]] for i, r in enumerate(matrix)]
    for k in range(n):
        pivot = next((i for i in range(k, n) if a[i][k] != 0), None)
        if pivot is None:
            raise ValueError("SINGULAR")
        a[k], a[pivot] = a[pivot], a[k]
        p = a[k][k]
        a[k] = [x / p for x in a[k]]
        for i in range(n):
            if i == k:
                continue
            q = a[i][k]
            a[i] = [x - q * y for x, y in zip(a[i], a[k])]
    return [r[-1] for r in a]


def condition_inf_fraction(matrix: list[list[F]]) -> float:
    if not matrix:
        return 1.0
    n = len(matrix)
    cols = [solve_fraction(matrix, [F(int(i == j)) for i in range(n)]) for j in range(n)]
    na = max(sum(abs(x) for x in row) for row in matrix)
    ni = max(sum(abs(cols[j][i]) for j in range(n)) for i in range(n))
    return float(na * ni)


def network(case: dict, boundary_override: dict | None = None) -> dict:
    e = case["electrical"]
    boundary = e["ports"] if boundary_override is None else boundary_override
    nodes = sorted(n["id"] for n in e["nodes"])
    free = [n for n in nodes if n not in boundary]
    idx = {n: i for i, n in enumerate(free)}
    a = [[F(0) for _ in free] for _ in free]
    b = [F(0) for _ in free]
    for edge in e["resistors"]:
        g = 1 / F(str(edge["resistance_ohm"]))
        for x, y in ((edge["a"], edge["b"]), (edge["b"], edge["a"])):
            if x not in idx:
                continue
            i = idx[x]
            a[i][i] += g
            if y in idx:
                a[i][idx[y]] -= g
            else:
                if y not in boundary:
                    continue
                b[i] += g * F(str(boundary[y]))
    adjacency = {n: [] for n in nodes}
    for edge in e["resistors"]:
        adjacency[edge["a"]].append(edge["b"]); adjacency[edge["b"]].append(edge["a"])
    unseen = set(nodes)
    while unseen:
        start = next(iter(unseen)); stack = [start]; component = set()
        while stack:
            n = stack.pop()
            if n in component:
                continue
            component.add(n); unseen.discard(n); stack.extend(adjacency[n])
        if not (component & set(boundary)):
            raise ValueError("FLOATING_COMPONENT")
    v = {k: F(str(value)) for k, value in boundary.items()}
    if free:
        v.update(dict(zip(free, solve_fraction(a, b))))
    current = {n: F(0) for n in nodes}
    edge_current = {}
    heat = F(0)
    for edge in e["resistors"]:
        r = F(str(edge["resistance_ohm"]))
        i = (v[edge["a"]] - v[edge["b"]]) / r
        edge_current[edge["id"]] = i
        current[edge["a"]] += i; current[edge["b"]] -= i
        heat += i * i * r
    for n in free:
        require(current[n] == 0, "ORACLE_KCL")
    power = sum((v[n] * current[n] for n in boundary), F(0))
    require(power == heat, "ORACLE_POWER")
    return {
        "potentials_v": {k: float(vv) for k, vv in v.items()},
        "port_currents_a": {k: float(current[k]) for k in boundary},
        "edge_currents_a": {k: float(iv) for k, iv in edge_current.items()},
        "power_w": float(power),
        "condition_inf": condition_inf_fraction(a),
    }


def mechanical_static(case: dict) -> dict:
    m = case["mechanical"]
    mobile = sorted(n["id"] for n in m["nodes"] if not n["anchored"])
    idx = {n: i for i, n in enumerate(mobile)}
    a = [[F(0) for _ in mobile] for _ in mobile]
    for edge in m["springs"]:
        k = F(str(edge["stiffness_n_per_m"]))
        for x, y in ((edge["a"], edge["b"]), (edge["b"], edge["a"])):
            if x in idx:
                a[idx[x]][idx[x]] += k
                if y in idx:
                    a[idx[x]][idx[y]] -= k
    load = [F(1) if n == case["controls"]["coupler_node_id"] else F(0) for n in mobile]
    x = solve_fraction(a, load)
    return {
        "mobile_nodes": mobile,
        "displacement_per_newton": {n: float(v) for n, v in zip(mobile, x)},
        "condition_inf": condition_inf_fraction(a),
    }


def source_port(case: dict) -> str:
    ports = case["electrical"]["ports"]
    source_edges = [e for e in case["electrical"]["resistors"] if e["role"] == "SOURCE_RESISTANCE"]
    require(len(source_edges) == 1, "SOURCE_ROLE_COUNT")
    endpoints = [n for n in (source_edges[0]["a"], source_edges[0]["b"]) if n in ports]
    require(len(endpoints) == 1, "SOURCE_BOUNDARY_ENDPOINT")
    return endpoints[0]


_COEFF_CACHE: dict[str, tuple[float,float]] = {}

def electrical_coupler_coefficients(case: dict) -> tuple[float,float]:
    key = sha({"electrical":case["electrical"],"coupling_n_per_a":case["controls"]["coupling_n_per_a"],"source_port_id":source_port(case)})
    if key in _COEFF_CACHE:
        return _COEFF_CACHE[key]
    sp = source_port(case)
    g = float(case["controls"]["coupling_n_per_a"])
    base = network(case)
    shifted = dict(case["electrical"]["ports"])
    shifted[sp] = float(shifted[sp]) - g
    unit = network(case, shifted)
    i0 = float(base["port_currents_a"][sp])
    iv = float(unit["port_currents_a"][sp]) - i0
    _COEFF_CACHE[key] = (i0, iv)
    return i0, iv

def derivatives(case: dict, state: list[float], active: set[str] | None = None) -> tuple[list[float], dict]:
    m = case["mechanical"]
    mobile = sorted(n["id"] for n in m["nodes"] if not n["anchored"])
    idx = {n: i for i, n in enumerate(mobile)}
    count = len(mobile)
    q, v = state[:count], state[count:]
    g = float(case["controls"]["coupling_n_per_a"])
    coupler = case["controls"]["coupler_node_id"]
    ci = idx[coupler]
    i0, iv = electrical_coupler_coefficients(case)
    current = i0 + iv * v[ci]
    graph = None
    forces = [0.0] * count
    efforts = {}
    for edge in m["springs"]:
        enabled = active is None or edge["id"] in active
        if not enabled:
            efforts[edge["id"]] = 0.0
            continue
        ia, ib = idx.get(edge["a"]), idx.get(edge["b"])
        qa = q[ia] if ia is not None else 0.0; qb = q[ib] if ib is not None else 0.0
        va = v[ia] if ia is not None else 0.0; vb = v[ib] if ib is not None else 0.0
        effort = float(edge["stiffness_n_per_m"]) * (qa - qb) + float(edge["damping_ns_per_m"]) * (va - vb)
        efforts[edge["id"]] = effort
        if ia is not None: forces[ia] -= effort
        if ib is not None: forces[ib] += effort
    forces[ci] += g * current + float(case["controls"]["external_force_n"])
    masses = {n["id"]: float(n["mass_kg"]) for n in m["nodes"]}
    acc = [forces[i] / masses[mobile[i]] for i in range(count)]
    return v + acc, {"current_a": current, "efforts_n": efforts, "graph": graph}


def rk4_step(case: dict, state: list[float], h: float, active: set[str] | None = None) -> list[float]:
    def add(x, y, scale): return [a + scale*b for a, b in zip(x, y)]
    k1, _ = derivatives(case, state, active)
    k2, _ = derivatives(case, add(state, k1, h/2), active)
    k3, _ = derivatives(case, add(state, k2, h/2), active)
    k4, _ = derivatives(case, add(state, k3, h), active)
    return [x + h*(a + 2*b + 2*c + d)/6 for x, a, b, c, d in zip(state, k1, k2, k3, k4)]


def trajectory_reference(case: dict) -> dict:
    mobile = sorted(n["id"] for n in case["mechanical"]["nodes"] if not n["anchored"])
    state = [0.0] * (2 * len(mobile))
    macro = float(case["dt_s"])
    sub = max(24, int(math.ceil(macro / 2.5e-5)))
    h = macro / sub
    samples = []
    for step in range(int(case["steps"])):
        for _ in range(sub): state = rk4_step(case, state, h)
        _, obs = derivatives(case, state)
        n = len(mobile)
        samples.append({
            "time_s": (step + 1) * macro,
            "displacements_m": {mobile[i]: state[i] for i in range(n)},
            "velocities_m_per_s": {mobile[i]: state[n+i] for i in range(n)},
            "current_a": obs["current_a"],
        })
    return {"samples": samples}


def lifecycle_reference(case: dict) -> dict:
    mobile = sorted(n["id"] for n in case["mechanical"]["nodes"] if not n["anchored"])
    state = [0.0] * (2 * len(mobile))
    macro = float(case["dt_s"])
    h = macro / 80.0
    end = macro * int(case["steps"])
    t = 0.0
    previous = {e["id"]: 0.0 for e in case["mechanical"]["springs"]}
    while t < end - 1e-15:
        state = rk4_step(case, state, h)
        t += h
        _, obs = derivatives(case, state)
        for edge in case["mechanical"]["springs"]:
            effort = abs(float(obs["efforts_n"][edge["id"]]))
            capacity = float(edge["capacity_n"])
            if previous[edge["id"]] < capacity <= effort:
                return {"failure_bond_id": edge["id"], "failure_time_s": t, "effort_n": obs["efforts_n"][edge["id"]]}
            previous[edge["id"]] = effort
    raise ValueError("LIFECYCLE_NO_FAILURE")


def pos(x: float) -> list[float]:
    return [round(x, 9), 0.0, 0.0]


def mech_nodes(count_mobile: int, rng: Stream, noncollinear: bool = False, anchored: bool = True):
    nodes = [{"id": "m0", "position_m": pos(0.0), "mass_kg": 1.0, "anchored": anchored}]
    for i in range(1, count_mobile + 1):
        p = pos(float(i))
        if noncollinear and i == max(1, count_mobile // 2): p[1] = 0.25
        nodes.append({"id": f"m{i}", "position_m": p, "mass_kg": round(rng.uniform(0.8, 2.2), 6), "anchored": False})
    nodes.append({"id": f"m{count_mobile+1}", "position_m": pos(float(count_mobile+1)), "mass_kg": 1.0, "anchored": anchored})
    return nodes


def spring(id_: str, a: str, b: str, k: float, c: float, cap: float):
    return {"id": id_, "a": a, "b": b, "stiffness_n_per_m": float(k), "damping_ns_per_m": float(c), "capacity_n": float(cap)}


def e_nodes(n: int):
    return [{"id": f"e{i}", "position_m": pos(float(i))} for i in range(n)]


def resistor(id_: str, a: str, b: str, r: float, role: str = "WIRE_RESISTANCE"):
    return {"id": id_, "a": a, "b": b, "resistance_ohm": float(r), "role": role}


def base_controls(coupler: str, rng: Stream, external: tuple[float,float]=(1.0, 4.0), coupling=(0.6, 1.8)):
    return {"coupler_node_id": coupler, "coupling_n_per_a": round(rng.uniform(*coupling), 6), "external_force_n": round(rng.uniform(*external), 6), "guard_fraction": 0.78}


def case_template(id_: str, family: str, phase: str, m_nodes, springs, enodes, resistors, ports, controls, dt=0.001, steps=8, post=0):
    return {
        "id": id_, "family": family, "expectation": "PHYSICS" if family in POSITIVE else "REJECT_INVALID",
        "phase": phase,
        "mechanical": {"material": "material/steel", "nodes": m_nodes, "springs": springs},
        "electrical": {"material": "material/copper", "nodes": enodes, "resistors": resistors, "ports": ports},
        "controls": controls, "dt_s": dt, "steps": steps, "post_commit_steps": post,
    }


def generate(seed: str) -> list[dict]:
    rng = Stream(seed)
    cases = []
    n = rng.randint(4, 7); en = e_nodes(n)
    rs = [resistor(f"r{i}", f"e{i}", f"e{i+1}", round(rng.uniform(0.8, 4.0),6), "WIRE_RESISTANCE") for i in range(n-1)]
    rs[0]["role"] = "SOURCE_RESISTANCE"; rs[-1]["role"] = "LOAD_RESISTANCE"
    mn = mech_nodes(1,rng); sp=[spring("s0","m0","m1",70,2,1e6),spring("s1","m1","m2",110,3,1e6)]
    cases.append(case_template("r42-chain",FAMILIES[0],"STATIC",mn,sp,en,rs,{"e0":9.0,"e%d"%(n-1):0.0},base_controls("m1",rng)))
    en=e_nodes(7); rs=[
      resistor("r0","e0","e1",1.4,"SOURCE_RESISTANCE"), resistor("r1","e1","e2",2.1), resistor("r2","e1","e3",3.3),
      resistor("r3","e2","e4",1.9,"LOAD_RESISTANCE"), resistor("r4","e3","e4",2.7), resistor("r5","e2","e3",4.6),
      resistor("r6","e4","e5",1.2), resistor("r7","e3","e6",2.4)]
    mn=mech_nodes(2,rng); sp=[spring("s0","m0","m1",90,2.2,1e6),spring("s1","m1","m2",120,2.5,1e6),spring("s2","m2","m3",80,1.8,1e6)]
    cases.append(case_template("r42-branch",FAMILIES[1],"STATIC",mn,sp,en,rs,{"e0":11.0,"e5":0.0,"e6":3.25},base_controls("m2",rng)))
    en=e_nodes(8); rs=[]
    for i in range(8): rs.append(resistor(f"ring{i}",f"e{i}",f"e{(i+1)%8}",1.0+0.31*i))
    rs += [resistor("d0","e0","e4",3.7),resistor("d1","e2","e6",2.9)]
    rs[0]["role"]="SOURCE_RESISTANCE"; rs[4]["role"]="LOAD_RESISTANCE"
    mn=mech_nodes(3,rng); sp=[spring("s0","m0","m1",70,1.5,1e6),spring("s1","m1","m2",95,1.7,1e6),spring("s2","m2","m3",130,2.2,1e6),spring("s3","m3","m4",85,1.6,1e6),spring("sx","m1","m3",35,0.8,1e6)]
    cases.append(case_template("r42-cycle",FAMILIES[2],"STATIC",mn,sp,en,rs,{"e0":12.0,"e2":7.0,"e4":0.0,"e6":2.0},base_controls("m2",rng)))
    mn=mech_nodes(4,rng); sp=[]
    for i in range(5): sp.append(spring(f"s{i}",f"m{i}",f"m{i+1}",75+15*i,1.2+0.3*i,1e6))
    sp += [spring("cross0","m1","m3",28,0.6,1e6), spring("cross1","m2","m4",31,0.7,1e6)]
    en=e_nodes(4); rs=[resistor("r0","e0","e1",1.2,"SOURCE_RESISTANCE"),resistor("r1","e1","e2",2.0),resistor("r2","e2","e3",1.4,"LOAD_RESISTANCE"),resistor("r3","e1","e3",4.1)]
    cases.append(case_template("r42-mechanics",FAMILIES[3],"STATIC",mn,sp,en,rs,{"e0":8.0,"e3":0.0},base_controls("m3",rng)))
    mn=mech_nodes(2,rng); sp=[spring("softL","m0","m1",1.0e-3,1e-4,1e6),spring("hard","m1","m2",1.0e3,1.0,1e6),spring("softR","m2","m3",2.0e-3,1e-4,1e6)]
    en=e_nodes(6); rs=[resistor("r0","e0","e1",1.0,"SOURCE_RESISTANCE"),resistor("r1","e1","e2",1.0),resistor("weak","e2","e3",1e6),resistor("r3","e3","e4",1.0),resistor("r4","e4","e5",1.0,"LOAD_RESISTANCE")]
    cases.append(case_template("r42-near-singular",FAMILIES[4],"STATIC",mn,sp,en,rs,{"e0":5.0,"e5":0.0},base_controls("m1",rng,external=(0.01,0.05),coupling=(0.2,0.4))))
    mn=mech_nodes(3,rng); sp=[spring("s0","m0","m1",55,2.5,1e6),spring("s1","m1","m2",80,2.0,1e6),spring("s2","m2","m3",105,2.2,1e6),spring("s3","m3","m4",75,1.8,1e6),spring("bridge","m1","m3",22,0.5,1e6)]
    en=e_nodes(6); rs=[resistor("r0","e0","e1",1.0,"SOURCE_RESISTANCE"),resistor("r1","e1","e2",1.8),resistor("r2","e1","e3",2.6),resistor("r3","e2","e4",1.4,"LOAD_RESISTANCE"),resistor("r4","e3","e4",2.1),resistor("r5","e2","e3",3.7),resistor("r6","e4","e5",1.1)]
    cases.append(case_template("r42-dynamic",FAMILIES[5],"DYNAMIC",mn,sp,en,rs,{"e0":10.0,"e5":0.0,"e3":2.5},base_controls("m2",rng,external=(2.0,3.0),coupling=(0.7,1.1)),dt=0.001,steps=32))
    mn=mech_nodes(3,rng); edges=[("m0","m1"),("m1","m2"),("m2","m3"),("m3","m4"),("m1","m3")]
    weak=rng.randint(0,3); sp=[]
    for i,(a,b) in enumerate(edges): sp.append(spring(f"life{i}",a,b,65+12*i,1.0+0.25*i,4.5 if i==weak else 90.0))
    en=e_nodes(5); rs=[resistor("r0","e0","e1",0.8,"SOURCE_RESISTANCE"),resistor("r1","e1","e2",1.4),resistor("r2","e1","e3",2.2),resistor("r3","e2","e4",1.0,"LOAD_RESISTANCE"),resistor("r4","e3","e4",1.7),resistor("r5","e2","e3",2.8)]
    cases.append(case_template("r42-lifecycle",FAMILIES[6],"LIFECYCLE",mn,sp,en,rs,{"e0":14.0,"e4":0.0,"e3":3.0},base_controls("m2",rng,external=(13.0,17.0),coupling=(1.0,1.5)),dt=0.001,steps=400,post=16))
    base=copy.deepcopy(cases[1]); base["id"]="r42-reject-floating"; base["family"]=FAMILIES[7]; base["expectation"]="REJECT_INVALID"; base["phase"]="NEGATIVE"
    base["electrical"]["nodes"] += [{"id":"f0","position_m":pos(8.0)},{"id":"f1","position_m":pos(9.0)}]
    base["electrical"]["resistors"] += [resistor("floating","f0","f1",2.0)]
    cases.append(base)
    base=copy.deepcopy(cases[3]); base["id"]="r42-reject-mechanics"; base["family"]=FAMILIES[8]; base["expectation"]="REJECT_INVALID"; base["phase"]="NEGATIVE"
    for node in base["mechanical"]["nodes"]: node["anchored"]=False
    cases.append(base)
    base=copy.deepcopy(cases[3]); base["id"]="r42-reject-noncollinear"; base["family"]=FAMILIES[9]; base["expectation"]="REJECT_INVALID"; base["phase"]="NEGATIVE"
    base["mechanical"]["nodes"][2]["position_m"][1]=0.35
    cases.append(base)
    for c in cases:
        c["mechanical"]["nodes"] = rng.shuffle(c["mechanical"]["nodes"])
        c["mechanical"]["springs"] = rng.shuffle(c["mechanical"]["springs"])
        c["electrical"]["nodes"] = rng.shuffle(c["electrical"]["nodes"])
        c["electrical"]["resistors"] = rng.shuffle(c["electrical"]["resistors"])
    return cases


def normalize(case: dict) -> dict:
    """Pure topology/material translation. It never solves the case."""
    out={"id":case["id"],"family":case["family"],"expectation":case["expectation"],"phase":case["phase"],"controls":copy.deepcopy(case["controls"]),"dt_s":case["dt_s"],"steps":case["steps"],"post_commit_steps":case["post_commit_steps"],"ports":copy.deepcopy(case["electrical"]["ports"])}
    for domain in ("mechanical","electrical"):
        spec=case[domain]; nodes=[]; edges=[]
        positions={n["id"]:n["position_m"] for n in spec["nodes"]}
        for n in spec["nodes"]:
            row={"id":"part/"+n["id"],"position_m":n["position_m"],"mass_kg":n.get("mass_kg",1.0)}
            if domain=="mechanical": row["anchored"]=n["anchored"]
            nodes.append(row)
        source_port_id = source_port(case) if domain=="electrical" else ""
        for e in spec["springs"] if domain=="mechanical" else spec["resistors"]:
            pa,pb=positions[e["a"]],positions[e["b"]]
            length=math.sqrt(sum((float(a)-float(b))**2 for a,b in zip(pa,pb)))
            if domain=="mechanical":
                metadata={"area_m2":float(e["stiffness_n_per_m"])*length/STEEL_E,"damping_ns_per_m":float(e["damping_ns_per_m"])}
                edges.append({"id":"bond/"+e["id"],"a":"part/"+e["a"],"b":"part/"+e["b"],"kind":"AXIAL_SPRING","capacity_n":e["capacity_n"],"metadata":metadata})
            else:
                metadata={"area_m2":COPPER_RHO*length/float(e["resistance_ohm"]),"composition_r3_role":e["role"]}
                edges.append({"id":"bond/"+e["id"],"a":"part/"+e["a"],"b":"part/"+e["b"],"kind":"ELECTRICAL_RESISTOR","capacity_n":100.0,"metadata":metadata})
        out[domain]={"nodes":nodes,"edges":edges,"material":spec["material"]}
        if domain=="electrical": out["source_port_id"]="part/"+source_port_id
    out["ports"]={"part/"+k:v for k,v in case["electrical"]["ports"].items()}
    out["controls"]["source_voltage_v"] = max(case["electrical"]["ports"].values()) - min(case["electrical"]["ports"].values())
    out["controls"]["coupler_node_id"]="part/"+case["controls"]["coupler_node_id"]
    return out


def reference(case: dict) -> dict:
    if case["expectation"] == "REJECT_INVALID":
        family=case["family"]
        expected={
            FAMILIES[7]: ["R3_GENERAL_FLOATING_COMPONENT"],
            FAMILIES[8]: ["R3_GENERAL_MECHANICAL_UNDERDETERMINED"],
            FAMILIES[9]: ["R3_GENERAL_COLLINEAR_AXIAL_REQUIRED"],
        }[family]
        return {"expected_error_codes":expected}
    e=network(case); m=mechanical_static(case)
    ref={"electrical":e,"mechanical":m,"source_port_id":source_port(case)}
    if case["phase"]=="DYNAMIC": ref["trajectory"]=trajectory_reference(case)
    if case["phase"]=="LIFECYCLE": ref["lifecycle"]=lifecycle_reference(case)
    return ref


def validate_case(c: dict) -> None:
    require(set(c)=={"id","family","expectation","phase","mechanical","electrical","controls","dt_s","steps","post_commit_steps"},"CASE_FIELDS")
    require(c["family"] in FAMILIES and c["expectation"] in ("PHYSICS","REJECT_INVALID"),"CASE_KIND")
    require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{1,63}",c["id"]) is not None,"CASE_ID")
    for domain in ("mechanical","electrical"):
        require(isinstance(c[domain]["nodes"],list) and 2<=len(c[domain]["nodes"])<=32,"NODE_COUNT")
    require(2<=len(c["electrical"]["ports"])<=4,"PORT_COUNT")
    require(c["controls"]["coupler_node_id"] in {n["id"] for n in c["mechanical"]["nodes"] if not n["anchored"]},"COUPLER")
    require(1e-7<=c["dt_s"]<=0.02 and 1<=c["steps"]<=500,"TIME")


def build_bundle(seed: str, beacon: dict, prereg_sha: str) -> dict:
    cases=generate(seed)
    require([c["family"] for c in cases]==list(FAMILIES),"FAMILY_ORDER")
    rows=[]
    for c in cases:
        validate_case(c)
        ref=reference(c)
        rows.append({"case":c,"runtime_input":normalize(c),"reference":ref,"case_sha256":sha(c),"reference_sha256":sha(ref)})
    bundle={"schema":SCHEMA,"generator_version":GENERATOR_VERSION,"preregistration_commit":prereg_sha,"beacon":beacon,"cases":rows,"checksum":""}
    bundle["checksum"]=sha({k:v for k,v in bundle.items() if k!="checksum"})
    return bundle


def protocol_test(prereg_path: Path) -> dict:
    prereg=json.loads(prereg_path.read_text())
    require(prereg["schema"]==PREREG_SCHEMA,"PREREG_SCHEMA")
    require(prereg["generator_version"]==GENERATOR_VERSION,"PREREG_VERSION")
    require(tuple(prereg["families"])==FAMILIES,"PREREG_FAMILIES")
    calibration_seeds=["CALIBRATION-R42-2026-09-20"] + [f"CALIBRATION-R42-STRESS-{i:02d}" for i in range(9)]
    bundles=[]; weak_ids=set()
    for seed in calibration_seeds:
        beacon={"source":"CALIBRATION","value":seed}
        a=build_bundle(seed,beacon,"0"*40)
        b=build_bundle(seed,beacon,"0"*40)
        require(a==b,"GENERATOR_NONDETERMINISTIC")
        require(len(a["cases"])==10,"CASE_COUNT")
        for row in a["cases"]:
            c=row["case"]
            if c["expectation"]=="PHYSICS":
                require(row["reference"]["electrical"]["condition_inf"]>=1.0,"E_CONDITION")
                require(row["reference"]["mechanical"]["condition_inf"]>=1.0,"M_CONDITION")
        near=next(r for r in a["cases"] if r["case"]["family"]==FAMILIES[4])
        require(max(near["reference"]["electrical"]["condition_inf"],near["reference"]["mechanical"]["condition_inf"])>1e4,"NEAR_SINGULAR_NOT_STRESSFUL")
        life=next(r for r in a["cases"] if r["case"]["family"]==FAMILIES[6])
        require(life["reference"]["lifecycle"]["failure_time_s"]<life["case"]["steps"]*life["case"]["dt_s"],"LIFECYCLE_CALIBRATION_NO_FAILURE")
        weak_ids.add(life["reference"]["lifecycle"]["failure_bond_id"])
        bundles.append(a)
    require(weak_ids=={"life0","life1","life2","life3"},"LIFECYCLE_CALIBRATION_COVERAGE")
    return {"protocol":"PASS","calibration_bundle_hash":sha(bundles[0]),"stress_bundle_hash":sha([b["checksum"] for b in bundles]),"stress_seed_count":len(bundles),"lifecycle_weak_ids":sorted(weak_ids),"case_count":len(bundles[0]["cases"]),"families":list(FAMILIES)}


def main() -> int:
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="cmd",required=True)
    a=sub.add_parser("protocol"); a.add_argument("--prereg",required=True)
    g=sub.add_parser("generate"); g.add_argument("--prereg",required=True); g.add_argument("--prereg-sha",required=True); g.add_argument("--beacon-json",required=True); g.add_argument("--out",required=True)
    v=sub.add_parser("verify"); v.add_argument("--challenge",required=True)
    args=p.parse_args()
    try:
        if args.cmd=="protocol":
            print(dumps(protocol_test(Path(args.prereg)))); return 0
        if args.cmd=="verify":
            bundle=json.loads(Path(args.challenge).read_text())
            require(bundle.get("schema")==SCHEMA,"CHALLENGE_SCHEMA")
            expected=bundle.get("checksum",""); raw={k:v for k,v in bundle.items() if k!="checksum"}
            require(expected==sha(raw),"CHALLENGE_CHECKSUM")
            for row in bundle.get("cases",[]):
                require(row.get("case_sha256")==sha(row["case"]),"CASE_CHECKSUM")
                require(row.get("reference_sha256")==sha(row["reference"]),"REFERENCE_CHECKSUM")
            print(dumps({"verify":"PASS","checksum":expected,"cases":len(bundle.get("cases",[]))})); return 0
        prereg=json.loads(Path(args.prereg).read_text()); require(prereg["schema"]==PREREG_SCHEMA,"PREREG_SCHEMA")
        beacon=json.loads(Path(args.beacon_json).read_text()); require(isinstance(beacon,dict) and isinstance(beacon.get("value"),str),"BEACON")
        seed=sha({"domain":"FABRIC-R4.2","prereg":args.prereg_sha,"beacon":beacon["value"]})
        bundle=build_bundle(seed,beacon,args.prereg_sha)
        Path(args.out).write_text(json.dumps(bundle,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n")
        print(dumps({"generated":"PASS","seed_commitment":sha(seed),"cases":len(bundle["cases"]),"bundle_checksum":bundle["checksum"]})); return 0
    except Exception as exc:
        print(dumps({"status":"FAIL","error":str(exc)})); return 2

if __name__=="__main__": raise SystemExit(main())
