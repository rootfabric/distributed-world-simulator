extends SceneTree
const S = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failed := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("COMPLEX3-A0: " + label)
func _initialize() -> void:
	var hashes: Array = []
	for count in S.ALLOWED_COUNTS:
		var base := S.create_subject(count, false)
		check(base.success, "%d base source" % count)
		check(S.validate_subject(base, count == 5000).success, "%d source validation" % count)
		var successor := S.create_subject(count, true)
		check(successor.success and S.is_successor(base, successor), "%d canonical successor" % count)
		check(base.spec.expanded_part_digest == successor.spec.expanded_part_digest, "%d part identity preserved" % count)
		check(base.spec.expanded_bond_digest != successor.spec.expanded_bond_digest, "%d topology digest changes" % count)
		check(int(base.spec.part_count) == count and int(base.spec.bond_count) == count - 1, "%d counts" % count)
		check(S.part_id(count - 1).ends_with("%06d" % (count - 1)), "%d addressable last identity" % count)
		var whole := S.aggregate_span(base.spec, 0, count)
		check(whole.success and int(whole.details.descriptor.part_count) == count, "%d streaming aggregate" % count)
		hashes.append(U.canonical_hash({"source": base.spec.checksum, "aggregate": whole.details.descriptor.checksum}))
	check(not S.create_subject(4999, false).success, "undeclared scale rejected")
	var tampered := S.create_subject(5000, false)
	tampered.spec.break_index += 1
	tampered.spec.checksum = U.compute_checksum(tampered.spec)
	check(not S.validate_subject(tampered, false).success, "rehashed topology contradiction rejected")
	print("COMPLEX3_A0_HASH=" + U.canonical_hash(hashes))
	if not failed:
		print("FABRIC COMPLEX3-A0: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)
