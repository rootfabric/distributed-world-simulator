extends "res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd"
## R5.5 R2: authenticate every prefix endpoint used by a range query.
## The trusted seals are built outside the event path by the parent machine.
## No hidden part scan or full prefix verification occurs during local events.
const U55 = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const FIELDS := ["mass", "sx", "sy", "sz", "jxx", "jxy", "jxz", "jyy", "jyz", "jzz"]
var _trusted_endpoint_seals: Dictionary = {}
var verified_prefix_endpoints := 0

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
    # Reject unsupported endpoints instead of silently trusting unchecked data.
    for endpoint in [first, end_exclusive]:
        var key := str(endpoint)
        var expected := String(_trusted_endpoint_seals.get(key, ""))
        if expected.is_empty() or endpoint_seal(_r5_range_index, endpoint) != expected:
            return U55.failure("R5_5_PREFIX_INTEGRITY_MISMATCH", {"endpoint": endpoint})
    var result: Dictionary = super._r5_query(spec, first, end_exclusive)
    if result.success:
        verified_prefix_endpoints += 2
    return result
