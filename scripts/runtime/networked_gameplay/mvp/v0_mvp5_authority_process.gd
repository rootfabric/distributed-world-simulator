extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_authority_process.gd"

const SharedMaterial5 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_material_output_authority.gd")

func create_shared_dig():
	return SharedMaterial5.new()

func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind != "MVP5_MATERIAL": return super.handle_rpc(body)
	if closing_ms > 0 or _shared_dig4 == null:
		return Protocol.failure("MVP5_MATERIAL_OWNER_UNAVAILABLE")
	var ingested: Dictionary = ingest_decisions(body)
	if not bool(ingested.get("success", false)): return ingested
	var actor := String(body.get("actor", ""))
	if actor not in ["a", "b"] or body.get("session") != Protocol.session(cfg, actor):
		return Protocol.failure("MVP5_NATIVE_PEER_BINDING_INVALID")
	var result: Dictionary = _shared_dig4.material_snapshot(actor, Protocol.session(cfg, actor))
	return native_envelope(kind, actor, result)
