from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))

from evo6_generated_outcomes_v1 import PHENOTYPES, build_artifact  # noqa: E402

EXPECTED_ARTIFACT_DIGEST = "c2c49218cc04dffaf8b036b0b2986672559ff8884e4be54d2149b61ba45f0f67"
EXPECTED_SURFACE_DIGEST = "e3fbaee778ba54708057e623fb6e515b7de6e7eedd20248d2a3daad45d3fb6de"


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
