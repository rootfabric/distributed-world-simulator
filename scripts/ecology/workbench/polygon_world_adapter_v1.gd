# EcologyWorkbench PolygonWorldAdapter v1 (P12, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: WORLD_COMPAT mode adapter between the polygon workbench and the A10
#   world binding contracts. THIN COMPOSITION ONLY: every authority decision
#   delegates to an existing A10 contract; the adapter owns no world state
#   truth of its own.
#   - World/environment authority source: authority_region_descriptor (ACTIVE),
#     world_binding_v1.bind_matter_site / admit_cursor,
#     matter_resource_mapping_v1.create / admit_material_batch (explicit-only).
#   - Ecology (genome/body/lifecycle) stays the canonical A1-A9 pipeline inside
#     ExperimentController; ONLY the environment sampling authority changes.
#   - Damage (§25): external trusted DamageRecord -> world_binding_v1
#     projection -> body_construction_binding_v1 overlay. The historical
#     BodyGraph is never modified; effective_function is presentation.
#   - Region handoff (§24): world_seam_binding_v1 prepare/admit over the
#     production handoff ticket; ecology_region_ownership_v1 production line
#     is composed (observed, not replaced).
# Layer: 2 (SIMULATION / ORCHESTRATION adapter; no new truth, no formulas).
# Forbidden (and absent): PolygonRegion/PolygonMatter/PolygonHandoff ownership,
# polygon persistence truth, guessed matter<->ecology semantics.
# Documented canonical gaps (A11/canonical backlog):
#   - No canonical Matter -> A4 signal (light/temperature) mapping exists;
#     WORLD_COMPAT signals remain explicit manifest declarations (zone
#     light/temperature fields). Stocks, in contrast, come exclusively from
#     matter mapping admissions (WORLD_COMPAT manifests must declare zero
#     zone stocks — enforced fail-closed below).
#   - Checkpoint identity across the seam uses ExperimentController
#     serialize_state (P8): the A8 snapshot_seam_v1 ecology payload schema is
#     bound to the A7 observatory treatment model and cannot carry controller
#     field+population+feedback state; the controller envelope is the
#     canonical fit and is used instead.
class_name EcoWorkbenchPolygonWorldAdapterV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const WorldBinding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const SeamBinding = preload("res://scripts/research/ecology/v2/world_seam_binding_v1.gd")
const Mapping = preload("res://scripts/research/ecology/v2/matter_resource_mapping_v1.gd")
const BodyBinding = preload("res://scripts/research/ecology/v2/body_construction_binding_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Ownership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")

const STATE_SCHEMA := "dws.ecology.workbench.world-adapter-state.v1"
const STATE_ENVELOPE_SCHEMA := "dws.ecology.workbench.world-adapter-state-envelope.v1"
const AUTHORITY_FIELDS := ["region", "entity_id", "owner_id", "catalog", "mapping_entries"]
const STOCK_FIELDS := ["water_mg", "nutrient_mg", "organic_mg"]

var _manifest: Dictionary = {}
var _manifest_hash := ""
var _region: Dictionary = {}
var _cursor: Dictionary = {}
var _catalog: Dictionary = {}
var _mapping: Dictionary = {}
var _map_id := "eco-map/world-compat"
var _site_binding: Dictionary = {}
# batch_id -> {"batch": ..., "checksum": ..., "applied": bool, "admission": ...}
var _batches: Dictionary = {}
var _admitted_resources := FieldContract.stock()
# individual_id -> {"modules", "snapshot", "binding", "overlay", "event"}
var _damage: Dictionary = {}
var last_error := ""

