"""ECO.EVO6/R1 - rule language compiler. Rules are DATA; fail-closed validation;
canonical application order = sorted by id; deterministic accumulation."""
from __future__ import annotations

WHEN_KEYS = {
    "neighbours", "water_dist_m", "in_water", "mineral", "wind_exposure",
    "sun_exposure", "snow_cover_frac", "soil_moisture_ppm",
}
NEIGHBOUR_KEYS = {"within_r", "taller_than_self", "count"}
TARGET_KEYS = {"form", "root_type", "pigment_class", "any"}
EFFECT_CHANNELS = {
    "vitality", "death_chance", "max_height_cap", "pigment_shift", "thorns",
    "seed_establishment",
}


def _reject(msg: str):
    raise ValueError(f"rule rejected fail-closed: {msg}")


def _numeric_predicate(spec, *, default_op: str = ">=") -> tuple[str, float]:
    if isinstance(spec, bool) or not isinstance(spec, (int, float, str)):
        _reject(f"numeric predicate expected, got {type(spec).__name__}")
    if isinstance(spec, (int, float)):
        return default_op, float(spec)
    text = spec.strip()
    for op in ("<=", ">=", "==", "<", ">"):
        if text.startswith(op):
            try:
                return op, float(text[len(op):].strip())
            except ValueError:
                _reject(f"invalid numeric predicate {spec!r}")
    try:
        return default_op, float(text)
    except ValueError:
        _reject(f"invalid numeric predicate {spec!r}")


def _compare_numeric(actual: float, spec, *, default_op: str = ">=") -> bool:
    op, expected = _numeric_predicate(spec, default_op=default_op)
    if op == "<":
        return actual < expected
    if op == "<=":
        return actual <= expected
    if op == ">":
        return actual > expected
    if op == ">=":
        return actual >= expected
    return actual == expected


def _validate_when(when: dict) -> None:
    if not isinstance(when, dict) or not when:
        _reject("when must be a non-empty object")
    for key, spec in when.items():
        if key not in WHEN_KEYS:
            _reject(f"unknown when key {key}")
        if key == "neighbours":
            if not isinstance(spec, dict):
                _reject("neighbours must be an object")
            for nk in spec:
                if nk not in NEIGHBOUR_KEYS:
                    _reject(f"unknown neighbour key {nk}")
        elif key == "mineral":
            if not isinstance(spec, dict):
                _reject("mineral must be an object")
            for mk in ("type", "richness"):
                if mk not in spec:
                    _reject("mineral requires type and richness")
            _numeric_predicate(spec["richness"], default_op=">")
        elif key != "in_water":
            _numeric_predicate(spec, default_op="<" if key == "water_dist_m" else ">=")


def _validate_target(target: dict) -> None:
    if not isinstance(target, dict):
        _reject("target must be an object")
    for key in target:
        if key not in TARGET_KEYS:
            _reject(f"unknown target key {key}")


def _validate_effect(effect: dict) -> None:
    if not isinstance(effect, dict) or not effect:
        _reject("effect must be non-empty")
    for channel, value in effect.items():
        if channel not in EFFECT_CHANNELS:
            _reject(f"unknown effect channel {channel}")
        if channel == "death_chance" and not 0.0 <= float(value) <= 1.0:
            _reject("death_chance out of range")
        if channel == "pigment_shift":
            if not isinstance(value, list) or len(value) != 3:
                _reject("pigment_shift must be [r,g,b]")


def compile_rules(rules_list: list[dict]) -> list[dict]:
    seen = set()
    compiled = []
    for raw in rules_list:
        rid = raw.get("id")
        if not isinstance(rid, str) or not rid:
            _reject("rule id required")
        if rid in seen:
            _reject(f"duplicate rule id {rid}")
        seen.add(rid)
        _validate_when(raw.get("when"))
        _validate_target(raw.get("target"))
        _validate_effect(raw.get("effect"))
        compiled.append({"id": rid, **raw})
    return sorted(compiled, key=lambda r: r["id"])


def _phenotype_matches(target: dict, phenotype: dict) -> bool:
    for key in target:
        if key == "any":
            continue
        if str(phenotype.get(key)) != str(target[key]):
            return False
    return True


def apply_rules(compiled: list[dict], site_context: dict, phenotype: dict) -> dict:
    effects = {
        "vitality": 0.0,
        "death_chance": 0.0,
        "thorns": 0,
        "seed_establishment": 0.0,
        "pigment_shift": [0.0, 0.0, 0.0],
    }
    eff_conditions = site_context.get("effective_conditions", site_context)
    features = site_context.get("features", site_context)
    for rule in compiled:
        target = rule["target"]
        if not _phenotype_matches(
            target if "any" in target else {k: v for k, v in target.items() if k != "any"} or {"any": True},
            phenotype,
        ):
            if "any" not in target and not _phenotype_matches(target, phenotype):
                continue
        matched = True
        for key, spec in rule["when"].items():
            if key == "neighbours":
                nb = features.get("neighbours", {})
                if "taller_than_self" in spec and not _compare_numeric(
                    float(nb.get("taller_than_self", 0)), spec["taller_than_self"], default_op=">="
                ):
                    matched = False
                if "count" in spec and not _compare_numeric(
                    float(nb.get("count", 0)), spec["count"], default_op=">="
                ):
                    matched = False
                if "within_r" in spec and abs(float(nb.get("within_r", -1.0)) - float(spec["within_r"])) > 1e-9:
                    matched = False
            elif key == "water_dist_m":
                if "water_dist_m" not in features or not _compare_numeric(
                    float(features["water_dist_m"]), spec, default_op="<"
                ):
                    matched = False
            elif key == "in_water":
                if bool(features.get("in_water", False)) != bool(spec):
                    matched = False
            elif key == "mineral":
                dep = features.get("mineral_deposit") or {}
                if str(dep.get("type")) != str(spec["type"]) or not _compare_numeric(
                    float(dep.get("richness", 0.0)), spec["richness"], default_op=">"
                ):
                    matched = False
            else:
                if key not in eff_conditions or not _compare_numeric(
                    float(eff_conditions[key]), spec, default_op=">="
                ):
                    matched = False
        if not matched:
            continue
        for channel, value in rule["effect"].items():
            if channel == "pigment_shift":
                effects[channel] = [effects[channel][i] + float(value[i]) for i in range(3)]
            else:
                effects[channel] = effects.get(channel, 0.0) + float(value)
    return effects
