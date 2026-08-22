"""Tests for ECO.EVO5/A genes block. Run directly: python test_evo5_genes_block.py"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_genes_block_v1 import (  # noqa: E402
    build_block, clamp_gene, derive_initial_genes, expressed, vigor_multiplier,
)

SITE_IRON = {"mineral_type": "iron_vein", "effective_conditions": {"mineral_richness_ppm": 360000}}
SITE_PLAIN = {"mineral_type": "", "effective_conditions": {"mineral_richness_ppm": 0}}
IRON_REQ = {"mineral_type": "iron_vein", "min_mineral_richness_ppm": 300000}


def _eq(label, ok):
    if not ok:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    g1 = derive_initial_genes("a4c391bddeadbeef")
    g2 = derive_initial_genes("a4c391bddeadbeef")
    _eq("checksum-keyed determinism", g1 == g2 and set(g1) == {"defense_intensity", "toxicity", "nutrient_value", "regrowth_rate", "leaf_archetype_gene", "hue_gene", "thorn_gene"})
    _eq("bounds hold on 200 checksums", all(clamp_gene(n, v) == v for cs in (f"ck{i:04x}" for i in range(200)) for n, v in derive_initial_genes(cs).items()))
    _eq("clamp out-of-range", clamp_gene("defense_intensity", 5.0) == 0.95 and clamp_gene("nutrient_value", -1.0) == 0.1)
    _eq("unconditional gene expresses anywhere", expressed({"expression_requirements": None}, SITE_PLAIN))
    _eq("gated gene silent on plain", not expressed({"expression_requirements": IRON_REQ}, SITE_PLAIN))
    _eq("gated gene expresses on iron+richness", expressed({"expression_requirements": IRON_REQ}, SITE_IRON))
    _eq("gated gene silent when richness low", not expressed({"expression_requirements": {**IRON_REQ, "min_mineral_richness_ppm": 400000}}, SITE_IRON))
    _eq("pricing monotone in defense", vigor_multiplier({"defense_intensity": 0.5}) < vigor_multiplier({"defense_intensity": 0.1}))
    _eq("pricing monotone in toxicity", vigor_multiplier({"toxicity": 0.5}) < vigor_multiplier({"toxicity": 0.1}))
    _eq("pricing at gene bounds exact", vigor_multiplier({"defense_intensity": 0.95, "toxicity": 0.9}) == 0.535)
    block = build_block("a4c391bddeadbeef", {"defense_intensity": IRON_REQ})
    _eq("block schema + requirement recorded", block["genes"]["defense_intensity"]["expression_requirements"]["mineral_type"] == "iron_vein")
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