## Configure the world authority for one WORLD_COMPAT experiment.
## authority (dependency-injected, explicit):
##   region         ACTIVE authority_region_descriptor (required)
##   entity_id      world-side entity identifier for the cursor (required)
##   owner_id       must equal region.owner_node_id (required)
##   owner_epoch    defaults to region.authority_epoch
##   revision/clock/ecology_step  cursor bookkeeping, default 0
##   catalog        production matter catalog (required)
##   map_id         optional mapping id (default eco-map/world-compat)
##   mapping_entries explicit material->resource entries, possibly empty (required)
##   matter_query   optional MatterQueryResult; when present the adapter also
##                  builds a world_binding_v1 matter site binding.
func configure(manifest: Dictionary, authority: Dictionary) -> Dictionary:
	var manifest_error := Manifest.validate(manifest)
	if not manifest_error.is_empty():
		return _fail("ADAPTER_MANIFEST:" + manifest_error)
	if String(manifest.mode) != "WORLD_COMPAT":
		return _fail("ADAPTER_MODE_NOT_WORLD_COMPAT")
	if not authority is Dictionary:
		return _fail("ADAPTER_AUTHORITY_FIELDS")
	for field in AUTHORITY_FIELDS:
		if not authority.has(field):
			return _fail("ADAPTER_AUTHORITY_FIELDS:" + field)
	var region: Dictionary = authority.region
	if not bool(Region.validate(region).get("success", false)):
		return _fail("ADAPTER_REGION_INVALID")
	if String(region.lifecycle_state) != "ACTIVE":
		return _fail("ADAPTER_REGION_NOT_ACTIVE")
	if not C.identifier(String(authority.entity_id)) or not C.identifier(String(authority.owner_id)):
		return _fail("ADAPTER_AUTHORITY_IDENTITY")
	if String(authority.owner_id) != String(region.owner_node_id):
		return _fail("ADAPTER_AUTHORITY_OWNER_MISMATCH")
	var owner_epoch: int = int(region.authority_epoch) if not authority.has("owner_epoch") else int(authority.owner_epoch)
	var cursor := {
		"entity_id": String(authority.entity_id),
		"region_id": String(region.region_id),
		"owner_id": String(authority.owner_id),
		"owner_epoch": owner_epoch,
		"revision": int(authority.get("revision", 0)),
		"clock": int(authority.get("clock", 0)),
		"ecology_step": int(authority.get("ecology_step", 0)),
	}
	var admitted := WorldBinding.admit_cursor(cursor, region)
	if not bool(admitted.get("success", false)):
		return _fail("ADAPTER_CURSOR:" + String(admitted.get("error", "?")))
	var catalog: Dictionary = authority.catalog
	var entries: Array = authority.mapping_entries
	if not entries is Array:
		return _fail("ADAPTER_MAPPING_ENTRIES")
	var map_id := String(authority.get("map_id", "eco-map/world-compat"))
	var mapping := Mapping.create(catalog, map_id, entries)
	if mapping.is_empty():
		return _fail("ADAPTER_MAPPING_INVALID")
	_manifest = manifest.duplicate(true)
	_manifest_hash = Manifest.canonical_hash(manifest)
	_region = region.duplicate(true)
	_cursor = cursor
	_catalog = catalog.duplicate(true)
	_mapping = mapping
	_map_id = map_id
	_site_binding = {}
	_batches = {}
	_admitted_resources = FieldContract.stock()
	_damage = {}
	last_error = ""
	return {"success": true, "cursor": cursor.duplicate(true), "map_checksum": String(mapping.checksum)}

## Controller-side compatibility check (fail-closed gate used by
## ExperimentController.initialize in WORLD_COMPAT mode): the manifest must be
## the configured one and must not declare zone stocks (stock authority is the
## matter mapping alone; dual truth is forbidden).
func world_manifest_compatible(manifest: Dictionary) -> Dictionary:
	if _manifest.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	if Manifest.canonical_hash(manifest) != _manifest_hash:
		return _fail("ADAPTER_MANIFEST_MISMATCH")
	for zone in manifest.environment.zones:
		for stock_field in STOCK_FIELDS:
			if int(zone[stock_field]) != 0:
				return _fail("ADAPTER_ZONE_STOCK_DUAL_TRUTH:" + String(zone.id) + "/" + stock_field)
	return {"success": true}

## ACTIVE-only execution admission (called by the controller before EVERY
## WORLD_COMPAT tick). On success the world-side cursor bookkeeping advances
## (clock/ecology_step/revision); on failure nothing changes.
func admit_execution() -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	var admitted := WorldBinding.admit_cursor(_cursor, _region)
	if not bool(admitted.get("success", false)):
		return _fail(String(admitted.get("error", "A10_CURSOR")))
	_cursor.revision = int(_cursor.revision) + 1
	_cursor.clock = int(_cursor.clock) + 1
	_cursor.ecology_step = int(_cursor.ecology_step) + 1
	return {"success": true, "cursor": cursor()}

