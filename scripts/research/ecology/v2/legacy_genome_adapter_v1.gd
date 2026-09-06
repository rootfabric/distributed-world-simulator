extends RefCounted
## Lossless preservation, NOT a fabricated modular migration of legacy scalar proxies.
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Extension = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const SCHEMA := "dws.ecology.legacy-preservation-envelope.v1"
const MAX_BYTES := 1048576

static func preserve(bundle: Dictionary) -> Dictionary:
	if not valid(bundle) or not _safe_value(bundle): return {}
	var bytes := var_to_bytes(bundle)
	if bytes.size() > MAX_BYTES: return {}
	return {"schema": SCHEMA, "encoding": "GODOT_VARIANT_SAFE", "payload": Marshalls.raw_to_base64(bytes), "sha256": _hash(bytes), "coverage": {"development": "LEGACY_V1_ONLY", "root_extent": "AGGREGATE_ONLY", "modular_body": "NOT_INFERRED", "conversion": "REQUIRES_EXPLICIT_SEMANTIC_MIGRATION"}}

static func restore(envelope: Dictionary) -> Dictionary:
	if envelope.get("schema") != SCHEMA or envelope.get("encoding") != "GODOT_VARIANT_SAFE" or not envelope.get("payload") is String:
		return {}
	if envelope.payload.length() > MAX_BYTES * 2: return {}
	var bytes := Marshalls.base64_to_raw(envelope.payload)
	if bytes.size() > MAX_BYTES or _hash(bytes) != envelope.get("sha256"): return {}
	# bytes_to_var does not deserialize Objects (unlike bytes_to_var_with_objects).
	var value: Variant = bytes_to_var(bytes)
	return value if value is Dictionary and valid(value) and _safe_value(value) else {}

static func valid(bundle: Dictionary) -> bool:
	for name in ["genome", "dev_traits", "ext_traits"]:
		if not bundle.get(name) is Dictionary: return false
	return bool(Genome.validate(bundle.genome).get("success",false)) and bool(Traits.validate(bundle.dev_traits).get("success",false)) and bool(Extension.validate(bundle.ext_traits).get("success",false))

static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _safe_value(value: Variant, depth: int = 0) -> bool:
	if depth > 24: return false
	if value is Array or value is Dictionary:
		if value.size() > 4096: return false
		for key in range(value.size()) if value is Array else value.keys():
			if value is Dictionary and not key is String: return false
			if not _safe_value(value[key], depth + 1): return false
		return true
	if typeof(value) == TYPE_FLOAT: return is_finite(value)
	return typeof(value) in [TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_NIL]
