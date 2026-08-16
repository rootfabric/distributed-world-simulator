extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd"

# Final P4 closure shim. Keep the fingerprint composition deliberately simple
# and unambiguous: the exact four immutable bindings are concatenated in a
# fixed order and hashed. This function is virtual through the inherited P4
# hardening layer, so all FAST_COMMIT duplicate checks and COMMITTED ACK checks
# use this canonical implementation.


func _p4_compose_commit_fingerprint(
	package_checksum: String,
	prewarm_id: String,
	prewarm_checksum: String,
	directory_checksum: String
) -> String:
	return ("%s|%s|%s|%s" % [
		package_checksum,
		prewarm_id,
		prewarm_checksum,
		directory_checksum,
	]).sha256_text()