## Replace the tracked region descriptor (host reflects world-side lifecycle
## changes: ACTIVE -> WARM handoff prep, post-commit ACTIVE, etc.). The new
## descriptor is validated; execution admission decides executability.
func set_region(region: Dictionary) -> Dictionary:
	if not bool(Region.validate(region).get("success", false)):
		return _fail("ADAPTER_REGION_INVALID")
	if String(region.region_id) != String(_region.region_id):
		return _fail("ADAPTER_REGION_IDENTITY")
	if String(region.universe_id) != String(_region.universe_id) \
			or String(region.instance_id) != String(_region.instance_id) \
			or String(region.space_id) != String(_region.space_id):
		return _fail("ADAPTER_REGION_SPACE")
	_region = region.duplicate(true)
	return {"success": true}

## Optional matter site binding (world_binding_v1.bind_matter_site): binds a
## materialized Matter point sample to the cursor/region for provenance.
## NOTE: the binding carries NO resource stock authority
## (resource_stock_authority = NOT_DERIVED_FROM_POINT_SAMPLE).
func bind_site(matter_query: Dictionary) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	var bound := WorldBinding.bind_matter_site(matter_query, _region, _cursor)
	if not bool(bound.get("success", false)):
		return _fail(String(bound.get("error", "A10_SITE")))
	_site_binding = bound.binding.duplicate(true)
	return {"success": true, "binding_hash": String(_site_binding.binding_hash)}

## Register an external trusted material batch (checksum = trusted anchor).
## Admits it through matter_resource_mapping_v1 immediately (explicit-only:
## unmapped materials stay unmapped; nothing is guessed).
func add_batch(batch: Dictionary, expected_batch_checksum: String) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	var admitted_batch := Mapping.admit_material_batch(batch, _catalog, _mapping, expected_batch_checksum)
	if not bool(admitted_batch.get("success", false)):
		return _fail(String(admitted_batch.get("error", "A10_R2")))
	var admission: Dictionary = admitted_batch.admission
	var batch_id := String(admission.batch_id)
	if _batches.has(batch_id):
		var existing: Dictionary = _batches[batch_id]
		if String(existing.checksum) != String(admission.batch_checksum) or existing.admission != admission:
			return _fail("ADAPTER_BATCH_ID_CONFLICT:" + batch_id)
		# Exact replay is idempotent and preserves the original applied flag.
		return {"success": true, "admission": existing.admission.duplicate(true), "replay": true, "applied": bool(existing.applied)}
	_batches[batch_id] = {
		"checksum": String(admission.batch_checksum),
		"applied": false,
		"admission": admission.duplicate(true),
	}
	return {"success": true, "admission": admission.duplicate(true), "replay": false, "applied": false}

## Push all not-yet-applied admitted batches into the controller field through
## the canonical owner-write bridge (ExperimentController.apply_world_stocks).
## Aggregates per-resource totals across admissions (mass conservation is
## already guaranteed per admission by the mapping contract).
func apply_environment(controller: Object) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	if controller == null or not controller.has_method("apply_world_stocks"):
		return _fail("ADAPTER_CONTROLLER")
	# Delta-only: cumulative admitted resources are observability, never an
	# amount to deposit again. Bookkeeping is committed only after the canonical
	# field write succeeds.
	var delta := FieldContract.stock()
	var applied_ids: Array = []
	for batch_id in _batches.keys():
		var row: Dictionary = _batches[batch_id]
		if bool(row.applied):
			continue
		for resource in FieldContract.RESOURCES:
			delta[resource] = int(delta[resource]) + int(row.admission.resources[resource])
		applied_ids.append(String(batch_id))
	if applied_ids.is_empty():
		return {"success": true, "applied_batches": [], "resources": _admitted_resources.duplicate(true), "applied": false}
	applied_ids.sort()
	var source_tag := "matter-delta/%s/%s" % [_map_id, C.digest(applied_ids).substr(0, 16)]
	var result: Dictionary = controller.apply_world_stocks(delta, source_tag)
	if not bool(result.get("success", false)):
		return _fail("ADAPTER_ENVIRONMENT_APPLY:" + String(result.get("error", "?")))
	for batch_id in applied_ids:
		_batches[batch_id].applied = true
	for resource in FieldContract.RESOURCES:
		_admitted_resources[resource] = int(_admitted_resources[resource]) + int(delta[resource])
	return {
		"success": true,
		"applied_batches": applied_ids,
		"resources": _admitted_resources.duplicate(true),
		"delta_resources": delta.duplicate(true),
		"applied": true,
		"field_hash": String(result.get("field_hash", "")),
	}

# --- damage integration (§25) --------------------------------------------------

