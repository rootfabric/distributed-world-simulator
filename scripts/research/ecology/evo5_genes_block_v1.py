"""ECO.EVO5/A - Genes-v1 companion block keyed by genome_checksum.

Additive to (never inside) accepted PH0 traits. Each gene: bounds + optional
expression_requirements; a gene EXPRESSES only when the site context satisfies
them (mineral_type match + mineral_richness_ppm >= threshold), else neutral.
CAL1 pricing contract (declared): vigor_multiplier = clamp(1 - 0.30*defense
- 0.20*toxicity + 0.05*regrowth_rate, 0.40, 1.15). Initial values derived from
genome_checksum (sha256 _unit pattern) - deterministic, v0-style honesty.
"""
from __future__ import annotations

import hashlib

GENE_BOUNDS = {
    "defense_intensity": (0.0, 0.95), "toxicity": (0.0, 0.9),
    "nutrient_value": (0.1, 1.0), "regrowth_rate": (0.0, 1.0),
    "leaf_archetype_gene": (0, 2), "hue_gene": (0.0, 1.0), "thorn_gene": (0.0, 1.0),
}
NEUTRAL = {"defense_intensity": 0.0, "toxicity": 0.0, "nutrient_value": 0.4,
           "regrowth_rate": 0.0, "leaf_archetype_gene": 0, "hue_gene": 0.5, "thorn_gene": 0.0}


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def derive_initial_genes(genome_checksum: str) -> dict:
    genes = {}
    for i, name in enumerate(sorted(GENE_BOUNDS)):
        lo, hi = GENE_BOUNDS[name]
        raw = lo + (hi - lo) * _unit(f"{genome_checksum}|{name}|{i}")
        genes[name] = int(round(raw)) if name == "leaf_archetype_gene" else round(raw, 4)
    return genes


def clamp_gene(name: str, value):
    lo, hi = GENE_BOUNDS[name]
    value = int(value) if name == "leaf_archetype_gene" else float(value)
    return max(lo, min(hi, value))


def expressed(gene_record: dict, site_context: dict) -> bool:
    req = gene_record.get("expression_requirements")
    if not req:
        return True
    conditions = site_context.get("effective_conditions", {})
    if req.get("mineral_type") and str(req["mineral_type"]) != str(site_context.get("mineral_type", "")):
        return False
    threshold = int(req.get("min_mineral_richness_ppm", 0))
    if threshold and int(conditions.get("mineral_richness_ppm", 0)) < threshold:
        return False
    return True


def build_block(genome_checksum: str, requirements_by_gene: dict | None = None) -> dict:
    requirements = requirements_by_gene or {}
    block = {"schema": "distributed_world_simulator.ecology.evo5_genes_block.v1",
             "genome_checksum": genome_checksum, "genes": {}}
    for name in sorted(GENE_BOUNDS):
        record = {"value": derive_initial_genes(genome_checksum)[name],
                  "bounds": list(GENE_BOUNDS[name])}
        if name in requirements:
            record["expression_requirements"] = dict(requirements[name])
            record["expressed_at_reference_site"] = True
        block["genes"][name] = record
    return block


def vigor_multiplier(genes: dict) -> float:
    g = {k: NEUTRAL[k] if genes.get(k) is None else float(genes[k]) for k in ("defense_intensity", "toxicity", "regrowth_rate")}
    raw = 1.0 - 0.30 * g["defense_intensity"] - 0.20 * g["toxicity"] + 0.05 * g["regrowth_rate"]
    return round(max(0.40, min(1.15, raw)), 4)
