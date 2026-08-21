"""ECO.EVO4/E4.B1 - extended species catalog generator.

Reads the ACCEPTED persisted SpeciesCatalog (never modified), attaches the
frozen evo4-b0-derivation-v0 DevelopmentTraits to each entry as an additive
research-layer block, and emits validation/ecology/
evo4_b1_dev_traits_extended_catalog.v1.json with full provenance.
Deterministic: byte-identical output across fresh processes.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE_CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
OUTPUT_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"

DOC_SCHEMA = "distributed_world_simulator.ecology.evo4_b1_extended_species_catalog.v1"
PROVENANCE_SCHEMA = "distributed_world_simulator.ecology.evo4_b1_catalog_extension.v1"
VERSION = "1.0.0"
DERIVATION_RULE_ID = "evo4-b0-derivation-v0"


def _load_derivation_module():
    try:
        import evo4_bridge_derivation_v0 as derivation  # type: ignore

        return derivation
    except ImportError:
        pass
    module_path = Path(__file__).resolve().parent / "evo4_bridge_derivation_v0.py"
    spec = importlib.util.spec_from_file_location("evo4_bridge_derivation_v0", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load derivation module from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def build_document(source_bytes: bytes) -> dict:
    derivation = _load_derivation_module()
    catalog = json.loads(source_bytes.decode("utf-8"))
    entries_out = []
    for index, entry in enumerate(catalog["entries"]):
        genome = entry["genome"]
        traits = derivation.derive_traits(str(genome["genome_id"]), genome)
        seed = derivation.demo_individual_seed(
            catalog["bake_id"], str(entry["lineage_id"]), str(genome["checksum"]), index
        )
        extended = dict(entry)
        extended["development_traits"] = traits
        extended["evo4_bridge"] = {
            "derivation_rule_id": DERIVATION_RULE_ID,
            "individual_seed_demo": seed,
            "source_genome_checksum": str(genome["checksum"]),
        }
        entries_out.append(extended)
    return {
        "schema": DOC_SCHEMA,
        "version": VERSION,
        "derived_representation": True,
        "extension_provenance": {
            "schema": PROVENANCE_SCHEMA,
            "version": VERSION,
            "source_catalog_schema": catalog["schema"],
            "source_catalog_hash": catalog["catalog_hash"],
            "source_catalog_sha256": hashlib.sha256(source_bytes).hexdigest(),
            "source_catalog_path": "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json",
            "derivation_rule_id": DERIVATION_RULE_ID,
            "generator": "evo4_bridge_catalog_extender_v1.py",
            "generator_version": VERSION,
        },
        "entries": entries_out,
    }


def main() -> int:
    source_bytes = SOURCE_CATALOG_PATH.read_bytes()
    document = build_document(source_bytes)
    payload = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(payload, encoding="utf-8", newline="\n")
    digest = hashlib.sha256(OUTPUT_PATH.read_bytes()).hexdigest()
    print(f"EVO4_B1_EXTENDED_CATALOG_WRITTEN entries={len(document['entries'])} sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