## Accept an EXTERNAL trusted DamageRecord (checksum anchor), project it onto
## the organism's historical BodyGraph modules (world_binding_v1), and build a
## persistent body_construction_binding_v1 binding + damage overlay. The
## historical BodyGraph is copied read-only and never modified.
## part_to_module: {"part/<id>": "<module id>"} explicit, one-to-one.
func register_damage(controller: Object, individual_id: String, request: Dictionary, record: Dictionary, source_snapshot: Dictionary, part_to_module: Dictionary, expected_record_checksum: String) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	if controller == null or not controller.has_method("debug_state"):
		return _fail("ADAPTER_CONTROLLER")
	var entry := _population_entry(controller.debug_state(), individual_id)
	if entry.is_empty():
		return _fail("ADAPTER_ORGANISM_UNKNOWN:" + individual_id)
	var modules: Array = entry.state.development.modules
	if not Body.validate(modules).is_empty():
		return _fail("ADAPTER_BODY_INVALID")
	var projected := WorldBinding.project_construction_damage(request, record, source_snapshot, modules, part_to_module, expected_record_checksum)
	if not bool(projected.get("success", false)):
		return _fail(String(projected.get("error", "A10_DAMAGE")))
	var event: Dictionary = projected.event
	var binding := BodyBinding.create_binding(modules, source_snapshot, part_to_module)
	if binding.is_empty():
		return _fail("ADAPTER_DAMAGE_BINDING")
	var overlay := BodyBinding.create_overlay(binding, modules, source_snapshot)
	if overlay.is_empty():
		return _fail("ADAPTER_DAMAGE_OVERLAY")
	_damage[String(individual_id)] = {
		"modules": modules.duplicate(true),
		"snapshot": source_snapshot.duplicate(true),
		"binding": binding,
		"overlay": overlay,
		"event": event.duplicate(true),
		# Caller-owned trust anchor captured at admission time. apply_damage()
		# must never derive the expected value from the event being checked.
		"trusted_event_binding_hash": String(event.binding_hash),
	}
	return {"success": true, "event": event.duplicate(true), "binding": binding.duplicate(true), "overlay": overlay.duplicate(true)}

## Apply the previously projected damage event to the overlay. The projected
## event's binding_hash is the trusted anchor (it was sealed from the trusted
## record). Idempotent per damage_id (R4 replay contract).
func apply_damage(individual_id: String) -> Dictionary:
	if not _damage.has(String(individual_id)):
		return _fail("ADAPTER_DAMAGE_UNKNOWN:" + String(individual_id))
	var row: Dictionary = _damage[String(individual_id)]
	var applied := BodyBinding.apply_damage(row.binding, row.overlay, row.modules, row.snapshot, row.event, String(row.trusted_event_binding_hash))
	if not bool(applied.get("success", false)):
		return _fail(String(applied.get("error", "A10_R4")))
	row.overlay = applied.overlay.duplicate(true)
	return {"success": true, "replay": bool(applied.replay), "overlay": row.overlay.duplicate(true)}

## Effective active body function (presentation projection, R4).
func effective_function(individual_id: String) -> Dictionary:
	if not _damage.has(String(individual_id)):
		return {}
	var row: Dictionary = _damage[String(individual_id)]
	return BodyBinding.effective_function(row.binding, row.overlay, row.modules, row.snapshot)

func has_overlay(individual_id: String) -> bool:
	return _damage.has(String(individual_id))

## Three-layer damage view for the inspector (§25): historical topology /
## damage overlay / effective active modules — SEPARATE layers; the historical
## topology_signature is a copy and can never be modified by the overlay.
func damage_view(individual_id: String) -> Dictionary:
	if not _damage.has(String(individual_id)):
		return {}
	var row: Dictionary = _damage[String(individual_id)]
	if not BodyBinding.validate_overlay(row.overlay, row.binding, row.modules, row.snapshot).is_empty():
		return {}
	var effective := effective_function(individual_id)
	if effective.is_empty():
		return {}
	return {
		"overlay_present": true,
		"historical": {
			"topology_signature": Body.topology_signature(row.modules),
			"module_count": int(row.modules.size()),
			"body_hash": String(row.binding.body_hash),
		},
		"overlay": {
			"revision": int(row.overlay.revision),
			"degraded_modules": Array(row.overlay.degraded_modules).duplicate(),
			"destroyed_modules": Array(row.overlay.destroyed_modules).duplicate(),
			"disabled_modules": Array(row.overlay.disabled_modules).duplicate(),
			"overlay_checksum": String(row.overlay.checksum),
		},
		"effective": {
			"active_module_ids": Array(effective.active_module_ids).duplicate(),
			"active_module_count": int(effective.active_module_count),
			"functional_hash": String(effective.functional_hash),
		},
	}

