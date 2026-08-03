extends RefCounted

const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")
const ProtocolManifestScript = preload("res://scripts/network/observability/network_protocol_manifest.gd")

const CHECKPOINT: String = "v16.14.0-network-nx4-client-prediction-reconciliation"
const BUILD_ID: String = "nx4-client-prediction-reconciliation"
const SOURCE_COMMIT: String = "ac8ae0afdd47e0f290dbbc8af396add7aba60cda"
const DEFAULT_SESSION_TOKEN: String = "session-id/local-development"


static func create_fingerprint(config: Dictionary = {}) -> Dictionary:
	var world_id: String = String(config.get("world_id", "")).strip_edges().to_lower()
	if world_id.is_empty():
		world_id = "playground" if bool(config.get("playable_sandbox", false)) else "moon"
	var build_id: String = String(config.get("network_build_id", BUILD_ID)).strip_edges().to_lower()
	var git_commit: String = String(config.get("network_git_commit", SOURCE_COMMIT)).strip_edges().to_lower()
	var protocol_hash: String = String(
		config.get("network_protocol_hash", ProtocolManifestScript.current_protocol_hash())
	).strip_edges().to_lower()
	var session_token: String = String(
		config.get("network_session_token", DEFAULT_SESSION_TOKEN)
	).strip_edges().to_lower()
	return FingerprintScript.create(build_id, git_commit, protocol_hash, world_id, session_token)


static func validate_config(config: Dictionary = {}) -> Dictionary:
	var fingerprint: Dictionary = create_fingerprint(config)
	var validation: Dictionary = FingerprintScript.validate(fingerprint)
	if not bool(validation.get("success", false)):
		return {
			"success": false,
			"error_code": "INVALID_NETWORK_RUNTIME_IDENTITY",
			"details": {"cause": validation, "fingerprint": fingerprint},
		}
	return {
		"success": true,
		"error_code": "",
		"details": {
			"fingerprint": fingerprint,
			"protocol_manifest": ProtocolManifestScript.create(),
		},
	}
