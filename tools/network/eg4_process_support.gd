extends "res://tools/network/eg3_process_support.gd"

const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")

## Shared EG4 process-worker support: the projection-aggregation scenario.
##
## Topology under proof: ONE game-client process connected ONLY to the gateway;
## the gateway holds TWO upstream legs — Sim A (ACTIVE authority, normal
## EG1..EG3 data plane) and Sim B (PROJECTION source streaming synthetic
## read-only WORLD_PROJECTION frames for SUBSCRIBED worlds). Identity
## namespaces stay strictly separated.
##
## Demand wire convention (additive EG2 placement-handler dispatch): a client
## SESSION_CONTROL frame with payload_schema planet_simulator.eg4_projection_
## demand.v1 carries {demand_kind, worlds[]} and lands in the gateway worker's
## EG4 handler (EG1 session control reports UNSUPPORTED_SESSION_CONTROL_SCHEMA,
## the wrapper intercepts BEFORE delegating auth/placement schemas).
##
## World <-> entity-slug convention for subscribe targets: L2 world ids avoid
## dashes beyond their separators (world/eg4/l2p0007) so the slug round-trips:
## slug = world_id.replace("/", "-"); world_id re-derived by replacing the
## first two dashes.

const HOME_WORLD_ID_EG4 := "world/eg4/fixture-0000"
const AUTHORITY_ID_EG4_A := "authority/eg4-a"
const AUTHORITY_ID_EG4_B := "authority/eg4-b"
const SERVER_INSTANCE_EG4_A := "server-instance/eg4-a"
const SERVER_INSTANCE_EG4_B := "server-instance/eg4-b"

const DEMAND_PAYLOAD_SCHEMA := "planet_simulator.eg4_projection_demand.v1"
const DEMAND_ACK_PAYLOAD_SCHEMA := "planet_simulator.eg4_projection_ack.v1"
const DEMAND_KIND_SUBSCRIBE := "projection_subscribe"
const DEMAND_KIND_WITHDRAW := "projection_withdraw"

## Synthetic projection cadence: one frame per subscribed (session, world)
## pair per beat; generous deadlines everywhere. Wire frames stay SMALL
## (< ~900 bytes encoded): an unreliable frame above the ENet fragmentation
## threshold arrives with the UNRELIABLE_FRAGMENT transfer mode, which the
## strict physical frame-binding fence rejects as a protocol violation.
const PROJECTION_BEAT_MS := 120
## The PROJECTION source attempts a SOLO mutation-shaped frame every this many
## frames per subscribed pair (0-based: each pair's first frame is an attempt);
## repetition makes at-least-one-arrival deterministic for the end-to-end
## write-injection rejection proof.
const INJECTION_AFTER_FRAMES := 3

## Gateway watchdog: a subscribed source silent this long is LOST (a killed
## UDP process stays protocol-silent, so liveness is traffic-based).
const SOURCE_LOSS_TIMEOUT_MS := 2500


static func l2_world_id(index: int) -> String:
	# Fixture-convention world ids: exactly two separator dashes so the entity
	# slug round-trips (world/eg4/fixture-0007).
	return "world/eg4/fixture-%04d" % maxi(index, 0)


static func world_entity_slug(world_id: String) -> String:
	return "entity/%s" % world_id.replace("/", "-")


static func world_from_entity_slug(slug: String) -> String:
	var text := String(slug)
	if text.begins_with("entity/world-"):
		var rest := text.trim_prefix("entity/world-")
		var first := rest.find("-")
		if first > 0:
			return "world/%s/%s" % [rest.substr(0, first), rest.substr(first + 1)]
	return ""


## ---- EG4 demand inner frames ---------------------------------------------------


static func place_request_inner_eg4(client_session_id: String, ticket_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg4/l2/place/1",
			"gateway-session/eg4/probe/l2",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA,
			{
				"client_session_id": client_session_id,
				"ticket_id": ticket_id,
				"resume_token": "",
				"world_id": HOME_WORLD_ID_EG4,
			})


static func projection_demand_inner(gateway_session_id: String, demand_kind: String, worlds: Array) -> Dictionary:
	var payload := {
		"demand_kind": demand_kind,
		"worlds": worlds,
	}
	return ClientWorldFrameScript.create(
			"frame/eg4/l2/demand/%s/%d" % [demand_kind.replace("_", "-"), Time.get_ticks_msec()],
			gateway_session_id,
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			DEMAND_PAYLOAD_SCHEMA,
			payload)


## ---- PROJECTION-source egress ---------------------------------------------------


static func projection_egress_envelope(
		envelope_counter: int,
		gateway_session_id: String,
		world_id: String,
		source_revision: int,
		read_only: bool,
) -> Dictionary:
	# ONE compact entity keeps the encoded wire frame below the unreliable
	# fragmentation threshold (see the cadence note above).
	var payload := {
		"read_only": read_only,
		"source_revision": source_revision,
		"entities": ["entity/eg4p%04d" % (source_revision % 10000)],
	}
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/p/%06d" % envelope_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT", "WORLD_PROJECTION", maxi(source_revision, 1),
			"planet_simulator.test_world_projection.v1",
			payload)
	return EgressEnvelopeScript.create(
			"gateway-envelope/eg4/p/%06d" % envelope_counter,
			"gateway/eg4-w",
			"backend-link/eg4-b",
			gateway_session_id,
			1, 1, 1,
			AUTHORITY_ID_EG4_B,
			SERVER_INSTANCE_EG4_B,
			"PROJECTION",
			inner)


## Mutation-shaped INJECTION frame: a PROJECTION-role envelope whose inner
## channel is a MUTATING channel. The gateway read-only fence must reject it.
static func mutation_injection_envelope(envelope_counter: int, gateway_session_id: String) -> Dictionary:
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/i/%06d" % envelope_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT", "WORLD_OPERATION", maxi(envelope_counter, 1),
			"planet_simulator.test_world_operation.v1",
			{
				"operation_id": "operation/eg4/inj-%06d" % envelope_counter,
				"command": "inventory.assign_hotbar",
				"target_id": "entity/eg4-injected",
			})
	return EgressEnvelopeScript.create(
			"gateway-envelope/eg4/i/%06d" % envelope_counter,
			"gateway/eg4-w",
			"backend-link/eg4-b",
			gateway_session_id,
			1, 1, 1,
			AUTHORITY_ID_EG4_B,
			SERVER_INSTANCE_EG4_B,
			"PROJECTION",
			inner)


static func send_envelope(boundary, peer_id: String, wire_session: String, sequence: int, semantic_channel: String, envelope: Dictionary, frame_tag: String) -> Dictionary:
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/b/%s/%06d" % [frame_tag, sequence],
			wire_session, sequence,
			GatewayUtils.eg1_physical_channel_for(semantic_channel),
			GatewayUtils.eg1_delivery_mode_for(semantic_channel),
			"planet_simulator.gateway_egress_envelope.v1",
			envelope)
	return boundary.send_to_peer(peer_id, wire)


## ---- expected totals ------------------------------------------------------------


static func demand_projection_worlds(count: int) -> Array[String]:
	var worlds: Array[String] = []
	for index in range(1, maxi(count, 0) + 1):
		worlds.append(l2_world_id(index))
	return worlds