# --- region handoff seam (§24) ---------------------------------------------------

## WARM handoff preparation: world_seam_binding_v1.prepare_ticket over the
## current cursor + ACTIVE source region and a WARM target region (different
## owner, newer epoch, same spatial region). Read-only: the cursor does not move.
func prepare_region_handoff(target_region_warm: Dictionary, expires_at_tick: int) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	var prepared := SeamBinding.prepare_ticket(_cursor, _region, target_region_warm, int(_cursor.clock) + 1, expires_at_tick)
	if not bool(prepared.get("success", false)):
		return _fail(String(prepared.get("error", "A10_R3")))
	return {"success": true, "ticket": prepared.ticket.duplicate(true)}

## Post-commit admission: admit_committed validates the COMMITTED ticket, the
## target ACTIVE region and the new cursor; on success the adapter authority
## switches to the target region (old owner is rejected from here on).
func commit_region_handoff(target_region_active: Dictionary, ticket_committed: Dictionary) -> Dictionary:
	if _region.is_empty():
		return _fail("ADAPTER_NOT_CONFIGURED")
	var next_cursor := _cursor.duplicate(true)
	next_cursor.owner_id = String(target_region_active.get("owner_node_id", ""))
	next_cursor.owner_epoch = int(target_region_active.get("authority_epoch", -1))
	var admitted := SeamBinding.admit_committed(next_cursor, target_region_active, ticket_committed)
	if not bool(admitted.get("success", false)):
		return _fail(String(admitted.get("error", "A10_R3")))
	var swapped := set_region(target_region_active)
	if not bool(swapped.get("success", false)):
		return _fail(String(swapped.get("error", "ADAPTER_REGION")))
	_cursor = next_cursor
	return {"success": true, "cursor": cursor()}

# --- production ownership line (composed, observed — thin passthroughs) --------

## Production region ownership handoff package (ecology_region_ownership_v1).
## The production P4.5 line is composed beside the A10 seam: it owns server
## fencing epochs; the A10 seam owns region authority. No truth is duplicated.
static func production_prepare_handoff(ownership_state: Dictionary, target_owner_server_id: String) -> Dictionary:
	var package := Ownership.prepare_handoff(ownership_state, target_owner_server_id)
	if package.is_empty():
		return {"success": false, "error": "ADAPTER_PRODUCTION_PREPARE"}
	return {"success": true, "package": package}

static func production_accept_handoff(ownership_state: Dictionary, package: Dictionary, accepting_server_id: String) -> Dictionary:
	var target := Ownership.accept_handoff(ownership_state, package, accepting_server_id)
	if target.is_empty():
		return {"success": false, "error": "ADAPTER_PRODUCTION_ACCEPT"}
	return {"success": true, "ownership": target}

# --- durable WORLD_COMPAT state -------------------------------------------------

## Export orchestration/authority state that is external to the biological
## runtime but required to continue the exact same WORLD_COMPAT experiment.
## This envelope never becomes ecology biology truth; the shared runtime
## checkpoint binds it as an externally anchored companion payload.
func export_state() -> Dictionary:
	if _region.is_empty():
		return {}
	# The physical-world payload legitimately contains finite floats (Matter
	# samples/catalog and Construction snapshots). It therefore keeps its own
	# JSON canonicalization domain and crosses into the integer-only ecology
	# checkpoint as opaque canonical TEXT plus a text hash.
	var raw := {
		"schema": STATE_SCHEMA,
		"manifest_hash": _manifest_hash,
		"region": _region.duplicate(true),
		"cursor": _cursor.duplicate(true),
		"catalog": _catalog.duplicate(true),
		"mapping": _mapping.duplicate(true),
		"map_id": _map_id,
		"site_binding": _site_binding.duplicate(true),
		"batches": _batches.duplicate(true),
		"admitted_resources": _admitted_resources.duplicate(true),
		"damage": _damage.duplicate(true),
		"checksum": "",
	}
	raw.checksum = _state_checksum(raw)
	var error := _validate_raw_state(raw)
	if not error.is_empty():
		return {}
	var state_text := MatterUtils.canonical_json(raw)
	if state_text.is_empty():
		return {}
	var envelope := {
		"schema": STATE_ENVELOPE_SCHEMA,
		"state_text": state_text,
		"state_hash": state_text.sha256_text(),
	}
	return envelope if not C.encode(envelope).is_empty() else {}

