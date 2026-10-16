extends "res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd"
## R5.5 R3: code-anchored fixed-fixture prefix integrity. The frozen source
## formula and five canonical prefix moments are sealed in executable literals.
## Runtime-provided seals are corroborating metadata, never roots of trust.
## No full prefix scans occur during local events. This is NOT a generic ROM
## immutable-memory guarantee; code tamper and unsupported events are out of scope.
const U55 = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const FIELDS := ["mass", "sx", "sy", "sz", "jxx", "jxy", "jxz", "jyy", "jyz", "jzz"]
var _trusted_endpoint_seals: Dictionary = {}
var verified_prefix_endpoints := 0

# The fixed one-bond 100000-part fixture has only five consumed endpoints.
# Literal branches are intentionally NOT a mutable Dictionary/Array. Independently
# generated once from canonical Source.create_subject + RangeIndex.build on the
# canonical Godot 4.7.1 double executable, then pinned as product source code.
# Changing a runtime seal to match a poisoned prefix cannot change this anchor.
static func canonical_endpoint_seal(endpoint: int) -> String:
    match endpoint:
        0:
            return "3afd11b7c8aa4e984cf9c384e2e2097912033fae090a6c4d1b2c4a85b469182d"
        50000:
            return "c05be8d7d92d534ec870e0517f05cc0f728649603b5a2eba8aae717c1b4c0c64"
        50020:
            return "75480cd67866767e333d0f9f7e3b3602bf49ab72656c671102219436795f66e7"
        50007:
            return "a2db646807cf861e48dc88faca80898f73f0fffd3f1ff3e56f73e085a7cc92da"
        100000:
            return "8d41ac3163d34a41d43dbdfe2178eecbb5c2cd1b309f4aacfbbe934b51bd33c7"
        _:
            return ""

static func canonical_part_digest() -> String:
    return "76c1374738bfe43a9ed8dfa39d4bff49e02bf8f3ce1ff830b2ca47c214806ed6"

static func canonical_base_source_checksum() -> String:
    return "24e146e453bf414621ec721c01a6571a732e429c5de56cdb262fa24f3ac0f08e"

# R4 independent source-provenance witnesses for the exact frozen one-bond
# successor. All three are values from a canonical Godot 4.7.1 double source
# build, not derived from the runtime cache or its mutable cached hash.
# This is a fixed research fixture, not general tamper-proof ROM storage.
static func canonical_successor_subject_hash() -> String:
    return "30579f4208d5a033d3c6ad616702c44a271a6a4c1226d149ff05a325de7a7f3b"

static func canonical_successor_spec_checksum() -> String:
    return "c6378b862ce376f9e32ad671701b10ce7ca5896d549fd6df21893f094bc633c3"

static func canonical_successor_bond_digest() -> String:
    return "c515ae265c9a236d428b2a0db9075b049596adfbd170b2ab94688274d9132080"

static func endpoint_seal(index: Dictionary, endpoint: int) -> String:
    var prefix: Dictionary = index.get("prefix", {})
    var values: Array = []
    for field in FIELDS:
        var array = prefix.get(field)
        if typeof(array) != TYPE_PACKED_FLOAT64_ARRAY or endpoint < 0 or endpoint >= array.size():
            return ""
        values.append(float(array[endpoint]))
    return U55.canonical_hash({"endpoint": endpoint, "values": values})

func configure_seals(seals: Dictionary) -> void:
    # Read-only-by-ownership anchor. No full index copy per attempt.
    _trusted_endpoint_seals = seals.duplicate()

func _r5_query(spec: Dictionary, first: int, end_exclusive: int) -> Dictionary:
    # Fail closed when the generated structure changes: the code-backed seals
    # describe only the frozen 100000-part canonical source model.
    if int(spec.get("part_count", -1)) != 100000 or String(spec.get("expanded_part_digest", "")) != canonical_part_digest():
        return U55.failure("R5_5_PREFIX_SOURCE_ANCHOR_MISMATCH")
    for endpoint in [first, end_exclusive]:
        var expected := canonical_endpoint_seal(endpoint)
        var claimed := String(_trusted_endpoint_seals.get(str(endpoint), ""))
        var actual := endpoint_seal(_r5_range_index, endpoint)
        if expected.is_empty() or claimed != expected or actual != expected:
            return U55.failure("R5_5_PREFIX_INTEGRITY_MISMATCH", {"endpoint": endpoint})
    var result: Dictionary = super._r5_query(spec, first, end_exclusive)
    if result.success:
        verified_prefix_endpoints += 2
    return result
