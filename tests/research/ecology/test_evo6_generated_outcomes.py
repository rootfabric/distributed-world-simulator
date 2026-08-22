from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))

from evo6_generated_outcomes_v1 import PHENOTYPES, _site_context, build_artifact  # noqa: E402

EXPECTED_ARTIFACT_DIGEST = "e2b4de200e919546e00ce7606af0402019409f75435d739bbc963afded7953f1"
EXPECTED_SURFACE_DIGEST = "5e3469504d8fbfb38a0c13bb4ad6ceb300c29164a4b465d743f10b3bdd5fad34"


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    print(f"ok {label}")


def main() -> int:
    default = build_artifact()
    check(default["artifact_digest"] == EXPECTED_ARTIFACT_DIGEST, "default exact artifact digest pinned")
    check(default["selection_surface_digest"] == EXPECTED_SURFACE_DIGEST, "default selection surface digest pinned")

    a = build_artifact("evo6-r31-test")
    b = build_artifact("evo6-r31-test")
    c = build_artifact("evo6-r31-alt")
    check(a == b, "same seed is byte-structure deterministic")
    check(a["artifact_digest"] == b["artifact_digest"], "same seed digest stable")
    check(a["rule_digest"] != c["rule_digest"], "different seed changes generated rules")
    check(a["artifact_digest"] != c["artifact_digest"], "different seed changes artifact")
    check(a["metrics"]["cell_count"] == len(a["fates"]), "every terrain cell has a visual fate")
    check(len(a["selection_sites"]) == 4, "four deterministic selection sites materialized")
    check(
        default["metrics"]["neighbour_aggregate_cells"] == 196,
        "neighbour aggregates materialized for every terrain cell",
    )
    check(default["metrics"]["snow_context_cells"] == 12, "snow features bridged into rule-visible conditions")
    snow_context = _site_context(
        {"height": 1.0, "features": {"snow_cover_frac": 0.6}, "context": {"effective_conditions": {}}}
    )
    check(
        float(snow_context["effective_conditions"]["snow_cover_frac"]) == 0.6,
        "snow predicate is visible to the existing compiler",
    )
    check(
        default["metrics"]["generated_neighbour_rule_count"] > 0,
        "default generated set exercises neighbour predicates",
    )
    check(
        all(float(site["fitness_spread"]) > 0.0 for site in default["selection_sites"]),
        "selection sites exclude flat fitness surfaces",
    )

    expected = {f"{root}/{form}" for root, form in PHENOTYPES}
    for site in a["selection_sites"]:
        check(set(site["class_fitness"]) == expected, f"complete phenotype surface {site['site_id']}")
        check(
            all(float(value) > 0.0 for value in site["class_fitness"].values()),
            f"positive bounded fitness {site['site_id']}",
        )

    check(bool(a["metrics"]["selection_signal_present"]), "generated rules create a selectable phenotype signal")
    check(float(a["metrics"]["max_class_fitness_spread"]) > 0.0, "fitness surface is not flat")
    check(all(len(fate["pigment"]) == 3 for fate in a["fates"]), "visual pigment channel has fixed shape")
    encoded = json.dumps(a, sort_keys=True, separators=(",", ":"))
    check("evo5_r2_rule_outcomes" not in encoded, "generated artifact does not depend on static R2 outcomes")
    print("EVO6 R3.1 generated outcomes: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