## Import only an externally anchored state envelope. configure() must already
## have bound this adapter to the same manifest. The ecology checkpoint anchors
## this envelope; the envelope in turn anchors canonical physical JSON bytes.
func import_state(value: Dictionary, expected_hash: String) -> Dictionary:
	if not FieldContract.valid_hash(expected_hash) or C.digest(value) != expected_hash:
		return _fail("ADAPTER_STATE_EXTERNAL_ANCHOR")
	if not C.keys(value, ["schema", "state_text", "state_hash"]) or String(value.schema) != STATE_ENVELOPE_SCHEMA:
		return _fail("ADAPTER_STATE_ENVELOPE")
	if not value.state_text is String or not FieldContract.valid_hash(value.state_hash) \
			or String(value.state_text).sha256_text() != String(value.state_hash):
		return _fail("ADAPTER_STATE_TEXT_ANCHOR")
	var decoded: Variant = JSON.parse_string(String(value.state_text))
	if not decoded is Dictionary:
		return _fail("ADAPTER_STATE_TEXT_DECODE")
	# JSON numbers have no integer type; normalize through the production
	# network canonicalizer so cursor/revision fields regain exact int types
	# while genuine fractional physical values stay float.
	var normalized: Dictionary = NetworkUtils.canonicalize(decoded, "$.eco_world_state")
	if not bool(normalized.get("success", false)) or not normalized.get("value") is Dictionary:
		return _fail("ADAPTER_STATE_TEXT_NORMALIZE")
	var raw: Dictionary = normalized.value
	if MatterUtils.canonical_json(raw) != String(value.state_text):
		return _fail("ADAPTER_STATE_TEXT_NONCANONICAL")
	var error := _validate_raw_state(raw)
	if not error.is_empty():
		return _fail(error)
	if not _manifest_hash.is_empty() and String(raw.manifest_hash) != _manifest_hash:
		return _fail("ADAPTER_STATE_MANIFEST")
	_region = raw.region.duplicate(true)
	_cursor = raw.cursor.duplicate(true)
	_catalog = raw.catalog.duplicate(true)
	_mapping = raw.mapping.duplicate(true)
	_map_id = String(raw.map_id)
	_site_binding = raw.site_binding.duplicate(true)
	_batches = raw.batches.duplicate(true)
	_admitted_resources = raw.admitted_resources.duplicate(true)
	_damage = raw.damage.duplicate(true)
	last_error = ""
	return {"success": true}

func _validate_raw_state(value: Variant) -> String:
	var fields := ["schema", "manifest_hash", "region", "cursor", "catalog", "mapping", "map_id", "site_binding", "batches", "admitted_resources", "damage", "checksum"]
	if not C.keys(value, fields) or String(value.schema) != STATE_SCHEMA:
		return "ADAPTER_STATE_SCHEMA"
	if not FieldContract.valid_hash(value.manifest_hash) or not value.region is Dictionary or not value.cursor is Dictionary:
		return "ADAPTER_STATE_FIELDS"
	if not bool(Region.validate(value.region).get("success", false)):
		return "ADAPTER_STATE_REGION"
	if String(value.cursor.get("region_id", "")) != String(value.region.get("region_id", "")):
		return "ADAPTER_STATE_CURSOR_REGION"
	if String(value.cursor.get("owner_id", "")) != String(value.region.get("owner_node_id", "")):
		return "ADAPTER_STATE_CURSOR_OWNER"
	if int(value.cursor.get("owner_epoch", -1)) != int(value.region.get("authority_epoch", -2)):
		return "ADAPTER_STATE_CURSOR_EPOCH"
	if not value.catalog is Dictionary or not value.mapping is Dictionary or not Mapping.validate(value.mapping, value.catalog).is_empty():
		return "ADAPTER_STATE_MAPPING"
	if not value.map_id is String or String(value.map_id) != String(value.mapping.map_id):
		return "ADAPTER_STATE_MAP_ID"
	if not value.site_binding is Dictionary or not value.batches is Dictionary or not value.damage is Dictionary:
		return "ADAPTER_STATE_CONTAINER"
	if not MatterUtils.validate_json_safe(value.catalog).success \
			or not MatterUtils.validate_json_safe(value.site_binding).success \
			or not MatterUtils.validate_json_safe(value.damage).success:
		return "ADAPTER_STATE_JSON_SAFE"
	if not FieldContract.valid_total_stock(value.admitted_resources):
		return "ADAPTER_STATE_RESOURCES"
	for batch_id in value.batches:
		var row: Variant = value.batches[batch_id]
		if not row is Dictionary or not C.keys(row, ["checksum", "applied", "admission"]):
			return "ADAPTER_STATE_BATCH"
		if not FieldContract.valid_hash(row.checksum) or not row.applied is bool or not row.admission is Dictionary:
			return "ADAPTER_STATE_BATCH"
		if String(row.admission.get("batch_id", "")) != String(batch_id) or String(row.admission.get("batch_checksum", "")) != String(row.checksum):
			return "ADAPTER_STATE_BATCH_BINDING"
		if String(row.admission.get("map_checksum", "")) != String(value.mapping.checksum) or not FieldContract.valid_total_stock(row.admission.get("resources", {})):
			return "ADAPTER_STATE_BATCH_ADMISSION"
	for individual_id in value.damage:
		var row: Variant = value.damage[individual_id]
		if not row is Dictionary or not row.has_all(["modules", "snapshot", "binding", "overlay", "event", "trusted_event_binding_hash"]):
			return "ADAPTER_STATE_DAMAGE"
		if not row.modules is Array or not row.snapshot is Dictionary or not row.binding is Dictionary or not row.overlay is Dictionary or not row.event is Dictionary:
			return "ADAPTER_STATE_DAMAGE"
		if not Body.validate(row.modules).is_empty():
			return "ADAPTER_STATE_DAMAGE_BODY"
		if not BodyBinding.validate_binding(row.binding, row.modules, row.snapshot).is_empty():
			return "ADAPTER_STATE_DAMAGE_BINDING"
		if not BodyBinding.validate_overlay(row.overlay, row.binding, row.modules, row.snapshot).is_empty():
			return "ADAPTER_STATE_DAMAGE_OVERLAY"
		if not FieldContract.valid_hash(row.trusted_event_binding_hash) or String(row.event.get("binding_hash", "")) != String(row.trusted_event_binding_hash):
			return "ADAPTER_STATE_DAMAGE_EVENT_ANCHOR"
	if not FieldContract.valid_hash(value.checksum) or String(value.checksum) != _state_checksum(value):
		return "ADAPTER_STATE_CHECKSUM"
	return ""

func _state_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.checksum = ""
	return MatterUtils.payload_hash(payload)

# --- read views -------------------------------------------------------------------

func cursor() -> Dictionary:
	return _cursor.duplicate(true)

func region() -> Dictionary:
	return _region.duplicate(true)

func mapping() -> Dictionary:
	return _mapping.duplicate(true)

## World-facing read view (region state, cursor, matter anchors, damage).
func observe_world() -> Dictionary:
	if _region.is_empty():
		return {"configured": false, "error": last_error}
	var damage_summary := {}
	for individual_id in _damage.keys():
		var row: Dictionary = _damage[individual_id]
		damage_summary[individual_id] = {
			"overlay_revision": int(row.overlay.revision),
			"overlay_checksum": String(row.overlay.checksum),
		}
	return {
		"configured": true,
		"region_id": String(_region.region_id),
		"owner_node_id": String(_region.owner_node_id),
		"authority_epoch": int(_region.authority_epoch),
		"lifecycle_state": String(_region.lifecycle_state),
		"cursor": cursor(),
		"matter_mapping": {
			"map_id": String(_mapping.map_id),
			"map_checksum": String(_mapping.checksum),
			"entries": Array(_mapping.entries).duplicate(true),
		},
		"site_binding_hash": "" if _site_binding.is_empty() else String(_site_binding.binding_hash),
		"admitted_resources": _admitted_resources.duplicate(true),
		"damage": damage_summary,
	}

# --- helpers ------------------------------------------------------------------------

func _population_entry(debug: Dictionary, individual_id: String) -> Dictionary:
	if not debug is Dictionary or not debug.has("population"):
		return {}
	for entry in debug.population:
		if String(entry.state.individual_id) == String(individual_id):
			return entry
	return {}

func _fail(error: String) -> Dictionary:
	last_error = error
	return {"success": false, "error": error}
