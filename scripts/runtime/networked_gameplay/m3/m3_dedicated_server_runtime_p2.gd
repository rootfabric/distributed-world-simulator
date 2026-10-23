extends Node

const SmoothTrace = preload("res://scripts/network/smoothness/net_smooth_trace.gd")

signal ready_for_clients(report: Dictionary)

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const User1ProductSeamService = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
)
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const RecoveryRepository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const RecoveryCoordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const AsyncCheckpointWriter = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const M6AuthorityAdapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const R31Bp1DurableChunkCache = preload("res://scripts/runtime/networked_gameplay/m6/r31bp1_durable_chunk_cache.gd")
const M6ReplayOutbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const M6PendingDurableAckGate = preload("res://scripts/persistence/m6_pending_durable_ack_gate.gd")
const M6AsyncDurableCommandProof = preload("res://scripts/persistence/m6_async_durable_command_proof.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const CompatibilityHandshake = preload("res://scripts/network/observability/network_compatibility_handshake.gd")
const TelemetryCollector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const ConditionSimulatorPort = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const ConditionProfileStore = preload("res://scripts/network/conditions/network_condition_profile_store.gd")
const RealtimeChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")
const PlayerInputBatch = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_batch.gd")
const CanonicalItemGraphDelta = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")
const CompactGameplaySnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const FullSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const CommittedView = preload("res://scripts/runtime/networked_gameplay/contracts/committed_movement_view.gd")
const FixedTickScheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const FixedTickInputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")
const ConstructionBridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const Live2ServerStallWatchdog = preload(
	"res://scripts/runtime/networked_gameplay/m3/live2_server_stall_watchdog.gd"
)

const SCHEMA := "planet_simulator.m3_dedicated_server_runtime.v1"
const M6_CHECKPOINT := "v16.10.5-persistence-m6-dedicated-recovery"
const M6_BUILD_ID := "m6-dedicated-persistence-recovery"
const M7_CHECKPOINT := "v16.10.6.1-testing-m7-playable-networked-playground"
const M7_BUILD_ID := "m7-playable-networked-playground"
const M7_MOVEMENT_CHECKPOINT_INTERVAL_MS := 1500
const NX2_MOVEMENT_SNAPSHOT_INTERVAL_MS := 50
const NX3_FIXED_TICK_RATE_HZ := 60
const NX3_FIXED_TICK_DELTA_SECONDS := 1.0 / 60.0
const NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS := 3

var _boundary
var _service
var _configured := false
var _host := "127.0.0.1"
var _port := 0
var _result_file := ""
var _authority_owner_id := "simulation/m3/dedicated"
var _authority_epoch := 1
var _peer_to_player: Dictionary = {}
var _peer_to_session: Dictionary = {}
var _joins := 0
var _fast_join_acks := 0
var _leaves := 0
var _moves := 0
var _presentation_updates := 0
var _rejections := 0
var _broadcasts := 0
var _messages_sent := 0
var _messages_received := 0
var _last_error_code := ""
var _last_two_connected_checksum := ""
var _persistence_root := ""
var _persistence_enabled := false
var _recovery_repository
var _recovery_coordinator
var _recovery_authority
var _replay_outbox
# R4.1-P1: ordered durable-ACK escrow. No mutation entry, success result, or
# broadcast is published for an uncommitted checkpoint generation.
var _durable_ack_gate
# P1-B R2 opt-in ITEM canary (off in normal production).
var _p1b_item_async_enabled := false
var _p1b_item_async_owner
var _p1b_item_pending: Dictionary = {}
# Full wire snapshot captured before ITEM, never aliased to canonical state.
var _p1b_committed_view: Dictionary = {}
var _p1b_committed_frames := 0
var _p1b_committed_enqueues := 0
var _p1b_committed_rejections := 0
const P1B_MAX_DEFERRED_ITEM_RESYNCS := 32
var _p1b_item_resync_waiters: Dictionary = {}
var _p1b_item_commits := 0
# R3B: only the DISCONNECT legacy command uses this new asynchronous
# single-writer path; other legacy command contracts are not broadened.
var _r3b_async_disconnect_commits := 0
# R3C is strictly opt-in pending independent Windows verification.
var _r3c_async_admission_enabled := false
# R3C.2: opt-in phased, ordered post-durable ITEM publication. The existing
# M6 ACK escrow remains the only success publication authority.
var _r3c2_phased_item_publication_enabled := false
var _r3c2_postcommit_pending: Dictionary = {}
var _r3c2_postcommit_phases_completed := 0
var _r3c2_postcommit_last_stage_ms := 0.0
var _r3c2_deferred_diagnostic_reports := 0
# R3C.4: opt-in frame separation of the periodic checkpoint from the same-frame
# 20Hz movement snapshot burst. Frame pacing only; the single-writer M6
# pipeline, generation semantics and durable-before-ACK barrier are unchanged.
var _r3c4_periodic_frame_pacing_enabled := false
# R3C.4 R2: a separate opt-in routes ONLY periodic envelope/checksum
# construction to the existing worker, not the mutable gameplay export.
var _r3c4r2_worker_envelope_enabled := false
# R3C.4 R3.0: opt-in stage attribution only, never changes durable state or
# ACK sequencing. A product optimization requires a different feature gate.
var _r3c4r30_stage_attribution_enabled := false
# Replay-only immutable derived cache, NOT an authority gameplay snapshot.
# R3.1a opt-in does not change command paths, ACK gate or disk format.
var _r3c4r31_replay_projection_enabled := false
# R3C.4 R3.1b P0: per-domain durable export attribution only (opt-in).
var _r3c4r31b_durable_attribution_enabled := false
# R31b P1: opt-in source-fenced immutable durable chunk cache for the M4 Item
# Graph and ResourceMining durable components. Server-only, default OFF.
var _r31bp1_durable_chunks_enabled := false
var _r31bp1_chunk_cache = null
# R31b P2.0: profiler only. Does not skip any native validator.
var _r31bp20_validator_attribution_enabled := false
# R31P2.2: server-only diagnostic. Never changes work order, M6 or tick rate.
var _r31p22_loop_attribution_enabled := false
var _r3c4_deferral_started_ms := 0
var _r3c4_deferred_frames := 0
var _r3c4_capture_slots := 0
var _r3c4_forced_captures := 0
var _r3c4_precapture_work_ms := 0.0
# Bounded starvation guard: a due capture is forced no later than the next
# eligible process frame after 64ms, even if the frame is still heavy.
const R3C4_MAX_DEFERRAL_MS := 64
var _r3c_async_leave_commits := 0
const R3C_MAX_DEFERRED_ADMISSIONS := 32
const R3C_ADMISSION_TIMEOUT_MS := 20000
var _r3c_deferred_admissions: Array[Dictionary] = []
var _r3c_queued_joins := 0
var _r3c_queued_leaves := 0
var _r3c_admissions_drained := 0
var _r3c_admissions_dropped := 0
# Count ONLY unsafe full/ITEM snapshots blocked during a pending mutation.
# Movement committed-view frames are permitted and are never counted as holds.
var _p1b_item_precommit_snapshot_holds := 0
var _p1b_item_graph_snapshot_holds := 0
var _p1b_item_last_capture_ms := 0.0
var _p1b_item_last_worker_ms := 0.0
var _p1b_item_last_build_ms := 0.0
var _p1b_item_last_write_ms := 0.0
var _p1b_item_capture_stages: Dictionary = {}
var _p1b_item_last_ack_wait_ms := 0.0
var _player_ownership_epochs: Dictionary = {}
# Bound disconnected sessions while a durable generation is pending.
const MAX_DEFERRED_DISCONNECTS := 64
var _deferred_disconnects: Array[Dictionary] = []
var _checkpoint_generation := 0
var _recovered := false
var _recovery_source := ""
var _last_checkpoint_operation_id := ""
var _persistence_failures := 0
var _legacy_sync_commit_count := 0
var _legacy_last_main_thread_ms := 0.0
var _legacy_last_writer_wait_ms := 0.0
var _last_persistence_error_details: Dictionary = {}
var _durable_commits := 0
var _fatal_persistence_failure := false
var _playable_sandbox := false
var _movement_checkpoint_writer
var _async_checkpoint_capture_ms := 0.0
var _async_checkpoint_started_us := 0
var _async_checkpoint_last: Dictionary = {}
var _movement_checkpoint_dirty := false
var _last_movement_checkpoint_ms := 0
var _movement_checkpoints := 0
var _movement_commands_since_checkpoint := 0
var _debug_logging := false
var _last_debug_report_ms := 0
var _fixed_tick_scheduler
var _peer_input_buffers: Dictionary = {}
var _server_tick := 0
var _fixed_ticks_simulated := 0
var _fixed_tick_catch_up_batches := 0
var _fixed_tick_failures := 0
var _input_queue_stale_drops := 0
var _input_hold_expirations := 0
var _last_fixed_tick_duration_ms := 0.0
var _last_movement_snapshot_tick := 0
var _fingerprint: Dictionary = {}
var _protocol_manifest: Dictionary = {}
var _telemetry
var _network_condition_simulator
var _network_condition_profile: Dictionary = {}
var _network_condition_presets_file: String = ConditionProfileStore.DEFAULT_PRESETS_PATH
var _peer_compatibility: Dictionary = {}
var _handshake_attempts := 0
var _handshake_accepts := 0
var _handshake_rejections := 0
var _handshake_replays := 0
var _last_handshake_error_code := ""
var _movement_snapshot_dirty := false
# Last confirmed reliable PRODUCT_SEAM_STATE per transport session. Movement
# snapshots already carry the rapidly changing player state; the seam contract
# contains only authority/region transition state, not movement position.
var _seam_sent_state_by_peer: Dictionary = {}
var _seam_messages_sent := 0
var _seam_unchanged_skipped := 0
var _movement_batches_received := 0
var _movement_inputs_received := 0
var _movement_inputs_applied := 0
var _movement_inputs_redundant := 0
var _movement_inputs_rejected := 0
var _last_movement_rejection_error_code := ""
var _last_movement_rejection_stage := ""
var _movement_results_suppressed := 0
var _movement_deltas_suppressed := 0
var _movement_full_snapshots_suppressed := 0
var _movement_snapshots_published := 0
var _item_graph_deltas_published := 0
var _item_graph_delta_build_failures := 0
var _item_graph_full_snapshots_published := 0
var _item_graph_resync_requests := 0
var _compact_movement_snapshots_published := 0
var _movement_snapshot_retransmit_requests := 0
var _movement_snapshot_enqueue_failures := 0
var _compact_movement_snapshot_failures := 0
var _construction_bridge
var _construction_events_published := 0
var _construction_snapshots_published := 0
var _live2_stall_watchdog

func set_construction_bridge(bridge) -> Dictionary:
	if _configured:
		return _failure("M3_CONSTRUCTION_BRIDGE_MUST_BE_SET_BEFORE_SETUP")
	if bridge == null or not bridge.has_method("connect_player") or not bridge.has_method("submit_player_command"):
		return _failure("M3_CONSTRUCTION_BRIDGE_INVALID")
	_construction_bridge = bridge
	return _success()

func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("M3_SERVER_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_authority_owner_id = String(config.get("authority_owner_id", _authority_owner_id)).strip_edges()
	_authority_epoch = int(config.get("authority_epoch", 1))
	_persistence_root = String(config.get("persistence_root", "")).strip_edges()
	_persistence_enabled = not _persistence_root.is_empty()
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	_r3c_async_admission_enabled = (
		bool(config.get("r3c_async_admission_canary", false))
		or OS.get_environment("DWS_NET_R3C_ASYNC_ADMISSION") == "1"
	)
	_r3c2_phased_item_publication_enabled = (
		bool(config.get("r3c2_phased_publication_canary", false))
		or OS.get_environment("DWS_NET_R3C2_PHASED_ITEM_PUBLICATION") == "1"
	)
	var r3c4_mode := OS.get_environment("DWS_NET_R3C4_PERIODIC_FRAME_PACING")
	if not r3c4_mode.is_empty() and r3c4_mode != "0" and r3c4_mode != "1":
		return _failure("R3C4_INVALID_PACING_MODE")
	_r3c4_periodic_frame_pacing_enabled = (
		bool(config.get("r3c4_periodic_frame_pacing_canary", false))
		or r3c4_mode == "1"
	)
	var r3c4r2_mode := OS.get_environment("DWS_NET_R3C4_R2_WORKER_ENVELOPE")
	if not r3c4r2_mode.is_empty() and r3c4r2_mode != "0" and r3c4r2_mode != "1":
		return _failure("R3C4_R2_INVALID_MODE")
	_r3c4r2_worker_envelope_enabled = (
		bool(config.get("r3c4r2_worker_envelope_canary", false))
		or r3c4r2_mode == "1"
	)
	if _r3c4r2_worker_envelope_enabled and (
		not _r3c4_periodic_frame_pacing_enabled
		or not _persistence_enabled
		or not _playable_sandbox
	):
		return _failure("R3C4_R2_REQUIRES_PERIODIC_PERSISTENT_MODE")
	var r3c4r30_mode := OS.get_environment("DWS_NET_R3C4_R30_STAGE_ATTRIBUTION")
	if not r3c4r30_mode.is_empty() and r3c4r30_mode not in ["0", "1"]:
		return _failure("R3C4_R30_INVALID_MODE")
	_r3c4r30_stage_attribution_enabled = (
		bool(config.get("r3c4r30_stage_attribution_canary", false))
		or r3c4r30_mode == "1"
	)
	if _r3c4r30_stage_attribution_enabled and not _r3c4r2_worker_envelope_enabled:
		return _failure("R3C4_R30_REQUIRES_R2_WORKER_ENVELOPE")
	var r3c4r31_mode := OS.get_environment("DWS_NET_R3C4_R31_REPLAY_PROJECTION")
	if not r3c4r31_mode.is_empty() and r3c4r31_mode not in ["0", "1"]:
		return _failure("R3C4_R31_INVALID_MODE")
	_r3c4r31_replay_projection_enabled = (
		bool(config.get("r3c4r31_replay_projection_canary", false))
		or r3c4r31_mode == "1"
	)
	if _r3c4r31_replay_projection_enabled and not _r3c4r2_worker_envelope_enabled:
		return _failure("R3C4_R31_REQUIRES_R2_WORKER_ENVELOPE")
	# R3.0 timings apply to uncached replay path only. Keep independent
	# opt-in modes mutually exclusive to prevent false source attribution.
	if _r3c4r31_replay_projection_enabled and _r3c4r30_stage_attribution_enabled:
		return _failure("R3C4_R31_R30_ATTRIBUTION_MODE_CONFLICT")
	var r31b_mode := OS.get_environment("DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION")
	if not r31b_mode.is_empty() and r31b_mode not in ["0", "1"]:
		return _failure("R3C4_R31B_INVALID_MODE")
	_r3c4r31b_durable_attribution_enabled = (
		bool(config.get("r3c4r31b_durable_attribution_canary", false))
		or r31b_mode == "1"
	)
	if _r3c4r31b_durable_attribution_enabled and not _r3c4r31_replay_projection_enabled:
		return _failure("R3C4_R31B_REQUIRES_R31_REPLAY_PROJECTION")
	if _r3c4r31b_durable_attribution_enabled and not bool(config.get("product_seam_enabled", false)):
		return _failure("R3C4_R31B_REQUIRES_PRODUCT_SEAM")
	# R31b P1: the chunk cache is an implementation candidate layered on the
	# FULL P0 stack. Any missing prerequisite fails CLOSED.
	var r31bp1_mode := OS.get_environment("DWS_NET_R31BP1_DURABLE_CHUNKS")
	if not r31bp1_mode.is_empty() and r31bp1_mode not in ["0", "1"]:
		return _failure("R31BP1_INVALID_MODE")
	_r31bp1_durable_chunks_enabled = (
		bool(config.get("r31bp1_durable_chunks_canary", false))
		or r31bp1_mode == "1"
	)
	if _r31bp1_durable_chunks_enabled and (
		not _r3c4r31b_durable_attribution_enabled
		or not _r3c4r31_replay_projection_enabled
		or not _r3c4r2_worker_envelope_enabled
		or not _persistence_enabled
		or not bool(config.get("product_seam_enabled", false))
	):
		return _failure("R31BP1_REQUIRES_P0_ATTRIBUTION_REPLAY_R2_PERSISTENCE")
	var p20_mode := OS.get_environment("DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION")
	if not p20_mode.is_empty() and p20_mode not in ["0", "1"]:
		return _failure("R31BP20_INVALID_MODE")
	_r31bp20_validator_attribution_enabled = (
		bool(config.get("r31bp20_validator_attribution_canary", false))
		or p20_mode == "1"
	)
	if _r31bp20_validator_attribution_enabled and (
		not _r31bp1_durable_chunks_enabled
		or not _r3c4r31b_durable_attribution_enabled
		or not _r3c4r31_replay_projection_enabled
		or not _r3c4r2_worker_envelope_enabled
		or not _persistence_enabled
		or not bool(config.get("product_seam_enabled", false))
	):
		return _failure("R31BP20_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM")
	var p22_mode := OS.get_environment("DWS_NET_R31P22_LOOP_ATTRIBUTION")
	if not p22_mode.is_empty() and p22_mode not in ["0", "1"]:
		return _failure("R31P22_INVALID_MODE")
	_r31p22_loop_attribution_enabled = (
		bool(config.get("r31p22_loop_attribution_canary", false))
		or p22_mode == "1"
	)
	if _r31p22_loop_attribution_enabled and (
		not _r31bp1_durable_chunks_enabled
		or not _r3c4r31b_durable_attribution_enabled
		or not _r3c4r31_replay_projection_enabled
		or not _r3c4r2_worker_envelope_enabled
		or not _persistence_enabled
		or not bool(config.get("product_seam_enabled", false))
	):
		return _failure("R31P22_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM")
	_p1b_item_async_enabled = (
		bool(config.get("async_durable_item_canary", false))
		or OS.get_environment("DWS_NET_P1B_ITEM_ASYNC") == "1"
		or _r3c_async_admission_enabled
		or _r3c2_phased_item_publication_enabled
	)
	if _p1b_item_async_enabled and (not _persistence_enabled or not _playable_sandbox):
		return _failure("P1B_CANARY_REQUIRES_PERSISTENT_PLAYABLE_WORLD")
	_p1b_item_pending.clear()
	_p1b_committed_view.clear()
	_p1b_committed_frames = 0
	_p1b_committed_enqueues = 0
	_p1b_committed_rejections = 0
	_p1b_item_resync_waiters.clear()
	_p1b_item_commits = 0
	_r3b_async_disconnect_commits = 0
	_r3c_async_leave_commits = 0
	_r3c_deferred_admissions.clear()
	_r3c2_postcommit_pending.clear()
	_r3c2_postcommit_phases_completed = 0
	_r3c2_postcommit_last_stage_ms = 0.0
	_r3c2_deferred_diagnostic_reports = 0
	_r3c4_deferral_started_ms = 0
	_r3c4_deferred_frames = 0
	_r3c4_capture_slots = 0
	_r3c4_forced_captures = 0
	_r3c4_precapture_work_ms = 0.0
	_r3c_queued_joins = 0
	_r3c_queued_leaves = 0
	_r3c_admissions_drained = 0
	_r3c_admissions_dropped = 0
	_p1b_item_precommit_snapshot_holds = 0
	_p1b_item_graph_snapshot_holds = 0
	_debug_logging = bool(config.get("debug_logging", false))
	if _host.is_empty() or _port < 1 or _port > 65535 or _authority_owner_id.is_empty() or _authority_epoch < 1:
		return _failure("INVALID_M3_SERVER_CONFIGURATION")
	var identity_result: Dictionary = RuntimeIdentity.validate_config(config)
	if not bool(identity_result.get("success", false)):
		return identity_result
	_fingerprint = Dictionary(identity_result.get("details", {}).get("fingerprint", {})).duplicate(true)
	_protocol_manifest = Dictionary(identity_result.get("details", {}).get("protocol_manifest", {})).duplicate(true)
	_telemetry = TelemetryCollector.new()
	var telemetry_setup: Dictionary = _telemetry.configure(
		"server", _fingerprint, int(config.get("telemetry_sample_limit", 512))
	)
	if not bool(telemetry_setup.get("success", false)):
		return telemetry_setup
	_peer_compatibility.clear()
	_deferred_disconnects.clear()
	_seam_sent_state_by_peer.clear()
	_seam_messages_sent = 0
	_seam_unchanged_skipped = 0
	_handshake_attempts = 0
	_handshake_accepts = 0
	_handshake_rejections = 0
	_handshake_replays = 0
	_last_handshake_error_code = ""
	_service = (
		User1ProductSeamService.new()
		if bool(config.get("product_seam_enabled", false))
		else Service.new()
	)
	var service_setup: Dictionary = _service.setup(_authority_owner_id, _authority_epoch, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
		"playable_sandbox": _playable_sandbox,
		"fixed_tick_authority": true,
		"product_seam_enabled": bool(config.get("product_seam_enabled", false)),
	})
	if not bool(service_setup.get("success", false)):
		return service_setup
	if _r31bp1_durable_chunks_enabled:
		# Fail CLOSED: a misconfigured cache must abort server startup rather
		# than silently degrade to the legacy path with the flag advertised ON.
		var chunk_cache_setup: Dictionary = _setup_r31bp1_durable_chunk_cache()
		if not bool(chunk_cache_setup.get("success", false)):
			_service.shutdown()
			_service = null
			return chunk_cache_setup
	if _r31bp20_validator_attribution_enabled:
		if _service == null or not _service.has_method("configure_r31bp20_validation_attribution"):
			return _failure("R31BP20_PRODUCT_VALIDATOR_REQUIRED")
		var p20_setup: Dictionary = _service.configure_r31bp20_validation_attribution(true)
		if not bool(p20_setup.get("success", false)):
			return p20_setup
	if _persistence_enabled:
		var recovery_setup := _setup_recovery()
		if not bool(recovery_setup.get("success", false)):
			_service.shutdown()
			_service = null
			return recovery_setup
	if (_persistence_enabled and _playable_sandbox
		and bool(config.get("async_movement_checkpoints", true))
		and not (SmoothTrace.enabled() and OS.get_environment("DWS_NET_SMOOTH_SYNC_CHECKPOINTS") == "1")):

		_movement_checkpoint_writer = AsyncCheckpointWriter.new()
		var writer_setup: Dictionary = _movement_checkpoint_writer.setup(_persistence_root)
		if not bool(writer_setup.get("success", false)):
			_cleanup_setup_failure()
			return writer_setup
	if _p1b_item_async_enabled:
		if _movement_checkpoint_writer == null or _durable_ack_gate == null:
			_cleanup_setup_failure()
			return _failure("P1B_ITEM_SINGLE_WRITER_REQUIRED")
		_p1b_item_async_owner = M6AsyncDurableCommandProof.new()
		var p1b_owner_setup: Dictionary = _p1b_item_async_owner.configure(
			_movement_checkpoint_writer, _durable_ack_gate
		)
		if not bool(p1b_owner_setup.get("success", false)):
			_cleanup_setup_failure()
			return _failure("P1B_ITEM_ASYNC_SETUP_FAILED", {"cause": p1b_owner_setup})
	_fixed_tick_scheduler = FixedTickScheduler.new()
	_server_tick = int(_service.get_report().get("server_tick", 0))
	var fixed_tick_setup: Dictionary = _fixed_tick_scheduler.configure(
		NX3_FIXED_TICK_RATE_HZ, FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS, _server_tick
	)
	if not bool(fixed_tick_setup.get("success", false)):
		_cleanup_setup_failure()
		return fixed_tick_setup
	_peer_input_buffers.clear()
	_last_movement_snapshot_tick = _server_tick
	var condition_setup: Dictionary = _setup_network_condition_simulator(config)
	if not bool(condition_setup.get("success", false)):
		_cleanup_setup_failure()
		return condition_setup
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(
		_network_condition_simulator, 524288, 64, 2097152, _telemetry
	)
	if not bool(configured.get("success", false)):
		_cleanup_setup_failure()
		return configured
	var started: Dictionary = _boundary.start_server(Support.endpoint(_host, _port, true))
	if not bool(started.get("success", false)):
		_cleanup_setup_failure()
		return started
	_configured = true
	if _debug_logging:
		_live2_stall_watchdog = Live2ServerStallWatchdog.new()
		var watchdog_start: Dictionary = _live2_stall_watchdog.start(OS.get_process_id())
		if not bool(watchdog_start.get("success", false)):
			_debug_event("STALL_WATCHDOG_START_FAILED", watchdog_start)
			_live2_stall_watchdog = null
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_last_movement_snapshot_tick = _server_tick
	_last_debug_report_ms = _last_movement_checkpoint_ms
	set_process(true)
	_debug_event("SERVER_READY", {"host":_host,"port":_port,"persistence_root":_persistence_root,"recovered":_recovered})
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return _success({"host": _host, "port": _port})

func _process(delta: float) -> void:
	if not _configured or _boundary == null or _fatal_persistence_failure:
		return
	var smooth_started := Time.get_ticks_usec()
	# A single frame-local stamp sequence; when disabled, no timing calls
	# or extra trace writes are added to the accepted product path.
	var p22_marks: Array[int] = []
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(smooth_started)
	# Drain at most ONE post-durable stage from the PREVIOUS frame. A newly
	# completed writer cannot trigger its full snapshot/delta/ACK/broadcast
	# work in the same server frame (the R3C1 400-490ms completion burst).
	_r3c2_drain_postcommit_stage()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if _fatal_persistence_failure:
		return
	_p1b_poll_item_async_commit()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if _fatal_persistence_failure:
		return
	_complete_async_movement_checkpoint(false)
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if _fatal_persistence_failure:
		return
	# A transport leave must not mutate the authority during an in-flight
	# durable generation. Drain one deferred leave when the gate is clear.
	_drain_deferred_disconnects()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if _fatal_persistence_failure:
		return
	# R3C: one bounded pending JOIN/LEAVE admission per frame, never while an
	# older generation is inflight. Old transport-session disconnects win.
	_r3c_drain_deferred_admissions()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if _fatal_persistence_failure:
		return
	var process_started_us: int = Time.get_ticks_usec()
	var process_probe := _stall_enter("SERVER_PROCESS", {
		"server_tick": _server_tick,
		"connected_peers": _peer_to_player.size(),
		"messages_received": _messages_received,
		"messages_sent": _messages_sent,
	})
	_telemetry.increment("server_process_iterations")
	var poll_probe := _stall_enter("BOUNDARY_POLL", {
		"server_tick": _server_tick,
		"connected_peers": _peer_to_player.size(),
	})
	var polled: Dictionary = _boundary.poll_events(128)
	_stall_exit(poll_probe)
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "M3_SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		_stall_exit(process_probe)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			var payload: Dictionary = Dictionary(
				event.get("frame", {}).get("payload", {})
			).duplicate(true)
			var message_probe := _stall_enter(
				"MESSAGE:%s" % String(payload.get("type", "UNKNOWN")),
				_stall_context(
					peer_id,
					String(payload.get("operation_id", "")),
					String(payload.get("type", "UNKNOWN"))
				)
			)
			_handle_message(peer_id, session_id, payload)
			_stall_exit(message_probe)
		elif event_type == "PEER_DISCONNECTED":
			var disconnect_probe := _stall_enter(
				"PEER_DISCONNECT",
				_stall_context(peer_id, "", "PEER_DISCONNECTED")
			)
			_handle_disconnect(peer_id, session_id)
			_stall_exit(disconnect_probe)
	var smooth_messages_done := Time.get_ticks_usec()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	var fixed_probe := _stall_enter("FIXED_SIMULATION", {
		"server_tick": _server_tick,
		"pending_inputs": _total_pending_input_count(),
	})
	_advance_fixed_simulation(delta)
	_stall_exit(fixed_probe)
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	var smooth_fixed_done := Time.get_ticks_usec()
	var snapshot_probe := _stall_enter("MOVEMENT_SNAPSHOT_PUBLICATION", {
		"server_tick": _server_tick,
		"movement_dirty": _movement_snapshot_dirty,
	})
	_maybe_publish_movement_snapshot()
	_stall_exit(snapshot_probe)
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	var smooth_snapshot_done := Time.get_ticks_usec()
	# R3C.4: main-thread work already spent this frame BEFORE the periodic
	# capture stage (messages + fixed simulation + snapshot serialization).
	_r3c4_precapture_work_ms = float(smooth_snapshot_done - smooth_started) / 1000.0
	var persistence_probe := _stall_enter("MOVEMENT_PERSISTENCE", {
		"server_tick": _server_tick,
		"movement_dirty": _movement_checkpoint_dirty,
		"commands_since_checkpoint": _movement_commands_since_checkpoint,
	})
	_maybe_persist_movement_checkpoint()
	_stall_exit(persistence_probe)
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	_update_runtime_telemetry()
	if _r31p22_loop_attribution_enabled:
		p22_marks.append(Time.get_ticks_usec())
	var process_duration_ms: float = float(Time.get_ticks_usec() - process_started_us) / 1000.0
	_telemetry.observe("server_process_duration_ms", process_duration_ms)
	_stall_exit(process_probe)
	if SmoothTrace.enabled():
		var p22_server_loop_record: Dictionary = {"tick": _server_tick,
			"peers": _peer_to_player.size(), "rejections": _rejections,
			"process_ms": float(Time.get_ticks_usec() - smooth_started) / 1000.0,
			"message_ms": float(smooth_messages_done - smooth_started) / 1000.0,
			"fixed_ms": float(smooth_fixed_done - smooth_messages_done) / 1000.0,
			"snapshot_ms": float(smooth_snapshot_done - smooth_fixed_done) / 1000.0,
			"persistence_ms": float(Time.get_ticks_usec() - smooth_snapshot_done) / 1000.0,
			"dropped_time_s": _fixed_tick_scheduler.get_report().get("dropped_time_seconds", 0.0),
			"checkpoint_generation": _checkpoint_generation,
			"capture_ms": _async_checkpoint_capture_ms,
			"async_enabled": _movement_checkpoint_writer != null,
			"async_busy": _movement_checkpoint_writer != null and _movement_checkpoint_writer.is_busy()}
		if _r31p22_loop_attribution_enabled:
			p22_server_loop_record["engine_frame"] = Engine.get_process_frames()
		SmoothTrace.emit("server_loop", p22_server_loop_record)
	if _r31p22_loop_attribution_enabled and SmoothTrace.enabled():
		# One event per server frame; Engine.get_process_frames() matches
		# the high-priority NetSmoothProbe on this SAME process/frame.
		# No clock joins across server and client processes.
		if p22_marks.size() == 12:
			SmoothTrace.emit("r31p22_loop_stages", {
				"engine_frame": Engine.get_process_frames(),
				"server_tick": _server_tick,
				"polled_events": Array(polled.get("details", {}).get("events", [])).size(),
				"postcommit_ms": float(p22_marks[1] - p22_marks[0]) / 1000.0,
				"item_completion_ms": float(p22_marks[2] - p22_marks[1]) / 1000.0,
				"movement_completion_ms": float(p22_marks[3] - p22_marks[2]) / 1000.0,
				"deferred_disconnect_ms": float(p22_marks[4] - p22_marks[3]) / 1000.0,
				"deferred_admission_ms": float(p22_marks[5] - p22_marks[4]) / 1000.0,
				"boundary_poll_ms": float(p22_marks[6] - p22_marks[5]) / 1000.0,
				"message_dispatch_ms": float(p22_marks[7] - p22_marks[6]) / 1000.0,
				"fixed_simulation_ms": float(p22_marks[8] - p22_marks[7]) / 1000.0,
				"snapshot_publication_ms": float(p22_marks[9] - p22_marks[8]) / 1000.0,
				"movement_persistence_ms": float(p22_marks[10] - p22_marks[9]) / 1000.0,
				"telemetry_ms": float(p22_marks[11] - p22_marks[10]) / 1000.0,
				"message_span_ms": float(p22_marks[7] - p22_marks[0]) / 1000.0,
				"measured_total_ms": float(p22_marks[11] - p22_marks[0]) / 1000.0,
			})
	if _debug_logging and Time.get_ticks_msec() - _last_debug_report_ms >= 2000:
		_last_debug_report_ms = Time.get_ticks_msec()
		_debug_event("SERVER_HEALTH", {
			"connected_peers":_peer_to_player.size(),"moves":_moves,"rejections":_rejections,
			"messages_received":_messages_received,"messages_sent":_messages_sent,
			"checkpoint_generation":_checkpoint_generation,"movement_dirty":_movement_checkpoint_dirty,
			"movement_commands_since_checkpoint":_movement_commands_since_checkpoint,
			"last_error_code":_last_error_code,
			"stall_watchdog": (
				_live2_stall_watchdog.get_report()
				if _live2_stall_watchdog != null else {}
			),
		})

func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var handled_started_us: int = Time.get_ticks_usec()
	var client_sent_at_ms: int = int(payload.get("client_sent_at_ms", 0))
	if client_sent_at_ms > 0:
		_telemetry.observe("input_age_ms", float(maxi(Time.get_ticks_msec() - client_sent_at_ms, 0)))
	var message_type: String = String(payload.get("type", ""))
	if message_type == "COMPATIBILITY_HELLO":
		_handle_compatibility_hello(peer_id, session_id, payload)
	elif not _is_peer_compatible(peer_id, session_id):
		_reject_pre_handshake_message(peer_id, payload)
	else:
		match message_type:
			"JOIN": _handle_join(peer_id, session_id, payload)
			"MOVE": _handle_move(peer_id, session_id, payload)
			"PLAYER_INPUT": _handle_player_input(peer_id, session_id, payload)
			"PLAYER_INPUT_BATCH": _handle_player_input_batch(peer_id, session_id, payload)
			"PLAYER_STATE": _handle_player_state_rejected(peer_id, session_id, payload)
			"PRESENTATION": _handle_presentation(peer_id, session_id, payload)
			"ITEM_COMMAND": _handle_item_command(peer_id, session_id, payload)
			"ITEM_GRAPH_RESYNC_REQUEST": _handle_item_graph_resync_request(peer_id, session_id, payload)
			"CONSTRUCTION_COMMAND": _handle_construction_command(peer_id, session_id, payload)
			"LEAVE": _handle_leave(peer_id, session_id, payload)
			_: _send_result(peer_id, String(payload.get("operation_id", "")), "UNKNOWN", _failure("UNKNOWN_M3_MESSAGE_TYPE"))
	_telemetry.observe("server_message_processing_ms", float(Time.get_ticks_usec() - handled_started_us) / 1000.0)
	if SmoothTrace.enabled():
		SmoothTrace.emit("server_message", {"type": message_type, "peer": peer_id,
			"operation_id": payload.get("operation_id", ""), "tick": _server_tick,
			"duration_ms": float(Time.get_ticks_usec() - handled_started_us) / 1000.0})


func _handle_compatibility_hello(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_handshake_attempts += 1
	_telemetry.increment("handshake_attempts")
	var hello_value = payload.get("hello", {})
	var hello: Dictionary = Dictionary(hello_value).duplicate(true) if hello_value is Dictionary else {}
	var received_at_ms: int = Time.get_ticks_msec()
	var evaluation: Dictionary = CompatibilityHandshake.evaluate_server(
		_fingerprint, hello, received_at_ms
	)
	if not bool(evaluation.get("success", false)):
		_reject_handshake(
			peer_id,
			String(hello.get("handshake_id", "")),
			String(evaluation.get("error_code", "FINGERPRINT_MISMATCH"))
		)
		return
	var already_compatible: bool = _is_peer_compatible(peer_id, session_id)
	if not already_compatible:
		var handshaking: Dictionary = _boundary.mark_peer_handshaking(peer_id)
		if not bool(handshaking.get("success", false)) and String(
			handshaking.get("error_code", "")
		) != "INVALID_PEER_STATE_TRANSITION":
			_reject_handshake(peer_id, String(hello.get("handshake_id", "")), "PEER_HANDSHAKE_STATE_FAILED")
			return
	var ack: Dictionary = Dictionary(evaluation.get("details", {}).get("ack", {})).duplicate(true)
	if not _send_control(peer_id, "COMPATIBILITY_ACK", {"ack": ack}):
		_reject_handshake(peer_id, String(hello.get("handshake_id", "")), "FINGERPRINT_ACK_SEND_FAILED")
		return
	if already_compatible:
		_handshake_replays += 1
		_telemetry.increment("handshake_replays")
		return
	_peer_compatibility[peer_id] = {
		"session_id": session_id,
		"handshake_id": String(hello.get("handshake_id", "")),
		"verified_at_ms": Time.get_ticks_msec(),
		"client_fingerprint": Dictionary(hello.get("fingerprint", {})).duplicate(true),
	}
	_handshake_accepts += 1
	_telemetry.increment("handshake_accepts")
	for method_name in ["mark_peer_synchronizing", "mark_peer_ready"]:
		var transition: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(transition.get("success", false)):
			_last_error_code = "NX0_PEER_READY_FAILED"
			return


func _reject_handshake(peer_id: String, handshake_id: String, error_code: String) -> void:
	_handshake_rejections += 1
	_last_handshake_error_code = error_code
	_telemetry.increment("handshake_rejections")
	var safe_handshake_id: String = handshake_id
	if not CompatibilityHandshake.is_valid_handshake_id(safe_handshake_id):
		safe_handshake_id = "handshake/rejected/%s" % peer_id.sha256_text().left(16)
	var rejection: Dictionary = CompatibilityHandshake.create_rejection(
		safe_handshake_id, error_code, Time.get_ticks_msec()
	)
	_send_control(peer_id, "COMPATIBILITY_REJECTED", {"rejection": rejection})


func _reject_pre_handshake_message(peer_id: String, payload: Dictionary) -> void:
	var handshake_id: String = "handshake/prejoin/%s" % peer_id.sha256_text().left(16)
	_reject_handshake(peer_id, handshake_id, "FINGERPRINT_REQUIRED")
	_debug_event("PRE_HANDSHAKE_MESSAGE_REJECTED", {
		"peer_id": peer_id,
		"message_type": String(payload.get("type", "")),
	})


func _is_peer_compatible(peer_id: String, session_id: String) -> bool:
	var value = _peer_compatibility.get(peer_id)
	return value is Dictionary and String(value.get("session_id", "")) == session_id

# A deferred admission is an in-memory transport envelope, NOT a canonical
# mutation. It may be dropped on stale session / timeout without affecting M6.
func _r3c_defer_admission(
	kind: String, peer_id: String, session_id: String,
	logical_id: String, operation_id: String, payload: Dictionary
) -> bool:
	if not _r3c_async_admission_enabled or _fatal_persistence_failure:
		return false
	if _movement_checkpoint_writer == null or _p1b_item_async_owner == null:
		_enter_persistence_failure("R3C_SINGLE_WRITER_REQUIRED")
		return true
	var busy: bool = (
		not _gate_can_accept()
		or bool(_movement_checkpoint_writer.is_busy())
		or not _p1b_item_pending.is_empty()
		or String(_p1b_item_async_owner.get_report().get("phase", "")) != "IDLE"
	)
	if not busy:
		return false
	for queued in _r3c_deferred_admissions:
		var same_operation := String(queued.get("operation_id", "")) == operation_id
		var same_actor := (
			String(queued.get("peer_id", "")) == peer_id
			and String(queued.get("session_id", "")) == session_id
			and String(queued.get("logical_id", "")) == logical_id
			and String(queued.get("kind", "")) == kind
		)
		if same_operation and same_actor:
			return true  # exact retransmission: one queued mutation
		if same_operation or (same_actor and kind == "JOIN"):
			_r3c_reject_deferred_admission(kind, peer_id, operation_id, "R3C_ADMISSION_IDENTITY_CONFLICT")
			return true
	if _r3c_deferred_admissions.size() >= R3C_MAX_DEFERRED_ADMISSIONS:
		_r3c_reject_deferred_admission(kind, peer_id, operation_id, "R3C_ADMISSION_QUEUE_FULL")
		return true
	_r3c_deferred_admissions.append({
		"kind": kind, "peer_id": peer_id, "session_id": session_id,
		"logical_id": logical_id, "operation_id": operation_id,
		"payload": payload.duplicate(true),
		"queued_at_ms": Time.get_ticks_msec(),
	})
	if kind == "JOIN":
		_r3c_queued_joins += 1
	else:
		_r3c_queued_leaves += 1
	if SmoothTrace.enabled():
		SmoothTrace.emit("r3c_admission_queued", {
			"kind": kind, "operation_hash": operation_id.sha256_text().left(16),
			"queued_count": _r3c_deferred_admissions.size(),
			"generation": _checkpoint_generation,
		})
	return true


func _r3c_reject_deferred_admission(
	kind: String, peer_id: String, operation_id: String, code: String
) -> void:
	_rejections += 1
	if kind == "LEAVE":
		_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": code})
	else:
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": code})


func _r3c_discard_session_admissions(peer_id: String, session_id: String) -> void:
	for i in range(_r3c_deferred_admissions.size() - 1, -1, -1):
		var queued: Dictionary = _r3c_deferred_admissions[i]
		if String(queued.get("peer_id", "")) == peer_id and String(queued.get("session_id", "")) == session_id:
			_r3c_deferred_admissions.remove_at(i)
			_r3c_admissions_dropped += 1


func _r3c_drain_deferred_admissions() -> void:
	if not _r3c_async_admission_enabled or _r3c_deferred_admissions.is_empty():
		return
	# Retire stale peers even when the writer remains continuously busy.
	for i in range(_r3c_deferred_admissions.size() - 1, -1, -1):
		var queued: Dictionary = _r3c_deferred_admissions[i]
		var queued_peer_id := String(queued.get("peer_id", ""))
		var queued_session_id := String(queued.get("session_id", ""))
		var expired := Time.get_ticks_msec() - int(queued.get("queued_at_ms", 0)) > R3C_ADMISSION_TIMEOUT_MS
		var compatible := _is_peer_compatible(queued_peer_id, queued_session_id)
		if expired or not compatible:
			if expired and compatible:
				_r3c_reject_deferred_admission(
					String(queued.get("kind", "")), queued_peer_id,
					String(queued.get("operation_id", "")), "R3C_ADMISSION_TIMEOUT"
				)
			_r3c_deferred_admissions.remove_at(i)
			_r3c_admissions_dropped += 1
	if _r3c_deferred_admissions.is_empty() or not _gate_can_accept():
		return
	if _movement_checkpoint_writer == null or _movement_checkpoint_writer.is_busy():
		return
	# LEAVE must precede replacement JOIN for the same logical player. At most
	# one admission is retried per server frame; no unbounded catch-up loop.
	var selected := 0
	for i in range(_r3c_deferred_admissions.size()):
		if String(_r3c_deferred_admissions[i].get("kind", "")) == "LEAVE":
			selected = i
			break
	var next: Dictionary = _r3c_deferred_admissions[selected]
	_r3c_deferred_admissions.remove_at(selected)
	var peer_id := String(next.get("peer_id", ""))
	var session_id := String(next.get("session_id", ""))
	if not _is_peer_compatible(peer_id, session_id):
		_r3c_admissions_dropped += 1
		return
	var kind := String(next.get("kind", ""))
	var operation_id := String(next.get("operation_id", ""))
	if kind == "LEAVE" and String(_peer_to_session.get(peer_id, "")) != session_id:
		_r3c_admissions_dropped += 1
		return
	_r3c_admissions_drained += 1
	if SmoothTrace.enabled():
		SmoothTrace.emit("r3c_admission_drained", {
			"kind": kind, "operation_hash": operation_id.sha256_text().left(16),
			"wait_ms": Time.get_ticks_msec() - int(next.get("queued_at_ms", 0)),
			"queue_remaining": _r3c_deferred_admissions.size(),
		})
	if kind == "LEAVE":
		_handle_leave(peer_id, session_id, Dictionary(next.get("payload", {})))
	elif kind == "JOIN":
		_handle_join(peer_id, session_id, Dictionary(next.get("payload", {})))


func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if logical_id.is_empty() or not _is_canonical_operation_id(operation_id):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "INVALID_JOIN_PAYLOAD"})
		return
	# R3C: retain a bounded, identity-fenced admission instead of rejecting
	# reconnect JOIN while an older M6 generation owns the single writer.
	# No service.join(), replay record or ACK exists while this is queued.
	if _r3c_defer_admission("JOIN", peer_id, session_id, logical_id, operation_id, payload):
		return
	if not _gate_can_accept():
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": _gate_reject_code()})
		return
	var result: Dictionary = _service.join(logical_id, session_id, operation_id)
	var immediate_join_persistence := true
	if _service.has_method("requires_immediate_join_persistence"):
		immediate_join_persistence = bool(
			_service.requires_immediate_join_persistence()
		)
	var join_ownership_epoch := int(
		Dictionary(result.get("details", {}).get("player", {})).get("ownership_epoch", 0)
	)
	if (
		immediate_join_persistence
		and not _persist_command_result(operation_id, "JOIN", logical_id, result, peer_id, session_id, join_ownership_epoch)
	):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	if not bool(result.get("success", false)):
		_rejections += 1
		var rejection_sent := _send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "JOIN_REJECTED"))})
		if rejection_sent:
			_mark_operation_delivered(operation_id)
		_write_report("READY", false)
		return
	_peer_to_player[peer_id] = logical_id
	_peer_to_session[peer_id] = session_id
	_peer_input_buffers.erase(peer_id)
	_ensure_input_buffer(peer_id, logical_id)
	if join_ownership_epoch > 0:
		_player_ownership_epochs[logical_id] = join_ownership_epoch
	_debug_event("PLAYER_JOINED", {"peer_id":peer_id,"session_id":session_id,"logical_player_id":logical_id})
	var replay := _is_replay_result(result)
	if not replay:
		_joins += 1
	if immediate_join_persistence and not _gate_preflight_success_result(
		operation_id, peer_id, session_id, logical_id, join_ownership_epoch, result
	):
		return
	var join_sent := _send_on_channel(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"player": result.get("details", {}).get("player", {}),
		"snapshot": result.get("details", {}).get("snapshot", {}),
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot(),
	}, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
	if join_sent:
		_item_graph_full_snapshots_published += 1
		# The JOIN_ACK left only after the real reliable enqueue; the escrowed
		# record may be dropped for this exact session/epoch fence.
		if immediate_join_persistence:
			_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, join_ownership_epoch, result, true)
		if not immediate_join_persistence:
			_fast_join_acks += 1
			_telemetry.increment("fast_join_acks")
			_debug_event("JOIN_ACK_FAST_PATH", {
				"logical_player_id": logical_id,
				"operation_id": operation_id,
				"persistence_deferred": true,
			})
	if immediate_join_persistence and not join_sent:
		_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, join_ownership_epoch, result, false)
	if _fatal_persistence_failure:
		return
	if _construction_bridge != null:
		var player: Dictionary = Dictionary(result.get("details", {}).get("player", {}))
		var construction_join: Dictionary = _construction_bridge.connect_player(logical_id, int(player.get("ownership_epoch", 0)))
		if bool(construction_join.get("success", false)):
			var construction_snapshot: Dictionary = Dictionary(construction_join.get("details", {}).get("snapshot", {}))
			if not construction_snapshot.is_empty() and _send_on_channel(peer_id, "CONSTRUCTION_SNAPSHOT", construction_snapshot, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED"):
				_construction_snapshots_published += 1
		else:
			_last_error_code = String(construction_join.get("error_code", "M3_CONSTRUCTION_JOIN_FAILED"))
	if not replay:
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_broadcast_snapshot("PLAYER_JOINED")
		_broadcast_item_snapshot("PLAYER_JOINED", peer_id)
		_capture_two_connected_checksum()
	if join_sent:
		_mark_operation_delivered(operation_id)
		_send_product_seam_state(peer_id, logical_id, "PLAYER_JOINED")
	_write_report("READY", false)

func _handle_move(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "MOVE", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "MOVE",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	# R4.1-P1: refuse new mutations while a durable command commit is pending
	# or the gate is in fail-closed state.
	if not _gate_can_accept():
		_reject_uncommitted_command(peer_id, operation_id, "MOVE", _gate_reject_code())
		return
	var move_ownership_epoch := _stored_ownership_epoch(logical_id, int(payload.get("ownership_epoch", 0)))
	var result: Dictionary = _service.move_player(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		operation_id
	)
	if not _persist_command_result(operation_id, "MOVE", logical_id, result, peer_id, session_id, move_ownership_epoch):
		_send_result(peer_id, operation_id, "MOVE", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	if not _gate_preflight_success_result(operation_id, peer_id, session_id, logical_id, move_ownership_epoch, result):
		return
	var result_sent := _send_result(peer_id, operation_id, "MOVE", result)
	_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, move_ownership_epoch, result, result_sent)
	if _fatal_persistence_failure:
		return
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_moves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_MOVED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_player_input(peer_id: String, session_id: String, payload: Dictionary) -> void:
	# Compatibility path for older probes. Production NX2 clients send PLAYER_INPUT_BATCH.
	var intent_value = payload.get("intent", {})
	if not intent_value is Dictionary:
		_reject_uncommitted_command(peer_id, String(payload.get("operation_id", "")), "PLAYER_INPUT", "MOVEMENT_INTENT_REQUIRED")
		return
	var input_entry: Dictionary = {
		"input_sequence": int(payload.get("input_sequence", 0)),
		"operation_id": String(payload.get("operation_id", "")),
		"client_tick": int(payload.get("client_tick", payload.get("input_sequence", 0))),
		"client_sent_at_ms": int(payload.get("client_sent_at_ms", 0)),
		"intent": Dictionary(intent_value).duplicate(true),
	}
	var batch: Dictionary = PlayerInputBatch.create(
		"input-batch/legacy/%s/%d" % [peer_id.sha256_text().left(12), int(input_entry["input_sequence"])],
		String(payload.get("logical_player_id", _peer_to_player.get(peer_id, ""))),
		int(payload.get("ownership_epoch", 0)),
		[input_entry],
		String(payload.get("operation_id", ""))
	)
	_handle_player_input_batch(peer_id, session_id, {"batch": batch})


func _handle_player_input_batch(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_movement_batches_received += 1
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, "operation/nx3/stale/%s" % peer_id.sha256_text().left(12), "PLAYER_INPUT", _failure("STALE_TRANSPORT_SESSION"))
		return
	var batch_value = payload.get("batch", {})
	if not batch_value is Dictionary:
		_send_result(peer_id, "operation/nx3/invalid/%s" % peer_id.sha256_text().left(12), "PLAYER_INPUT", _failure("PLAYER_INPUT_BATCH_REQUIRED"))
		return
	var batch: Dictionary = Dictionary(batch_value).duplicate(true)
	var batch_check: Dictionary = PlayerInputBatch.validate(batch)
	if not bool(batch_check.get("success", false)):
		var invalid_operation_id: String = _latest_batch_operation_id(batch)
		_last_movement_rejection_error_code = String(batch_check.get("error_code", "INVALID_PLAYER_INPUT_BATCH"))
		_last_movement_rejection_stage = "BATCH_VALIDATE"
		_send_result(peer_id, invalid_operation_id, "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var logical_id: String = String(_peer_to_player.get(peer_id, ""))
	if String(batch.get("logical_player_id", "")) != logical_id:
		_last_movement_rejection_error_code = "PLAYER_INPUT_BATCH_PLAYER_MISMATCH"
		_last_movement_rejection_stage = "PLAYER_MATCH"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var player: Dictionary = _service.get_player(logical_id)
	if int(batch.get("ownership_epoch", 0)) != int(player.get("ownership_epoch", 0)):
		_last_movement_rejection_error_code = "STALE_PLAYER_OWNERSHIP_EPOCH"
		_last_movement_rejection_stage = "OWNERSHIP"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var expanded_result: Dictionary = PlayerInputBatch.expand_inputs(batch)
	if not bool(expanded_result.get("success", false)):
		_last_movement_rejection_error_code = String(expanded_result.get("error_code", "PLAYER_INPUT_BATCH_EXPAND_FAILED"))
		_last_movement_rejection_stage = "BATCH_EXPAND"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", expanded_result)
		_movement_inputs_rejected += 1
		return
	var buffer = _ensure_input_buffer(peer_id, logical_id)
	if buffer == null:
		_last_movement_rejection_error_code = "NX3_INPUT_BUFFER_SETUP_FAILED"
		_last_movement_rejection_stage = "INPUT_BUFFER"
		_send_result(peer_id, _latest_batch_operation_id(batch), "PLAYER_INPUT", _failure(_last_movement_rejection_error_code))
		_movement_inputs_rejected += 1
		return
	var inputs: Array = expanded_result.get("details", {}).get("inputs", [])
	_movement_inputs_received += inputs.size()
	var accepted_any: bool = false
	var redundant_any: bool = false
	for input_value in inputs:
		var input: Dictionary = Dictionary(input_value).duplicate(true)
		var queued: Dictionary = buffer.enqueue(input, _server_tick)
		if bool(queued.get("success", false)):
			if bool(queued.get("details", {}).get("accepted", false)):
				accepted_any = true
			else:
				redundant_any = true
				_movement_inputs_redundant += 1
		else:
			_movement_inputs_rejected += 1
			_last_movement_rejection_error_code = String(queued.get("error_code", "NX3_INPUT_QUEUE_REJECTED"))
			_last_movement_rejection_stage = "INPUT_QUEUE"
			_send_result(peer_id, String(input.get("operation_id", _latest_batch_operation_id(batch))), "PLAYER_INPUT", queued)
	if redundant_any and not accepted_any:
		_movement_snapshot_dirty = true
		_movement_snapshot_retransmit_requests += 1

func _ensure_input_buffer(peer_id: String, logical_id: String):
	if _peer_input_buffers.has(peer_id):
		return _peer_input_buffers[peer_id]
	var buffer = FixedTickInputBuffer.new()
	var setup_result: Dictionary = buffer.configure(_last_processed_input_sequence(logical_id))
	if not bool(setup_result.get("success", false)):
		return null
	_peer_input_buffers[peer_id] = buffer
	return buffer

func _advance_fixed_simulation(frame_delta_seconds: float) -> void:
	if _fixed_tick_scheduler == null or _service == null:
		return
	var scheduled: Dictionary = _fixed_tick_scheduler.advance(frame_delta_seconds)
	if not bool(scheduled.get("success", false)):
		_fixed_tick_failures += 1
		_last_error_code = String(scheduled.get("error_code", "NX3_FIXED_TICK_SCHEDULER_FAILED"))
		return
	var tick_count: int = int(scheduled.get("details", {}).get("tick_count", 0))
	if tick_count > 1:
		_fixed_tick_catch_up_batches += 1
	var first_tick: int = int(scheduled.get("details", {}).get("first_tick", _server_tick))
	for offset in range(tick_count):
		_run_fixed_tick(first_tick + offset)

func _run_fixed_tick(server_tick: int) -> void:
	var started_us: int = Time.get_ticks_usec()
	var advanced: Dictionary = _service.advance_fixed_server_tick(server_tick)
	if not bool(advanced.get("success", false)):
		_fixed_tick_failures += 1
		_last_error_code = String(advanced.get("error_code", "NX3_SERVER_TICK_ADVANCE_FAILED"))
		return
	_server_tick = server_tick
	_fixed_ticks_simulated += 1
	var peer_ids: Array[String] = []
	for peer_id_value in _peer_to_player.keys():
		peer_ids.append(String(peer_id_value))
	peer_ids.sort()
	for peer_id in peer_ids:
		var logical_id: String = String(_peer_to_player.get(peer_id, ""))
		var session_id: String = String(_peer_to_session.get(peer_id, ""))
		if logical_id.is_empty() or session_id.is_empty():
			continue
		var buffer = _ensure_input_buffer(peer_id, logical_id)
		if buffer == null:
			continue
		var before_report: Dictionary = buffer.get_report(server_tick)
		var consumed: Dictionary = buffer.consume_for_tick(server_tick)
		if not bool(consumed.get("success", false)):
			_fixed_tick_failures += 1
			continue
		var sequence: int = int(consumed.get("details", {}).get("input_sequence", 0))
		if sequence < 1:
			continue
		var intent: Dictionary = Dictionary(consumed.get("details", {}).get("intent", {})).duplicate(true)
		intent["delta_seconds"] = NX3_FIXED_TICK_DELTA_SECONDS
		var player: Dictionary = _service.get_player(logical_id)
		var result: Dictionary = _service.simulate_fixed_movement_tick(
			logical_id,
			session_id,
			int(player.get("ownership_epoch", 0)),
			sequence,
			intent,
			NX3_FIXED_TICK_DELTA_SECONDS
		)
		var consumed_new: bool = bool(consumed.get("details", {}).get("consumed_new_input", false))
		if not bool(result.get("success", false)):
			_fixed_tick_failures += 1
			if consumed_new:
				_movement_inputs_rejected += 1
				_last_movement_rejection_error_code = String(result.get("error_code", "NX3_FIXED_MOVEMENT_REJECTED"))
				_last_movement_rejection_stage = "FIXED_TICK_SIMULATION"
				_send_result(peer_id, String(consumed.get("details", {}).get("operation_id", "")), "PLAYER_INPUT", result)
			continue
		if consumed_new:
			_moves += 1
			_movement_inputs_applied += 1
			_movement_results_suppressed += 1
			_movement_deltas_suppressed += 1
			_movement_full_snapshots_suppressed += 1
			_movement_commands_since_checkpoint += 1
			_movement_snapshot_dirty = true
		if bool(result.get("details", {}).get("changed", false)):
			_movement_snapshot_dirty = true
			_movement_checkpoint_dirty = true
		var after_report: Dictionary = buffer.get_report(server_tick)
		_input_queue_stale_drops += maxi(
			int(after_report.get("stale_dropped", 0)) - int(before_report.get("stale_dropped", 0)), 0
		)
		_input_hold_expirations += maxi(
			int(after_report.get("hold_expirations", 0)) - int(before_report.get("hold_expirations", 0)), 0
		)
		_telemetry.observe("input_queue_age_ticks", float(consumed.get("details", {}).get("queue_age_ticks", 0)))
	_last_fixed_tick_duration_ms = float(Time.get_ticks_usec() - started_us) / 1000.0
	_telemetry.observe("server_tick_duration_ms", _last_fixed_tick_duration_ms)
	_telemetry.set_gauge("server_tick", float(_server_tick))

func _latest_batch_operation_id(batch: Dictionary) -> String:
	var operation_id: String = String(batch.get("operation_id", ""))
	if _is_canonical_operation_id(operation_id):
		return operation_id
	return "operation/nx2/invalid/%s" % NetworkUtilsScript.canonical_json(batch).sha256_text().left(16)


func _last_processed_input_sequence(logical_id: String) -> int:
	if _service == null:
		return 0
	for player_value in _service.create_snapshot().get("players", []):
		if player_value is Dictionary and String(player_value.get("logical_player_id", "")) == logical_id:
			return int(player_value.get("last_input_sequence", 0))
	return 0


func _maybe_publish_movement_snapshot() -> void:
	if not _movement_snapshot_dirty or _service == null:
		return
	# R3.1: retain the 20Hz 60/3 tick while the ITEM writer is pending.
	# The full/ITEM resync barrier is NOT relaxed.
	if _server_tick - _last_movement_snapshot_tick < NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS:
		return
	_last_movement_snapshot_tick = _server_tick
	var snapshot_started_us := Time.get_ticks_usec()
	var pending_view := not _p1b_item_pending.is_empty()
	var authoritative_snapshot: Dictionary
	if pending_view:
		var view: Dictionary = _build_p1b_committed_movement_snapshot()
		if not bool(view.get("success", false)):
			_p1b_committed_rejections += 1
			_last_error_code = String(view.get("error_code", "P1B_COMMITTED_VIEW_REJECTED"))
			return  # fail closed; never fall back to speculative live snapshot
		authoritative_snapshot = Dictionary(view.get("details", {}).get("snapshot", {}))
		_p1b_committed_frames += 1
	else:
		authoritative_snapshot = _service.create_snapshot()
	var snapshot_captured_us := Time.get_ticks_usec()
	var compact_result: Dictionary = CompactGameplaySnapshot.encode(authoritative_snapshot)
	var snapshot_encoded_us := Time.get_ticks_usec()
	if not bool(compact_result.get("success", false)):
		_compact_movement_snapshot_failures += 1
		_last_error_code = String(compact_result.get("error_code", "COMPACT_GAMEPLAY_SNAPSHOT_BUILD_FAILED"))
		return
	# encode() returns a new value object. FrameScript.create() converts it to
	# isolated canonical JSON per peer; no extra full snapshot copy here.
	var compact_snapshot: Dictionary = Dictionary(compact_result.get("details", {}).get("snapshot", {}))
	var sent_started_us := Time.get_ticks_usec()
	var compact_send_us := 0
	var seam_check_send_us := 0
	var seam_sent_before := _seam_messages_sent
	var seam_skipped_before := _seam_unchanged_skipped
	var all_enqueued := true
	var committed_enqueues_before := _p1b_committed_enqueues
	var target_count := 0
	for peer_id_value in _peer_to_player.keys():
		target_count += 1
		var peer_id := String(peer_id_value)
		if pending_view and not CommittedView.peer_is_fenced(
			authoritative_snapshot, String(_peer_to_player.get(peer_id, "")),
			String(_peer_to_session.get(peer_id, ""))
		):
			continue  # changed transport session never inherits committed view
		var compact_started_us := Time.get_ticks_usec()
		var compact_queued := _send_on_channel(
			peer_id,
			"COMPACT_GAMEPLAY_SNAPSHOT",
			{"reason": "P1B_COMMITTED_VIEW_MOVEMENT" if pending_view else "MOVEMENT_NETWORK_TICK",
			"snapshot": compact_snapshot},
			RealtimeChannelPolicy.SNAPSHOT,
			"UNRELIABLE_SEQUENCED"
		)
		compact_send_us += Time.get_ticks_usec() - compact_started_us
		if compact_queued:
			_broadcasts += 1
			_compact_movement_snapshots_published += 1
			if pending_view:
				_p1b_committed_enqueues += 1
			else:
				# USER1 seam resync remains reliable and live only after commit.
				var seam_started_us := Time.get_ticks_usec()
				_send_product_seam_state(
					peer_id,
					String(_peer_to_player.get(peer_id_value, "")),
					"MOVEMENT_NETWORK_TICK"
				)
				seam_check_send_us += Time.get_ticks_usec() - seam_started_us
		else:
			all_enqueued = false
			_movement_snapshot_enqueue_failures += 1
	_movement_snapshot_dirty = target_count > 0 and not all_enqueued
	if all_enqueued and target_count > 0:
		_movement_snapshots_published += 1
	if SmoothTrace.enabled():
		var p22_snapshot_stage_record: Dictionary = {
			"tick": _server_tick, "peers": target_count,
			"committed_view": pending_view,
			"pending_kind": String(_p1b_item_pending.get("kind", "ITEM")) if pending_view else "",
			"committed_enqueues": _p1b_committed_enqueues - committed_enqueues_before,
			"all_enqueued": all_enqueued,
			"capture_ms": float(snapshot_captured_us - snapshot_started_us) / 1000.0,
			"encode_ms": float(snapshot_encoded_us - snapshot_captured_us) / 1000.0,
			"send_and_seam_ms": float(Time.get_ticks_usec() - sent_started_us) / 1000.0,
			"compact_send_ms": float(compact_send_us) / 1000.0,
			"seam_check_send_ms": float(seam_check_send_us) / 1000.0,
			"seam_sent": _seam_messages_sent - seam_sent_before,
			"seam_skipped_unchanged": _seam_unchanged_skipped - seam_skipped_before,
		}
		if _r31p22_loop_attribution_enabled:
			p22_snapshot_stage_record["engine_frame"] = Engine.get_process_frames()
		SmoothTrace.emit("movement_snapshot_stages", p22_snapshot_stage_record)

# This reader only fetches *movement* records from the live service; every
# durable field is sourced from the verified snapshot captured pre-ITEM.
func _build_p1b_committed_movement_snapshot() -> Dictionary:
	if _p1b_committed_view.is_empty() or _service == null:
		return _failure("P1B_COMMITTED_VIEW_BASE_REQUIRED")
	var moving: Array = []
	for player_value in _p1b_committed_view.get("players", []):
		if not player_value is Dictionary:
			return _failure("P1B_COMMITTED_VIEW_PLAYER_INVALID")
		var id := String(Dictionary(player_value).get("logical_player_id", ""))
		var live: Dictionary = _service.get_player(id)
		if not live.is_empty():
			moving.append(live)
	return CommittedView.project(_p1b_committed_view, moving, _server_tick)


func _send_product_seam_state(
	peer_id: String,
	logical_player_id: String,
	reason: String
) -> bool:
	if (
		_service == null
		or not _service.has_method("get_product_seam_state")
		or logical_player_id.is_empty()
	):
		return false
	var state_value = _service.get_product_seam_state(logical_player_id)
	if not state_value is Dictionary or Dictionary(state_value).is_empty():
		return false
	var state: Dictionary = Dictionary(state_value)
	var session_id := String(_peer_to_session.get(peer_id, ""))
	var last_value: Dictionary = Dictionary(_seam_sent_state_by_peer.get(peer_id, {}))
	# Never suppress the initial or repeat JOIN: it is a reliable resync fence.
	# Subsequent movement frames must not flood the RELIABLE_ORDERED RESYNC
	# channel with the same 13-field seam state 20 times per second. A new
	# session, changed player identity, or actual authority transfer resends.
	if (
		reason != "PLAYER_JOINED"
		and bool(last_value.get("sent", false))
		and String(last_value.get("session_id", "")) == session_id
		and String(last_value.get("logical_player_id", "")) == logical_player_id
		and Dictionary(last_value.get("state", {})) == state
	):
		_seam_unchanged_skipped += 1
		return true
	var sent := _send_on_channel(
		peer_id,
		"PRODUCT_SEAM_STATE",
		{
			"reason": reason,
			"state": state,  # The service getter already returns a detached projection.
		},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		# Only cache a successfully queued, reliable frame. Failed dispatches
		# must be retried; never advance a cache on a rejected send.
		_seam_sent_state_by_peer[peer_id] = {
			"sent": true,
			"session_id": session_id,
			"logical_player_id": logical_player_id,
			"state": state.duplicate(true),
		}
		_seam_messages_sent += 1
	return sent


func _handle_player_state_rejected(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "PLAYER_STATE", _failure("STALE_TRANSPORT_SESSION"))
		return
	_reject_uncommitted_command(peer_id, operation_id, "PLAYER_STATE", "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")


func _handle_presentation(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "PRESENTATION", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "PRESENTATION",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if not _gate_can_accept():
		_reject_uncommitted_command(peer_id, operation_id, "PRESENTATION", _gate_reject_code())
		return
	var presentation_epoch := _stored_ownership_epoch(logical_id, int(payload.get("ownership_epoch", 0)))
	var result: Dictionary = _service.set_player_presentation(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		float(payload.get("orientation_yaw", 0.0)), bool(payload.get("flashlight_enabled", false)), operation_id
	)
	if not _persist_command_result(operation_id, "PRESENTATION", logical_id, result, peer_id, session_id, presentation_epoch):
		_send_result(peer_id, operation_id, "PRESENTATION", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	if not _gate_preflight_success_result(operation_id, peer_id, session_id, logical_id, presentation_epoch, result):
		return
	var result_sent := _send_result(peer_id, operation_id, "PRESENTATION", result)
	_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, presentation_epoch, result, result_sent)
	if _fatal_persistence_failure:
		return
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_presentation_updates += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_PRESENTATION_UPDATED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _handle_item_graph_resync_request(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		return
	_item_graph_resync_requests += 1
	var operation_id: String = String(payload.get("operation_id", ""))
	if not _p1b_item_pending.is_empty():
		# A reliable resync requested mid-commit must NOT read a mutable graph.
		# Keep one bounded waiter per peer/session; serve after worker commit.
		if (
			_p1b_item_resync_waiters.has(peer_id)
			or _p1b_item_resync_waiters.size() < P1B_MAX_DEFERRED_ITEM_RESYNCS
		):
			_p1b_item_resync_waiters[peer_id] = {
				"session_id": session_id, "operation_id": operation_id
			}
		else:
			_last_error_code = "P1B_ITEM_RESYNC_QUEUE_FULL"
		return
	var sent: bool = _send_on_channel(
		peer_id,
		"ITEM_GRAPH_SNAPSHOT",
		{
			"reason": "EXPLICIT_RESYNC",
			"operation_id": operation_id,
			"snapshot": _service.create_canonical_item_graph_snapshot(),
		},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		_item_graph_full_snapshots_published += 1


func _broadcast_item_snapshot(reason: String, excluded_peer_id: String = "") -> void:
	if not _p1b_item_pending.is_empty():
		# R3: compact committed-view MOVEMENT is allowed, but this is a
		# canonical full ITEM graph snapshot and remains strictly blocked.
		# Both full gameplay and item-graph holds are observable.
		_p1b_item_precommit_snapshot_holds += 1
		_p1b_item_graph_snapshot_holds += 1
		return
	var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(
			peer_id,
			"ITEM_GRAPH_SNAPSHOT",
			{"reason": reason, "snapshot": snapshot},
			RealtimeChannelPolicy.RESYNC,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_item_graph_full_snapshots_published += 1


func _handle_item_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "ITEM_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	var command_type := String(payload.get("command_type", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "ITEM_COMMAND",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if command_type.is_empty():
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_TYPE_REQUIRED")
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_PAYLOAD_REQUIRED")
		return
	if not _gate_can_accept():
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", _gate_reject_code())
		return
	var item_epoch := _stored_ownership_epoch(logical_id, int(payload.get("ownership_epoch", 0)))
	var p1b_reserved := false
	if _p1b_item_async_enabled and not _service.has_durable_replay_operation(operation_id):
		var reservation: Dictionary = _p1b_item_async_owner.reserve_mutation(
			operation_id, peer_id, session_id, logical_id, item_epoch, command_type
		)
		if not bool(reservation.get("success", false)):
			_reject_uncommitted_command(peer_id, operation_id, command_type,
				String(reservation.get("error_code", "P1B_ITEM_RESERVATION_FAILED")))
			return
		p1b_reserved = true
	var stage_context := _stall_context(peer_id, operation_id, command_type)
	var before_probe := _stall_enter("ITEM:BEFORE_SNAPSHOT", stage_context)
	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var before_gameplay_snapshot: Dictionary = {}
	if p1b_reserved:
		before_gameplay_snapshot = _service.create_snapshot()
		if not bool(FullSnapshot.validate(before_gameplay_snapshot).get("success", false)):
			_p1b_item_async_owner.release_noncommitting_reservation(
				operation_id, _failure("P1B_PREITEM_VIEW_INVALID")
			)
			_stall_exit(before_probe)
			_enter_persistence_failure("P1B_PREITEM_VIEW_INVALID")
			return
	_stall_exit(before_probe)
	var execute_probe := _stall_enter("ITEM:EXECUTE", stage_context)
	var result: Dictionary = _service.handle_canonical_item_command(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		operation_id, command_type, Dictionary(command_payload_value)
	)
	_stall_exit(execute_probe)
	if p1b_reserved:
		if bool(result.get("success", false)) and not _is_replay_result(result):
			if not _p1b_begin_item_async_commit(
				operation_id, command_type, logical_id, result,
				peer_id, session_id, item_epoch, before_item_snapshot,
				before_gameplay_snapshot
			):
				# The mutation happened, so failure is fatal and no success
				# result may escape as an uncommitted state.
				return
			return
		var released: Dictionary = _p1b_item_async_owner.release_noncommitting_reservation(
			operation_id, result
		)
		if not bool(released.get("success", false)):
			_enter_persistence_failure("P1B_ITEM_RESERVATION_RELEASE_FAILED")
			return
	var persist_probe := _stall_enter("ITEM:PERSIST_RESULT", stage_context)
	var persisted_result := _persist_command_result(operation_id, command_type, logical_id, result, peer_id, session_id, item_epoch)
	_stall_exit(persist_probe)
	if not persisted_result:
		_send_result(peer_id, operation_id, command_type, _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var item_delta: Dictionary = {}
	var item_delta_fallback_required: bool = false
	if bool(result.get("success", false)) and not _is_replay_result(result):
		var after_probe := _stall_enter("ITEM:AFTER_SNAPSHOT", stage_context)
		var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		_stall_exit(after_probe)
		var delta_probe := _stall_enter("ITEM:DELTA_BUILD", stage_context)
		var delta_result: Dictionary = CanonicalItemGraphDelta.create(before_item_snapshot, after_item_snapshot)
		_stall_exit(delta_probe)
		if not bool(delta_result.get("success", false)):
			# The authoritative mutation has already committed durably. Never convert it
			# into a rejection after commit; recover replication with a full resync.
			item_delta_fallback_required = true
			_item_graph_delta_build_failures += 1
			_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
		else:
			item_delta = Dictionary(delta_result.get("details", {}).get("delta", {})).duplicate(true)
	if not _gate_preflight_success_result(operation_id, peer_id, session_id, logical_id, item_epoch, result):
		return
	var send_probe := _stall_enter("ITEM:RESULT_SEND", stage_context)
	var result_sent := _send_result(peer_id, operation_id, command_type, result, item_delta)
	_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, item_epoch, result, result_sent)
	_stall_exit(send_probe)
	if _fatal_persistence_failure:
		return
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			var replication_probe := _stall_enter("ITEM:REPLICATION", stage_context)
			if item_delta_fallback_required:
				_broadcast_item_snapshot("ITEM_GRAPH_DELTA_BUILD_FALLBACK")
			else:
				_broadcast_item_delta(item_delta, peer_id, command_type)
			# Gameplay metadata still advances; publish one reliable resync snapshot,
			# but never embed the full Item Graph in ordinary results.
			_broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
			_capture_two_connected_checksum()
			_stall_exit(replication_probe)
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


# P1-B R2 canary: the authoritative ITEM mutation has occurred, but until the
# detached worker commits it, no success result, delta, full or compact frame
# can reveal the uncommitted canonical item state.
func _p1b_begin_item_async_commit(
	operation_id: String, command_type: String, logical_id: String,
	result: Dictionary, peer_id: String, session_id: String, ownership_epoch: int,
	before_item_snapshot: Dictionary,
	before_gameplay_snapshot: Dictionary,
	commit_kind: String = "ITEM"
) -> bool:
	if not _p1b_item_pending.is_empty() or _p1b_item_async_owner == null:
		_enter_persistence_failure("P1B_ITEM_SINGLE_INFLIGHT_REQUIRED")
		return false
	if not _service.has_durable_replay_operation(operation_id):
		_enter_persistence_failure("P1B_ITEM_M6_REPLAY_OWNER_REQUIRED")
		return false
	if before_gameplay_snapshot.is_empty():
		_enter_persistence_failure("P1B_PREITEM_VIEW_REQUIRED")
		return false
	if commit_kind not in ["ITEM", "DISCONNECT", "LEAVE"]:
		_enter_persistence_failure("R3B_DURABLE_COMMIT_KIND_UNSUPPORTED")
		return false
	_p1b_committed_view = before_gameplay_snapshot  # already detached DTO
	var capture_start_us := Time.get_ticks_usec()
	var player_checksum := String(_service.create_snapshot().get("checksum", ""))
	var player_done_us := Time.get_ticks_usec()
	# This detached canonical ITEM snapshot is already built to bind the
	# outbox checksum. Keep it for post-durable replication in R3C2 instead
	# of recomputing the whole graph after the worker finishes.
	var frozen_after_item: Dictionary = _service.create_canonical_item_graph_snapshot()
	var item_checksum := String(frozen_after_item.get("checksum", ""))
	var item_done_us := Time.get_ticks_usec()
	var outbox_staged: Dictionary = _replay_outbox.stage_committed(
		operation_id, command_type,
		{
			"logical_player_id": logical_id,
			"success": true,
			"error_code": "",
			"result": result.duplicate(true),
			"player_snapshot_checksum": player_checksum,
			"item_graph_checksum": item_checksum,
		}
	)
	var outbox_done_us := Time.get_ticks_usec()
	if not bool(outbox_staged.get("success", false)):
		_enter_persistence_failure("P1B_ITEM_OUTBOX_STAGE_FAILED")
		return false
	if _service.has_method("prepare_product_persistence_quiescence_only"):
		var quiesced: Dictionary = _service.prepare_product_persistence_quiescence_only()
		if not bool(quiesced.get("success", false)):
			_last_persistence_error_details = quiesced.duplicate(true)
			_enter_persistence_failure("P1B_ITEM_SEAM_QUIESCENCE_FAILED")
			return false
	elif _service.has_method("prepare_product_persistence"):
		var quiesced: Dictionary = _service.prepare_product_persistence()
		if not bool(quiesced.get("success", false)):
			_last_persistence_error_details = quiesced.duplicate(true)
			_enter_persistence_failure("P1B_ITEM_SEAM_QUIESCENCE_FAILED")
			return false
	var quiesce_done_us := Time.get_ticks_usec()
	var authority: Dictionary = _recovery_authority.export_recovery_state()
	var authority_done_us := Time.get_ticks_usec()
	var replay: Dictionary = _replay_outbox.to_dict()
	var replay_done_us := Time.get_ticks_usec()
	if authority.is_empty() or replay.is_empty():
		_enter_persistence_failure("P1B_ITEM_EMPTY_FROZEN_STATE")
		return false
	var capture_done_us := Time.get_ticks_usec()
	# Set the visibility barrier BEFORE submitting to the worker. The main
	# thread can still accept movement inputs, but cannot publish the
	# speculative ITEM/inventory state through any full/compact resync.
	_p1b_item_pending = {
		"kind": commit_kind,
		"operation_id": operation_id,
		"command_type": command_type,
		"logical_id": logical_id,
		"peer_id": peer_id,
		"session_id": session_id,
		"ownership_epoch": ownership_epoch,
		"before_item": before_item_snapshot.duplicate(true),
		"after_item_frozen": frozen_after_item if _r3c2_phased_item_publication_enabled else {},
		"after_item_checksum": item_checksum if _r3c2_phased_item_publication_enabled else "",
		"result": result.duplicate(true),
		"started_us": capture_start_us,
	}
	var submitted: Dictionary = _p1b_item_async_owner.submit_frozen(
		operation_id, result, authority, replay
	)
	if not bool(submitted.get("success", false)):
		_last_persistence_error_details = submitted.duplicate(true)
		_enter_persistence_failure(
			String(submitted.get("error_code", "P1B_ITEM_ASYNC_SUBMIT_FAILED"))
		)
		return false
	_p1b_item_last_capture_ms = float(capture_done_us - capture_start_us) / 1000.0
	_p1b_item_capture_stages = {
		"player_checksum_ms": float(player_done_us - capture_start_us) / 1000.0,
		"item_checksum_ms": float(item_done_us - player_done_us) / 1000.0,
		"outbox_stage_ms": float(outbox_done_us - item_done_us) / 1000.0,
		"quiesce_ms": float(quiesce_done_us - outbox_done_us) / 1000.0,
		"authority_export_ms": float(authority_done_us - quiesce_done_us) / 1000.0,
		"replay_export_ms": float(replay_done_us - authority_done_us) / 1000.0,
		"worker_handoff_ms": float(Time.get_ticks_usec() - capture_done_us) / 1000.0,
	}
	if SmoothTrace.enabled():
		SmoothTrace.emit("p1b_item_capture_breakdown", _p1b_item_capture_stages)
		SmoothTrace.emit("p1b_item_async_stages", {
			"stage": "SUBMIT",
			"kind": commit_kind,
			"operation_hash": operation_id.sha256_text().left(16),
			"generation": int(submitted.get("details", {}).get("generation", -1)),
			"capture_ms": _p1b_item_last_capture_ms,
			"submit_ms": float(Time.get_ticks_usec() - capture_done_us) / 1000.0,
		})
	return true


func _p1b_poll_item_async_commit() -> void:
	# The writer is already committed; M6 is waiting for staged publication.
	# Polling PHASE_ACK_READY as if it were COMMIT_PENDING is a fatal bug.
	if not _r3c2_postcommit_pending.is_empty():
		return
	if _p1b_item_pending.is_empty() or _p1b_item_async_owner == null:
		return
	var committed: Dictionary = _p1b_item_async_owner.poll_command_completion()
	if not bool(committed.get("success", false)):
		_last_persistence_error_details = committed.duplicate(true)
		_enter_persistence_failure(
			String(committed.get("error_code", "P1B_ITEM_ATOMIC_COMMIT_FAILED"))
		)
		return
	if bool(committed.get("details", {}).get("pending", false)):
		return
	if not bool(committed.get("details", {}).get("committed", false)):
		_enter_persistence_failure("P1B_ITEM_COMPLETION_NOT_DURABLE")
		return
	_p1b_finish_item_committed(committed, true)


func _p1b_finish_item_shutdown_barrier() -> void:
	# A completed generation awaiting staged publication is already durable.
	# Shutdown has no live transport ACK: quarantine the held session and
	# leave the result in canonical M6 replay for a fresh client after restart.
	if not _r3c2_postcommit_pending.is_empty():
		var pending: Dictionary = Dictionary(_r3c2_postcommit_pending.get("pending", {}))
		var discarded: Dictionary = _p1b_item_async_owner.discard_stale_session(
			String(pending.get("peer_id", "")), String(pending.get("session_id", ""))
		)
		if not bool(discarded.get("success", false)):
			_enter_persistence_failure("R3C2_POSTCOMMIT_SHUTDOWN_QUARANTINE_FAILED")
			return
		_r3c2_postcommit_pending.clear()
		_p1b_item_pending.clear()
		_p1b_committed_view.clear()
		_p1b_item_resync_waiters.clear()
		return
	# This is the ONLY intentional blocking wait: explicit stop/shutdown.
	if _p1b_item_pending.is_empty():
		return
	if _movement_checkpoint_writer == null or _p1b_item_async_owner == null:
		_enter_persistence_failure("P1B_ITEM_SHUTDOWN_WRITER_MISSING")
		return
	var completed: Dictionary = _movement_checkpoint_writer.wait_completed()
	if completed.is_empty():
		_enter_persistence_failure("P1B_ITEM_SHUTDOWN_COMPLETION_MISSING")
		return
	var accepted: Dictionary = _p1b_item_async_owner.accept_command_completion(completed)
	if not bool(accepted.get("success", false)):
		_last_persistence_error_details = accepted.duplicate(true)
		_enter_persistence_failure(
			String(accepted.get("error_code", "P1B_ITEM_SHUTDOWN_COMMIT_FAILED"))
		)
		return
	_p1b_finish_item_committed(accepted, false)


func _p1b_finish_item_committed(accepted: Dictionary, publish: bool) -> void:
	if _p1b_item_pending.is_empty() or not bool(accepted.get("details", {}).get("committed", false)):
		_enter_persistence_failure("P1B_ITEM_COMMITTED_RESULT_REQUIRED")
		return
	# R3C2 frozen_before/after ITEM DTOs were detached at capture. Copy only
	# the immutable envelope here: duplicate(true) of both full graphs on
	# durable-completion reintroduced a 100ms+ main-thread stall. Leave the
	# previous deep-copy behavior intact for every non-opt-in command.
	var is_phased_item := (
		_r3c2_phased_item_publication_enabled
		and String(_p1b_item_pending.get("kind", "ITEM")) == "ITEM"
	)
	var pending: Dictionary = (
		_p1b_item_pending.duplicate(false)
		if is_phased_item else _p1b_item_pending.duplicate(true)
	)
	var generation := int(accepted.get("details", {}).get("generation", -1))
	if (
		generation != _checkpoint_generation + 1
		or generation != int(_durable_ack_gate.get_report().get("generation", -2))
	):
		_enter_persistence_failure("P1B_ITEM_COMMITTED_GENERATION_MISMATCH")
		return
	_checkpoint_generation = generation
	_last_checkpoint_operation_id = String(pending.get("operation_id", ""))
	_durable_commits += 1
	match String(pending.get("kind", "ITEM")):
		"DISCONNECT":
			_r3b_async_disconnect_commits += 1
		"LEAVE":
			_r3c_async_leave_commits += 1
		_:
			_p1b_item_commits += 1
	_p1b_item_last_worker_ms = float(accepted.get("details", {}).get("worker_ms", 0.0))
	_p1b_item_last_build_ms = float(accepted.get("details", {}).get("build_ms", 0.0))
	_p1b_item_last_write_ms = float(accepted.get("details", {}).get("write_ms", 0.0))
	if _telemetry != null:
		_telemetry.observe("persistence_duration_ms", _p1b_item_last_worker_ms)
		_telemetry.observe("persistence_capture_ms", _p1b_item_last_capture_ms)
		_telemetry.increment("persistence_commits")
	_p1b_item_last_ack_wait_ms = float(
		Time.get_ticks_usec() - int(pending.get("started_us", Time.get_ticks_usec()))
	) / 1000.0
	# Later movement mutations happened AFTER frozen capture; keep their
	# dirty marker for a subsequent periodic checkpoint. R3C.2 ITEM keeps
	# the old wire visibility fence and M6 ACK head until all presentation
	# stages have completed on separate process turns.
	var staged_item_publication := (
		publish
		and _r3c2_phased_item_publication_enabled
		and String(pending.get("kind", "ITEM")) == "ITEM"
	)
	if not staged_item_publication:
		_p1b_item_pending.clear()
		_p1b_committed_view.clear()
	if SmoothTrace.enabled():
		SmoothTrace.emit("p1b_item_async_stages", {
			"stage": "DURABLE_COMMIT",
			"kind": String(pending.get("kind", "ITEM")),
			"operation_hash": String(pending.get("operation_id", "")).sha256_text().left(16),
			"generation": generation,
			"ack_wait_ms": _p1b_item_last_ack_wait_ms,
			"worker_build_ms": _p1b_item_last_build_ms,
			"worker_write_ms": _p1b_item_last_write_ms,
			"held_snapshot_count": _p1b_item_precommit_snapshot_holds,
		})
	if staged_item_publication:
		if not _r3c2_postcommit_pending.is_empty():
			_enter_persistence_failure("R3C2_POSTCOMMIT_SINGLE_INFLIGHT_REQUIRED")
			return
		_r3c2_postcommit_pending = {
			"stage": 0, "pending": pending, "after_item": {},
			"delta": {}, "fallback": false,
			"committed_at_ms": Time.get_ticks_msec(),
			"test_hold_reported": false,
		}
		return
	if not publish:
		# Graceful shutdown never lies about delivery to the vanished peer.
		_p1b_item_async_owner.discard_stale_session(
			String(pending.get("peer_id", "")), String(pending.get("session_id", ""))
		)
		_p1b_item_resync_waiters.clear()
		return
	match String(pending.get("kind", "ITEM")):
		"DISCONNECT":
			_r3b_publish_committed_disconnect(pending)
		"LEAVE":
			_r3c_publish_committed_leave(pending)
		_:
			_p1b_publish_committed_item(pending)


# R3C LEAVE becomes visible only after this exact M6 generation committed.
# A failed/stale reliable transport never receives an early or fabricated ACK.
func _r3c_publish_committed_leave(pending: Dictionary) -> void:
	var operation_id := String(pending.get("operation_id", ""))
	var peer_id := String(pending.get("peer_id", ""))
	var session_id := String(pending.get("session_id", ""))
	var logical_id := String(pending.get("logical_id", ""))
	var epoch := int(pending.get("ownership_epoch", 0))
	var result: Dictionary = Dictionary(pending.get("result", {}))
	var mapped_to_original := String(_peer_to_session.get(peer_id, "")) == session_id
	var publication: Dictionary = _p1b_item_async_owner.peek_publication(
		peer_id, session_id, logical_id, epoch
	)
	var eligible := (
		bool(publication.get("success", false))
		and mapped_to_original
		and _is_peer_compatible(peer_id, session_id)
	)
	var delivered := false
	if eligible:
		delivered = _send(peer_id, "LEAVE_ACK", {
			"operation_id": operation_id, "logical_player_id": logical_id,
		})
		var marked: Dictionary = _p1b_item_async_owner.mark_enqueued(
			operation_id, peer_id, session_id, logical_id, epoch, delivered
		)
		if not bool(marked.get("success", false)):
			_enter_persistence_failure("R3C_LEAVE_ACK_ESCROW_FAILED")
			return
	else:
		var discarded: Dictionary = _p1b_item_async_owner.discard_stale_session(peer_id, session_id)
		if not bool(discarded.get("success", false)):
			_enter_persistence_failure("R3C_LEAVE_ACK_QUARANTINE_FAILED")
			return
	if bool(result.get("success", false)) and not _is_replay_result(result):
		_leaves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	if mapped_to_original:
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		_peer_input_buffers.erase(peer_id)
		_seam_sent_state_by_peer.erase(peer_id)
	_broadcast_snapshot("PLAYER_LEFT")
	if delivered:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


# No old-session ACK is ever published. The generic M6 proof accepted the
# exact writer completion/generation above; now finalize only this DISCONNECT
# on the original transport-session fence. All other legacy handlers remain
# synchronous until separately verified (do not overclaim their latency).
func _r3b_publish_committed_disconnect(pending: Dictionary) -> void:
	var operation_id := String(pending.get("operation_id", ""))
	var peer_id := String(pending.get("peer_id", ""))
	var session_id := String(pending.get("session_id", ""))
	var result: Dictionary = Dictionary(pending.get("result", {}))
	var stale: Dictionary = _p1b_item_async_owner.discard_stale_session(peer_id, session_id)
	if not bool(stale.get("success", false)):
		_enter_persistence_failure("R3B_DISCONNECT_ACK_QUARANTINE_FAILED")
		return
	if bool(result.get("success", false)) and not _is_replay_result(result):
		_leaves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	else:
		_rejections += 1
	# A reconnected replacement session may share the peer id; never evict it.
	if String(_peer_to_session.get(peer_id, "")) == session_id:
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		_seam_sent_state_by_peer.erase(peer_id)
	_mark_operation_delivered(operation_id)
	_broadcast_snapshot("PEER_DISCONNECTED")
	_p1b_flush_item_resync_waiters()
	if has_method("_p1b_flush_resource_resync_waiters"):
		call("_p1b_flush_resource_resync_waiters")
	_write_report("READY", false)


# R3C.2: immutable postcommit work broken into ordered frame steps. While
# the M6 ACK remains pending, no other canonical mutation is admitted. The
# ordinary synchronous path remains untouched unless explicitly opted in.
func _r3c2_drain_postcommit_stage() -> void:
	if _r3c2_postcommit_pending.is_empty() or _fatal_persistence_failure:
		return
	var started := Time.get_ticks_usec()
	var stage := int(_r3c2_postcommit_pending.get("stage", -1))
	var pending: Dictionary = Dictionary(_r3c2_postcommit_pending.get("pending", {}))
	var operation_id := String(pending.get("operation_id", ""))
	var peer_id := String(pending.get("peer_id", ""))
	var session_id := String(pending.get("session_id", ""))
	var player_id := String(pending.get("logical_id", ""))
	var ownership_epoch := int(pending.get("ownership_epoch", 0))
	# R3C2 exact-process falsifier: a main-loop-NONBLOCKING window after
	# verified atomic worker completion, strictly before any M6 ACK enqueue.
	# Both environment gates are REQUIRED; ordinary gameplay is unchanged.
	if (
		stage == 2
		and _r3c2_phased_item_publication_enabled
		and OS.get_environment("DWS_NET_SMOOTH_TEST_HOOKS") == "1"
	):
		var forced_kill_window := (
			OS.get_environment("DWS_NET_R3C2_TEST_FORCE_PRE_ACK_HOLD") == "1"
		)
		var requested_hold_ms := clampi(
			int(OS.get_environment("DWS_NET_R3C2_TEST_PRE_ACK_HOLD_MS")), 0, 10000
		)
		var elapsed_ms := Time.get_ticks_msec() - int(
			_r3c2_postcommit_pending.get("committed_at_ms", Time.get_ticks_msec())
		)
		# Exact process-crash proof uses a test-only hold that never expires
		# by wall clock; otherwise a heavily loaded runner might send an ACK
		# before the harness kills server1, falsely passing the kill window.
		if forced_kill_window or (requested_hold_ms > 0 and elapsed_ms < requested_hold_ms):
			if not bool(_r3c2_postcommit_pending.get("test_hold_reported", false)):
				_r3c2_postcommit_pending["test_hold_reported"] = true
				if SmoothTrace.enabled():
					SmoothTrace.emit("r3c2_pre_ack_hold", {
						"operation_hash": operation_id.sha256_text().left(16),
						"generation": _checkpoint_generation,
						"hold_budget_ms": requested_hold_ms,
						"forced_until_kill": forced_kill_window,
					})
			return
	match stage:
		0:
			# Immutable exact-checksum DTO captured before submission: ITEM
			# cannot mutate while M6 owns this generation. No second graph
			# export after the worker completes.
			var after_item: Dictionary = Dictionary(
				pending.get("after_item_frozen", {})
			)
			if (
				after_item.is_empty()
				or String(after_item.get("checksum", "")).is_empty()
				or String(after_item.get("checksum", "")) !=
					String(pending.get("after_item_checksum", ""))
			):
				_enter_persistence_failure("R3C2_FROZEN_ITEM_CHECKSUM_MISMATCH")
				return
			_r3c2_postcommit_pending["after_item"] = after_item
			_r3c2_postcommit_pending["stage"] = 1
		1:
			var before_item: Dictionary = Dictionary(pending.get("before_item", {}))
			var after_item: Dictionary = Dictionary(_r3c2_postcommit_pending.get("after_item", {}))
			var delta_result: Dictionary = CanonicalItemGraphDelta.create(before_item, after_item)
			if not bool(delta_result.get("success", false)):
				_item_graph_delta_build_failures += 1
				_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
				_r3c2_postcommit_pending["fallback"] = true
			else:
				_r3c2_postcommit_pending["delta"] = Dictionary(
					delta_result.get("details", {}).get("delta", {})
				).duplicate(true)
			_r3c2_postcommit_pending.erase("after_item")
			_r3c2_postcommit_pending["stage"] = 2
		2:
			var result: Dictionary = Dictionary(pending.get("result", {}))
			var delta: Dictionary = Dictionary(_r3c2_postcommit_pending.get("delta", {}))
			var ready: Dictionary = _p1b_item_async_owner.peek_publication(
				peer_id, session_id, player_id, ownership_epoch
			)
			var delivered := false
			if bool(ready.get("success", false)):
				if String(_peer_to_session.get(peer_id, "")) == session_id:
					delivered = _send_result(
						peer_id, operation_id, String(pending.get("command_type", "")),
						result, delta
					)
				var enqueued: Dictionary = _p1b_item_async_owner.mark_enqueued(
					operation_id, peer_id, session_id, player_id, ownership_epoch, delivered
				)
				if not bool(enqueued.get("success", false)):
					_enter_persistence_failure("R3C2_POSTCOMMIT_ACK_FIFO_FAILED")
					return
				if delivered:
					_mark_operation_delivered(operation_id)
			else:
				var stale: Dictionary = _p1b_item_async_owner.discard_stale_session(
					peer_id, session_id
				)
				if not bool(stale.get("success", false)):
					_enter_persistence_failure("R3C2_POSTCOMMIT_ACK_QUARANTINE_FAILED")
					return
			_r3c2_postcommit_pending["stage"] = 3
		3:
			# Item is durable and its original ACK has been resolved. Clear the
			# visibility fence for replication; the independent R3C2 admission
			# lock still prevents a new canonical command before phase 4.
			_p1b_item_pending.clear()
			_p1b_committed_view.clear()
			if bool(_r3c2_postcommit_pending.get("fallback", false)):
				_broadcast_item_snapshot("R3C2_ITEM_DELTA_FALLBACK")
			else:
				_broadcast_item_delta(
					Dictionary(_r3c2_postcommit_pending.get("delta", {})),
					peer_id, String(pending.get("command_type", ""))
				)
			_r3c2_postcommit_pending["stage"] = 4
		4:
			_broadcast_snapshot(
				"ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED"
			)
			_capture_two_connected_checksum()
			_p1b_flush_item_resync_waiters()
			if has_method("_p1b_flush_resource_resync_waiters"):
				call("_p1b_flush_resource_resync_waiters")
			# _write_report() builds a FULL gameplay+M6 recovery export and
			# writes it synchronously. It is diagnostic, not the durability
			# checkpoint/ACK receipt. During opt-in real-time R3C2, defer
			# this unbounded report until explicit stop or other quiet gate.
			# The true durable result and every stage remain in bounded trace.
			_r3c2_deferred_diagnostic_reports += 1
			_r3c2_postcommit_pending.clear()
		_:
			_enter_persistence_failure("R3C2_POSTCOMMIT_INVALID_STAGE")
			return
	_r3c2_postcommit_last_stage_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_r3c2_postcommit_phases_completed += 1
	if SmoothTrace.enabled():
		SmoothTrace.emit("r3c2_postcommit_stage", {
			"stage": stage, "generation": _checkpoint_generation,
			"operation_hash": operation_id.sha256_text().left(16),
			"duration_ms": _r3c2_postcommit_last_stage_ms,
			"phases_completed": _r3c2_postcommit_phases_completed,
		})


func _p1b_publish_committed_item(pending: Dictionary) -> void:
	var operation_id := String(pending.get("operation_id", ""))
	var peer_id := String(pending.get("peer_id", ""))
	var session_id := String(pending.get("session_id", ""))
	var player_id := String(pending.get("logical_id", ""))
	var ownership_epoch := int(pending.get("ownership_epoch", 0))
	var command_type := String(pending.get("command_type", ""))
	var result: Dictionary = Dictionary(pending.get("result", {})).duplicate(true)
	var before_item: Dictionary = Dictionary(pending.get("before_item", {}))
	var after_item: Dictionary = _service.create_canonical_item_graph_snapshot()
	var delta_result: Dictionary = CanonicalItemGraphDelta.create(before_item, after_item)
	var item_delta: Dictionary = {}
	var delta_failed := not bool(delta_result.get("success", false))
	if delta_failed:
		_item_graph_delta_build_failures += 1
		_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
	else:
		item_delta = Dictionary(delta_result.get("details", {}).get("delta", {})).duplicate(true)
	# FIFO ACK is exposed ONLY after the exact repository commit, and never
	# to an old transport session or a replacement ownership epoch.
	var ready: Dictionary = _p1b_item_async_owner.peek_publication(
		peer_id, session_id, player_id, ownership_epoch
	)
	var delivered := false
	if bool(ready.get("success", false)):
		if String(_peer_to_session.get(peer_id, "")) == session_id:
			delivered = _send_result(peer_id, operation_id, command_type, result, item_delta)
		var enqueued: Dictionary = _p1b_item_async_owner.mark_enqueued(
			operation_id, peer_id, session_id, player_id, ownership_epoch, delivered
		)
		if not bool(enqueued.get("success", false)):
			_enter_persistence_failure("P1B_ITEM_ACK_ENQUEUE_FENCE_FAILED")
			return
		if delivered:
			_mark_operation_delivered(operation_id)
	else:
		# The command completed after disconnect; leave its canonical
		# replay-outbox record durable, with no false delivery marker.
		_p1b_item_async_owner.discard_stale_session(peer_id, session_id)
	if delta_failed:
		_broadcast_item_snapshot("P1B_ITEM_DELTA_FALLBACK")
	else:
		_broadcast_item_delta(item_delta, peer_id, command_type)
	_broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
	_capture_two_connected_checksum()
	_p1b_flush_item_resync_waiters()
	if has_method("_p1b_flush_resource_resync_waiters"):
		call("_p1b_flush_resource_resync_waiters")
	_write_report("READY", false)


func _p1b_flush_item_resync_waiters() -> void:
	if _p1b_item_resync_waiters.is_empty():
		return
	# Snapshot is created only AFTER the ITEM generation was committed.
	var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var waiters: Dictionary = _p1b_item_resync_waiters.duplicate(true)
	_p1b_item_resync_waiters.clear()
	for peer_id_value in waiters.keys():
		var peer_id := String(peer_id_value)
		var request: Dictionary = Dictionary(waiters[peer_id])
		if String(_peer_to_session.get(peer_id, "")) != String(request.get("session_id", "")):
			continue
		if _send_on_channel(
			peer_id, "ITEM_GRAPH_SNAPSHOT",
			{
				"reason": "P1B_AFTER_DURABLE_RESYNC",
				"operation_id": String(request.get("operation_id", "")),
				"snapshot": snapshot,
			}, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED"
		):
			_item_graph_full_snapshots_published += 1


func _handle_construction_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	if _construction_bridge == null:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("M3_CONSTRUCTION_NOT_ENABLED"))
		return
	var command_value = payload.get("command", {})
	if not command_value is Dictionary:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("CONSTRUCTION_COMMAND_REQUIRED"))
		return
	# Construction gateway mutates a separate owner. Its submit() is not an
	# M6 checkpoint; never promise durable ACK on the back of the M6 escrow.
	# Persistence-enabled construction must expose an independently verified
	# durable gateway contract before an acceptance result can be published.
	if not _gate_can_accept():
		_reject_uncommitted_command(peer_id, operation_id, "CONSTRUCTION_COMMAND", _gate_reject_code())
		return
	if not _construction_durability_allowed():
		_reject_uncommitted_command(peer_id, operation_id, "CONSTRUCTION_COMMAND", "M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED")
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var submitted: Dictionary = _construction_bridge.submit_player_command(logical_id, Dictionary(command_value))
	_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", submitted)
	if not bool(submitted.get("success", false)):
		_rejections += 1
		return
	var event_packet: Dictionary = Dictionary(submitted.get("details", {}).get("event_packet", {}))
	if event_packet.is_empty():
		_last_error_code = "M3_CONSTRUCTION_EVENT_MISSING"
		return
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(String(peer_id_value), "CONSTRUCTION_EVENT", event_packet, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED"):
			_construction_events_published += 1
	_write_report("READY", false)

func _broadcast_item_delta(delta: Dictionary, excluded_peer_id: String, reason: String) -> void:
	if not _p1b_item_pending.is_empty():
		return
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(peer_id, "ITEM_GRAPH_DELTA", {"reason": reason, "delta": delta}, RealtimeChannelPolicy.ITEM, "RELIABLE_ORDERED"):
			_broadcasts += 1
			_item_graph_deltas_published += 1

func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(_peer_to_player.get(peer_id, payload.get("logical_player_id", "")))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_leave(
			peer_id, operation_id,
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if _r3c_defer_admission("LEAVE", peer_id, session_id, logical_id, operation_id, payload):
		return
	if not _gate_can_accept():
		_reject_uncommitted_leave(peer_id, operation_id, _gate_reject_code())
		return
	var leave_epoch := _stored_ownership_epoch(logical_id, 0)
	var reserved_async := false
	var before_gameplay_snapshot: Dictionary = {}
	if _r3c_async_admission_enabled and _persistence_enabled and not _service.has_durable_replay_operation(operation_id):
		if String(_peer_to_session.get(peer_id, "")) != session_id or leave_epoch < 1:
			_reject_uncommitted_leave(peer_id, operation_id, "STALE_TRANSPORT_SESSION")
			return
		var reserved: Dictionary = _p1b_item_async_owner.reserve_mutation(
			operation_id, peer_id, session_id, logical_id, leave_epoch, "LEAVE"
		)
		if not bool(reserved.get("success", false)):
			_reject_uncommitted_leave(
				peer_id, operation_id, String(reserved.get("error_code", "R3C_LEAVE_RESERVATION_FAILED"))
			)
			return
		reserved_async = true
		before_gameplay_snapshot = _service.create_snapshot()
		if not bool(FullSnapshot.validate(before_gameplay_snapshot).get("success", false)):
			_enter_persistence_failure("R3C_LEAVE_PREVIEW_INVALID")
			return
	var result: Dictionary = _service.leave(logical_id, session_id, operation_id)
	if reserved_async:
		if bool(result.get("success", false)) and not _is_replay_result(result):
			if not _p1b_begin_item_async_commit(
				operation_id, "LEAVE", logical_id, result,
				peer_id, session_id, leave_epoch, {},
				before_gameplay_snapshot, "LEAVE"
			):
				# A successful canonical mutation without the M6 durable
				# generation must freeze the runtime, never issue LEAVE_ACK.
				return
			return
		var released: Dictionary = _p1b_item_async_owner.release_noncommitting_reservation(
			operation_id, result
		)
		if not bool(released.get("success", false)):
			_enter_persistence_failure("R3C_LEAVE_RESERVATION_RELEASE_FAILED")
			return
	if not _persist_command_result(operation_id, "LEAVE", logical_id, result, peer_id, session_id, leave_epoch):
		_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	if not _gate_preflight_success_result(operation_id, peer_id, session_id, logical_id, leave_epoch, result):
		return
	var leave_sent := false
	if bool(result.get("success", false)):
		leave_sent = _send(peer_id, "LEAVE_ACK", {"operation_id": operation_id, "logical_player_id": logical_id})
		_gate_after_result_enqueue(operation_id, peer_id, session_id, logical_id, leave_epoch, result, leave_sent)
		if _fatal_persistence_failure:
			return
		if not _is_replay_result(result):
			_leaves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		_seam_sent_state_by_peer.erase(peer_id)
		if not _is_replay_result(result):
			_broadcast_snapshot("PLAYER_LEFT")
	else:
		_rejections += 1
		leave_sent = _send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "LEAVE_REJECTED"))})
	if leave_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_disconnect(peer_id: String, session_id: String) -> void:
	_r3c_discard_session_admissions(peer_id, session_id)
	# A queued JOIN has not entered _peer_to_player yet, but its handshake
	# must still be forgotten so a stale transport can never drain later.
	if String(Dictionary(_peer_compatibility.get(peer_id, {})).get("session_id", "")) == session_id:
		_peer_compatibility.erase(peer_id)
	# Transport cleanup is immediate; authoritative LEAVE is serialized behind
	# any in-flight checkpoint. Never invalidate a newer session on stale events.
	var mapped_session := String(_peer_to_session.get(peer_id, ""))
	if _p1b_item_async_owner != null and not session_id.is_empty():
		_p1b_item_async_owner.discard_stale_session(peer_id, session_id)
	if _durable_ack_gate != null and not session_id.is_empty():
		_durable_ack_gate.discard_stale_session(peer_id, session_id)
	if session_id.is_empty() or mapped_session != session_id:
		_debug_event("STALE_PEER_DISCONNECT_IGNORED", {"peer_id": peer_id, "session_id": session_id})
		return
	_peer_input_buffers.erase(peer_id)
	_peer_compatibility.erase(peer_id)
	_debug_event("PEER_DISCONNECTED", {"peer_id": peer_id, "session_id": session_id})
	if not _gate_can_accept():
		_queue_deferred_disconnect(peer_id, session_id)
		return
	_commit_disconnect(peer_id, session_id)


func _queue_deferred_disconnect(peer_id: String, session_id: String) -> void:
	for pending in _deferred_disconnects:
		if String(pending.get("peer_id", "")) == peer_id and String(pending.get("session_id", "")) == session_id:
			return
	if _deferred_disconnects.size() >= MAX_DEFERRED_DISCONNECTS:
		_enter_persistence_failure("M6_DEFERRED_DISCONNECT_CAPACITY_EXCEEDED")
		return
	_deferred_disconnects.append({"peer_id": peer_id, "session_id": session_id})


func _drain_deferred_disconnects() -> void:
	if _deferred_disconnects.is_empty() or not _gate_can_accept():
		return
	# One terminal leave per frame bounds catch-up work and allows a new
	# reliable ACK/checkpoint fence to settle before the next disconnect.
	var pending: Dictionary = _deferred_disconnects.pop_front()
	_commit_disconnect(String(pending.get("peer_id", "")), String(pending.get("session_id", "")))


func _commit_disconnect(peer_id: String, session_id: String) -> void:
	# A reused peer id must never allow an old disconnect to evict its new session.
	if _service == null or String(_peer_to_session.get(peer_id, "")) != session_id or session_id.is_empty():
		return
	if not _gate_can_accept():
		_queue_deferred_disconnect(peer_id, session_id)
		return
	var operation_id := "operation/m3/disconnect/%s" % session_id.sha256_text().left(16)
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var disconnect_epoch := _stored_ownership_epoch(logical_id, 0)
	var r3b_reserved := false
	var before_gameplay_snapshot: Dictionary = {}
	if _p1b_item_async_enabled and not _service.has_durable_replay_operation(operation_id):
		# The old sync path waited for the periodic writer, stalling the
		# server for ~960ms. Defer before mutation; never wait in _process().
		if _movement_checkpoint_writer == null or _movement_checkpoint_writer.is_busy():
			_queue_deferred_disconnect(peer_id, session_id)
			return
		var reserved: Dictionary = _p1b_item_async_owner.reserve_mutation(
			operation_id, peer_id, session_id, logical_id, disconnect_epoch, "DISCONNECT"
		)
		if not bool(reserved.get("success", false)):
			if String(reserved.get("error_code", "")) in ["P1A_WAIT_PRIOR_PERIODIC", "P1A_GATE_BACKPRESSURE", "P1A_MUTATION_FENCED"]:
				_queue_deferred_disconnect(peer_id, session_id)
				return
			_enter_persistence_failure("R3B_DISCONNECT_RESERVATION_FAILED")
			return
		r3b_reserved = true
		before_gameplay_snapshot = _service.create_snapshot()
		if not bool(FullSnapshot.validate(before_gameplay_snapshot).get("success", false)):
			_enter_persistence_failure("R3B_DISCONNECT_PREVIEW_INVALID")
			return
	var result: Dictionary = _service.leave_transport_session(session_id, operation_id)
	if r3b_reserved:
		if bool(result.get("success", false)) and not _is_replay_result(result):
			if not _p1b_begin_item_async_commit(
				operation_id, "DISCONNECT", logical_id, result,
				peer_id, session_id, disconnect_epoch, {},
				before_gameplay_snapshot, "DISCONNECT"
			):
				# A successful mutation without its durable generation is FATAL.
				return
			return
		var released: Dictionary = _p1b_item_async_owner.release_noncommitting_reservation(
			operation_id, result
		)
		if not bool(released.get("success", false)):
			_enter_persistence_failure("R3B_DISCONNECT_RESERVATION_RELEASE_FAILED")
			return
	if not _persist_command_result(operation_id, "DISCONNECT", logical_id, result, peer_id, session_id, disconnect_epoch):
		return
	# Disconnects never send an old-session ACK. Canonical M6 replay retains
	# any committed outcome and the escrow entry is quarantined.
	if _durable_ack_gate != null:
		_durable_ack_gate.discard_stale_session(peer_id, session_id)
	if bool(result.get("success", false)) and not _is_replay_result(result):
		_leaves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	else:
		_rejections += 1
	_mark_operation_delivered(operation_id)
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_seam_sent_state_by_peer.erase(peer_id)
	_broadcast_snapshot("PEER_DISCONNECTED")
	_write_report("READY", false)


func _reject_uncommitted_command(peer_id: String, operation_id: String, command_type: String, error_code: String) -> void:
	_rejections += 1
	_send_result(peer_id, operation_id, command_type, _failure(error_code))
	_write_report("READY", false)


func _reject_uncommitted_leave(peer_id: String, operation_id: String, error_code: String) -> void:
	_rejections += 1
	_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": error_code})
	_write_report("READY", false)


func _send_result(peer_id: String, operation_id: String, command_type: String, result: Dictionary, item_graph_delta: Dictionary = {}) -> bool:
	var wire: Dictionary = _service.create_targeted_command_result("message/m3/result/%s" % operation_id.sha256_text().left(12), operation_id, result)
	var payload := {
		"operation_id": operation_id,
		"command_type": command_type,
		"status": String(wire.get("status", "REJECTED")),
		"error_code": String(wire.get("error_code", "")),
		"details": wire.get("payload", {}),
		"checksum": String(wire.get("checksum", "")),
	}
	if not item_graph_delta.is_empty():
		payload["item_graph_delta"] = item_graph_delta.duplicate(true)
		_item_graph_deltas_published += 1
	var channel: String = RealtimeChannelPolicy.ITEM if _is_item_command_type(command_type) else RealtimeChannelPolicy.CONTROL
	return _send_on_channel(peer_id, "COMMAND_RESULT", payload, channel, "RELIABLE_ORDERED")

func _broadcast_delta(delta: Dictionary, excluded_peer_id: String = "") -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		if peer_id == excluded_peer_id:
			continue
		if _send_on_channel(peer_id, "GAMEPLAY_DELTA", {"delta": delta}, RealtimeChannelPolicy.SNAPSHOT, "UNRELIABLE_SEQUENCED"):
			_broadcasts += 1


func _broadcast_snapshot(
	reason: String,
	channel: String = RealtimeChannelPolicy.RESYNC,
	delivery_mode: String = "RELIABLE_ORDERED"
) -> void:
	if not _p1b_item_pending.is_empty():
		_p1b_item_precommit_snapshot_holds += 1
		return
	var snapshot: Dictionary = _service.create_snapshot()
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(String(peer_id_value), "GAMEPLAY_SNAPSHOT", {"reason": reason, "snapshot": snapshot}, channel, delivery_mode):
			_broadcasts += 1


func _send(peer_id: String, message_type: String, data: Dictionary) -> bool:
	return _send_on_channel(peer_id, message_type, data, RealtimeChannelPolicy.CONTROL, "RELIABLE_ORDERED")


func _send_on_channel(
	peer_id: String,
	message_type: String,
	data: Dictionary,
	channel: String,
	delivery_mode: String
) -> bool:
	if _boundary == null or peer_id.is_empty():
		return false
	if not _ensure_peer_ready(peer_id):
		return false
	# P2.2 diagnostic: only COMPACT snapshot emission, not all messages.
	# No native frame format or per-peer send/flush ordering is changed.
	var p22_wire_probe := (
		_r31p22_loop_attribution_enabled
		and SmoothTrace.enabled()
		and message_type == "COMPACT_GAMEPLAY_SNAPSHOT"
	)
	var p22_wire_started_us: int = Time.get_ticks_usec() if p22_wire_probe else 0
	# The broadcaster owns a fresh compact snapshot and never mutates it.
	# FrameScript.create() JSON-roundtrips into a detached per-peer payload;
	# the envelope alone needs copying in this specific realtime path.
	var payload: Dictionary = (
		data.duplicate(false) if message_type == "COMPACT_GAMEPLAY_SNAPSHOT"
		else data.duplicate(true)
	)
	payload["type"] = message_type
	payload["server_sent_at_ms"] = Time.get_ticks_msec()
	var p22_clone_done_us: int = Time.get_ticks_usec() if p22_wire_probe else 0
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id, channel, Support.MESSAGE_SCHEMA, payload, delivery_mode
	)
	var p22_frame_done_us: int = Time.get_ticks_usec() if p22_wire_probe else 0
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED"))
		if p22_wire_probe:
			SmoothTrace.emit("r31p22_compact_wire_failed", {
				"engine_frame": Engine.get_process_frames(), "phase": "FRAME_CREATE"})
		return false
	var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
	var p22_send_done_us: int = Time.get_ticks_usec() if p22_wire_probe else 0
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED"))
		if p22_wire_probe:
			SmoothTrace.emit("r31p22_compact_wire_failed", {
				"engine_frame": Engine.get_process_frames(), "phase": "SEND"})
		return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	var p22_flush_done_us: int = Time.get_ticks_usec() if p22_wire_probe else 0
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "FLUSH_FAILED"))
		if p22_wire_probe:
			SmoothTrace.emit("r31p22_compact_wire_failed", {
				"engine_frame": Engine.get_process_frames(), "phase": "FLUSH"})
		return false
	_messages_sent += 1
	if p22_wire_probe:
		SmoothTrace.emit("r31p22_compact_wire_stages", {
			"engine_frame": Engine.get_process_frames(),
			"server_tick": _server_tick,
			"payload_clone_ms": float(p22_clone_done_us - p22_wire_started_us) / 1000.0,
			"frame_create_ms": float(p22_frame_done_us - p22_clone_done_us) / 1000.0,
			"boundary_send_ms": float(p22_send_done_us - p22_frame_done_us) / 1000.0,
			"outbound_flush_ms": float(p22_flush_done_us - p22_send_done_us) / 1000.0,
			"total_ms": float(p22_flush_done_us - p22_wire_started_us) / 1000.0,
		})
	return true


func _is_item_command_type(command_type: String) -> bool:
	return (
		command_type == "ITEM_COMMAND"
		or command_type.begins_with("item.")
		or command_type.begins_with("inventory.")
		or command_type.begins_with("container.")
		or command_type.begins_with("mount.")
	)


func _send_control(peer_id: String, message_type: String, data: Dictionary) -> bool:
	if _boundary == null or peer_id.is_empty():
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	payload["server_sent_at_ms"] = Time.get_ticks_msec()
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id, RealtimeChannelPolicy.CONTROL, Support.MESSAGE_SCHEMA, payload, "RELIABLE_ORDERED"
	)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "CONTROL_FRAME_CREATE_FAILED"))
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		peer_id, frame_result.get("details", {}).get("frame", {})
	)
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "CONTROL_SEND_FAILED"))
		return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "CONTROL_FLUSH_FAILED"))
		return false
	_messages_sent += 1
	return true


func _ensure_peer_ready(peer_id: String) -> bool:
	if String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY": return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(result.get("success", false)) and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION": return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"

func _capture_two_connected_checksum() -> void:
	if _peer_to_player.size() == 2 and _service != null:
		_last_two_connected_checksum = String(_service.create_snapshot().get("checksum", ""))

func _setup_r31bp1_durable_chunk_cache() -> Dictionary:
	# R31b P1: the cache exists only for the product seam service; the plain
	# service has no seam export and must never run with the flag ON.
	if _service == null or not _service.has_method("configure_r31bp1_durable_chunk_cache"):
		return _failure("R31BP1_REQUIRES_PRODUCT_SEAM_SERVICE")
	var cache := R31Bp1DurableChunkCache.new()
	var configured: Dictionary = cache.configure(true)
	if not bool(configured.get("success", false)):
		return configured
	var attached: Dictionary = _service.configure_r31bp1_durable_chunk_cache(cache)
	if not bool(attached.get("success", false)):
		return attached
	_r31bp1_chunk_cache = cache
	return _success({"enabled": true})


func _setup_recovery() -> Dictionary:
	_recovery_repository = RecoveryRepository.new()
	var repository_result: Dictionary = _recovery_repository.configure(_persistence_root)
	if not bool(repository_result.get("success", false)):
		return _failure("M6_RECOVERY_REPOSITORY_SETUP_FAILED", {"cause": repository_result})
	_recovery_authority = M6AuthorityAdapter.new()
	var authority_result: Dictionary = _recovery_authority.setup(
		_service,
		"session/m6/%s" % _authority_owner_id.sha256_text().left(16)
	)
	if not bool(authority_result.get("success", false)):
		return authority_result
	_replay_outbox = M6ReplayOutbox.new()
	var replay_result: Dictionary = _replay_outbox.setup(_service)
	if not bool(replay_result.get("success", false)):
		return replay_result
	_recovery_coordinator = RecoveryCoordinator.new()
	var coordinator_result: Dictionary = _recovery_coordinator.configure(
		_recovery_repository, _recovery_authority, _replay_outbox
	)
	if not bool(coordinator_result.get("success", false)):
		return coordinator_result
	var loaded: Dictionary = _recovery_repository.load_committed()
	if bool(loaded.get("success", false)):
		var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
		var authority_validation: Dictionary = _recovery_authority.validate_recovery_state(
			Dictionary(checkpoint.get("authority_state", {}))
		)
		if not bool(authority_validation.get("success", false)):
			return _failure("M6_DEDICATED_AUTHORITY_PREVALIDATION_FAILED", {"cause": authority_validation})
		var replay_validation: Dictionary = _replay_outbox.validate(
			Dictionary(checkpoint.get("replay_state", {}))
		)
		if not bool(replay_validation.get("success", false)):
			return _failure("M6_DEDICATED_REPLAY_PREVALIDATION_FAILED", {"cause": replay_validation})
		var recovered: Dictionary = _recovery_coordinator.recover_latest()
		if not bool(recovered.get("success", false)):
			return _failure("M6_DEDICATED_RECOVERY_FAILED", {"cause": recovered})
		checkpoint = recovered.get("details", {}).get("checkpoint", {})
		_checkpoint_generation = int(checkpoint.get("generation", 0))
		_last_checkpoint_operation_id = String(checkpoint.get("committed_operation_id", ""))
		_recovered = true
		_recovery_source = String(recovered.get("details", {}).get("source", ""))
		var gate_ready: Dictionary = _ensure_durable_ack_gate()
		if not bool(gate_ready.get("success", false)):
			return gate_ready
		return _success({"recovered": true, "generation": _checkpoint_generation, "source": _recovery_source})
	var load_error := String(loaded.get("error_code", ""))
	if load_error != "AUTHORITATIVE_CHECKPOINT_NOT_FOUND":
		return _failure("M6_DEDICATED_RECOVERY_LOAD_FAILED", {"cause": loaded})
	var seeded := _persist_checkpoint("", "BOOTSTRAP_SEED")
	if not bool(seeded.get("success", false)):
		return seeded
	var gate_ready_fresh: Dictionary = _ensure_durable_ack_gate()
	if not bool(gate_ready_fresh.get("success", false)):
		return gate_ready_fresh
	return _success({"recovered": false, "generation": _checkpoint_generation, "source": "NEW"})


func _ensure_durable_ack_gate() -> Dictionary:
	# R4.1-P1: the ACK gate starts at the durable generation that is actually on
	# disk after recovery or fresh seed. Restart creates a fresh instance; replay
	# idempotency for retried operation ids stays M6-owned.
	_durable_ack_gate = M6PendingDurableAckGate.new()
	var gate_config: Dictionary = _durable_ack_gate.configure(_checkpoint_generation)
	if not bool(gate_config.get("success", false)):
		return _failure("M6_DURABLE_ACK_GATE_CONFIG_FAILED", {"cause": gate_config})
	return _success({})


func _persist_command_result(
	operation_id: String,
	command_type: String,
	logical_player_id: String,
	result: Dictionary,
	peer_id: String = "",
	session_id: String = "",
	ownership_epoch: int = 0
) -> bool:
	if not _persistence_enabled:
		return true
	if not _is_canonical_operation_id(operation_id):
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_COMMITTED_OPERATION_ID_INVALID")
			return false
		return true
	if _is_replay_result(result) or String(result.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT":
		# M6 canonical replay is the single outcome for a retried operation id;
		# it never re-enters the ACK escrow and never re-applies a mutation.
		return true
	var replay_recorded := bool(_service.has_durable_replay_operation(operation_id))
	if not replay_recorded:
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_SUCCESS_RESULT_NOT_REPLAY_DURABLE")
			return false
		return true
	var legacy_started_us := Time.get_ticks_usec()
	var prior_writer_drained := false
	if bool(result.get("success", false)):
		# R4.1-P1: drain the async movement writer BEFORE escrow. The staged
		# generation must equal the actual next free generation; completing an
		# in-flight periodic checkpoint after staging would steal that slot.
		var legacy_wait_started_us := Time.get_ticks_usec()
		_complete_async_movement_checkpoint(true)
		_legacy_last_writer_wait_ms = float(Time.get_ticks_usec() - legacy_wait_started_us) / 1000.0
		prior_writer_drained = true
		if SmoothTrace.enabled():
			SmoothTrace.emit("legacy_command_prior_writer_wait", {
				"command_type": command_type,
				"wait_ms": _legacy_last_writer_wait_ms,
				"writer_available": _movement_checkpoint_writer != null,
			})
		if _fatal_persistence_failure:
			return false
		# R4.1-P1: escrow the successful result before any persistence. While a
		# record is COMMIT_PENDING the gate refuses further mutations, so no
		# conflicting canonical mutation can run before the checkpoint lands.
		var staged_gate: Dictionary = _durable_ack_gate.stage(
			operation_id, peer_id, session_id, logical_player_id,
			ownership_epoch, command_type, result, _checkpoint_generation + 1
		)
		if not bool(staged_gate.get("success", false)):
			_enter_persistence_failure(String(staged_gate.get("error_code", "M6_DURABLE_ACK_GATE_STAGE_FAILED")))
			return false
		var submitted_gate: Dictionary = _durable_ack_gate.mark_submitted(
			operation_id, _checkpoint_generation + 1
		)
		if not bool(submitted_gate.get("success", false)):
			_enter_persistence_failure(String(submitted_gate.get("error_code", "M6_DURABLE_ACK_GATE_SUBMIT_FAILED")))
			return false
	# R4.0: sample independent, bounded stages before changing any ACK contract.
	# Canonical snapshots and the outbox are unchanged; these measurements run
	# only for the durable command path, never for NX3 realtime inputs.
	var checksum_started_us: int = Time.get_ticks_usec()
	var player_checksum: String = String(_service.create_snapshot().get("checksum", ""))
	var item_graph_started_us: int = Time.get_ticks_usec()
	var item_graph_checksum: String = String(_service.create_canonical_item_graph_snapshot().get("checksum", ""))
	var outbox_started_us: int = Time.get_ticks_usec()
	var staged: Dictionary = _replay_outbox.stage_committed(operation_id, command_type, {
		"logical_player_id": logical_player_id,
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
		"result": result.duplicate(true),
		"player_snapshot_checksum": player_checksum,
		"item_graph_checksum": item_graph_checksum,
	})
	var outbox_done_us: int = Time.get_ticks_usec()
	if not bool(staged.get("success", false)):
		if SmoothTrace.enabled():
			SmoothTrace.emit("durable_command_stages", {
				"command_type": command_type,
				"player_checksum_ms": float(item_graph_started_us - checksum_started_us) / 1000.0,
				"item_graph_checksum_ms": float(outbox_started_us - item_graph_started_us) / 1000.0,
				"outbox_stage_ms": float(outbox_done_us - outbox_started_us) / 1000.0,
				"checkpoint_total_ms": 0.0, "success": false,
				"failure_stage": "OUTBOX_STAGE",
			})
		_enter_persistence_failure(String(staged.get("error_code", "M6_OUTBOX_STAGE_FAILED")))
		return false
	var checkpoint_started_us: int = Time.get_ticks_usec()
	var persisted: Dictionary = _persist_checkpoint(
		operation_id, "LEGACY_COMMAND_SYNC", prior_writer_drained
	)
	if SmoothTrace.enabled():
		SmoothTrace.emit("durable_command_stages", {
			"command_type": command_type,
			"player_checksum_ms": float(item_graph_started_us - checksum_started_us) / 1000.0,
			"item_graph_checksum_ms": float(outbox_started_us - item_graph_started_us) / 1000.0,
			"outbox_stage_ms": float(outbox_done_us - outbox_started_us) / 1000.0,
			"checkpoint_total_ms": float(Time.get_ticks_usec() - checkpoint_started_us) / 1000.0,
			"success": bool(persisted.get("success", false)),
			"failure_stage": "" if bool(persisted.get("success", false)) else "CHECKPOINT",
		})
	_legacy_sync_commit_count += 1
	_legacy_last_main_thread_ms = float(Time.get_ticks_usec() - legacy_started_us) / 1000.0
	if SmoothTrace.enabled():
		SmoothTrace.emit("legacy_command_main_thread", {
			"command_type": command_type, "operation_hash": operation_id.sha256_text().left(16),
			"total_ms": _legacy_last_main_thread_ms,
			"prior_writer_wait_ms": _legacy_last_writer_wait_ms,
			"success": bool(persisted.get("success", false)),
		})
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M6_DURABLE_COMMIT_FAILED")))
		return false
	if bool(result.get("success", false)):
		# Durable-before-ACK is preserved: the escrow record becomes ACK_ELIGIBLE
		# only for the exact generation the repository actually committed.
		var committed_gate: Dictionary = _durable_ack_gate.complete(operation_id, _checkpoint_generation, {
			"success": true, "generation": _checkpoint_generation,
		})
		if not bool(committed_gate.get("success", false)):
			_enter_persistence_failure(String(committed_gate.get("error_code", "M6_DURABLE_ACK_GATE_COMMIT_FAILED")))
			return false
	_durable_commits += 1
	# The command checkpoint contains the latest movement state as well. Do not
	# emit a redundant movement-only checkpoint at the same gameplay revision.
	if _movement_checkpoint_dirty:
		_movement_checkpoint_dirty = false
		_movement_commands_since_checkpoint = 0
		_last_movement_checkpoint_ms = Time.get_ticks_msec()
	return true


func _persist_checkpoint(
	operation_id: String, origin_override: String = "", prior_writer_drained: bool = false
) -> Dictionary:
	if not _persistence_enabled or _recovery_coordinator == null:
		return _success({"skipped": true})
	# Commands retain the accepted durable-before-ACK contract. A newer sync
	# generation must never race an older periodic writer.
	var wait_started_us: int = Time.get_ticks_usec()
	if not prior_writer_drained:
		_complete_async_movement_checkpoint(true)
	var waited_us: int = Time.get_ticks_usec() - wait_started_us
	var origin: String = (
		origin_override if not origin_override.is_empty()
		else "COMMAND" if not operation_id.is_empty() else "PERIODIC_UNCLASSIFIED"
	)
	if _fatal_persistence_failure:
		if SmoothTrace.enabled():
			SmoothTrace.emit("durable_checkpoint_stages", {
				"origin": origin, "wait_async_ms": float(waited_us) / 1000.0,
				"quiesce_ms": 0.0, "persist_atomic_ms": 0.0,
				"success": false, "failure_stage": "WAIT_ASYNC",
			})
		return _failure(_last_error_code)
	var quiesce_started_us: int = Time.get_ticks_usec()
	if _service != null and _service.has_method("prepare_product_persistence"):
		var quiesced: Dictionary = _service.prepare_product_persistence()
		if not bool(quiesced.get("success", false)):
			if SmoothTrace.enabled():
				SmoothTrace.emit("durable_checkpoint_stages", {
					"origin": origin, "wait_async_ms": float(waited_us) / 1000.0,
					"quiesce_ms": float(Time.get_ticks_usec() - quiesce_started_us) / 1000.0,
					"persist_atomic_ms": 0.0,
					"success": false, "failure_stage": "QUIESCE",
				})
			return _failure("USER1_SEAM_PERSISTENCE_NOT_QUIESCENT", {
				"cause": quiesced,
			})
	var quiesce_done_us: int = Time.get_ticks_usec()
	var persistence_started_us: int = Time.get_ticks_usec()
	var next_generation := _checkpoint_generation + 1
	var checkpoint_id := "checkpoint/m6/dedicated/%d" % next_generation
	var persisted: Dictionary = _recovery_coordinator.persist_checkpoint(
		checkpoint_id,
		next_generation,
		_checkpoint_generation,
		operation_id
	)
	var persistence_done_us: int = Time.get_ticks_usec()
	if SmoothTrace.enabled():
		SmoothTrace.emit("durable_checkpoint_stages", {
			"origin": origin, "wait_async_ms": float(waited_us) / 1000.0,
			"quiesce_ms": float(quiesce_done_us - quiesce_started_us) / 1000.0,
			"persist_atomic_ms": float(persistence_done_us - persistence_started_us) / 1000.0,
			"success": bool(persisted.get("success", false)),
			"failure_stage": "" if bool(persisted.get("success", false)) else "PERSIST_ATOMIC",
		})
	if not bool(persisted.get("success", false)):
		_last_persistence_error_details = persisted.duplicate(true)
		_debug_event("CHECKPOINT_PERSIST_REJECTED", {
			"operation_id":operation_id,
			"next_generation":next_generation,
			"cause":persisted,
		})
		return _failure("M6_CHECKPOINT_PERSIST_FAILED", {"cause": persisted})
	_checkpoint_generation = next_generation
	_last_checkpoint_operation_id = operation_id
	# R4.1-P1: every durable generation advance must be observed by the ACK
	# gate. The escrowed command path completes its own record after this
	# (pending=true), so it is excluded here; failure-result command checkpoints
	# and periodic checkpoints are observed as ordinary generation advances.
	if _durable_ack_gate != null:
		var gate_report: Dictionary = _durable_ack_gate.get_report()
		if not bool(gate_report.get("pending", false)) and _checkpoint_generation == int(gate_report.get("generation", 0)) + 1:
			var observed: Dictionary = _durable_ack_gate.observe_periodic_commit(_checkpoint_generation)
			if not bool(observed.get("success", false)):
				_enter_persistence_failure(String(observed.get("error_code", "M6_DURABLE_ACK_GATE_OBSERVE_FAILED")))
				return _failure(_last_error_code)
	_telemetry.observe("persistence_duration_ms", float(Time.get_ticks_usec() - persistence_started_us) / 1000.0)
	_telemetry.increment("persistence_commits")
	return _success({"generation": _checkpoint_generation, "checkpoint_id": checkpoint_id})


func _mark_operation_delivered(operation_id: String) -> void:
	if not _persistence_enabled or _replay_outbox == null or operation_id.is_empty():
		return
	var records: Array = _replay_outbox.get_records()
	for index in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index]
		if String(record.get("operation_id", "")) == operation_id:
			_replay_outbox.mark_delivered(int(record.get("sequence", 0)))
			return


func _is_replay_result(result: Dictionary) -> bool:
	return bool(result.get("replay", false)) or bool(result.get("details", {}).get("replay", false))


func _is_canonical_operation_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["/", "_", ".", "-"]
		):
			return false
	return true


func _enter_persistence_failure(error_code: String) -> void:
	_persistence_failures += 1
	_last_error_code = error_code if not error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED"
	# R4.1-P1: any persistence failure freezes new mutations and new ACKs. No
	# success result can leave the server after a failed durable commit.
	if _durable_ack_gate != null:
		_durable_ack_gate.fail_closed(_last_error_code)
	_fatal_persistence_failure = true
	_debug_event("PERSISTENCE_FATAL", {
		"error_code":_last_error_code,
		"checkpoint_generation":_checkpoint_generation,
		"cause":_last_persistence_error_details,
	})
	set_process(false)
	_write_report("FAILED", false)
	if _boundary != null:
		_boundary.stop()


func _persistence_report() -> Dictionary:
	var report: Dictionary = {
		"enabled": _persistence_enabled,
		"root_path": _persistence_root,
		"checkpoint_generation": _checkpoint_generation,
		"recovered": _recovered,
		"recovery_source": _recovery_source,
		"last_checkpoint_operation_id": _last_checkpoint_operation_id,
		"durable_commits": _durable_commits,
		"failures": _persistence_failures,
		"legacy_sync_command_count": _legacy_sync_commit_count,
		"legacy_sync_last_main_thread_ms": _legacy_last_main_thread_ms,
		"legacy_sync_last_writer_wait_ms": _legacy_last_writer_wait_ms,
		"fatal_failure": _fatal_persistence_failure,
		"last_error_details": _last_persistence_error_details.duplicate(true),
		"outbox": _replay_outbox.get_report() if _replay_outbox != null else {},
		"durable_ack_gate": _durable_ack_gate.get_report() if _durable_ack_gate != null else {},
		"item_async_canary_enabled": _p1b_item_async_enabled,
		"item_async_pending": not _p1b_item_pending.is_empty(),
		"item_async_commits": _p1b_item_commits,
		"r3b_async_disconnect_commits": _r3b_async_disconnect_commits,
		"r3c_async_admission_enabled": _r3c_async_admission_enabled,
		"r3c4_periodic_frame_pacing_enabled": _r3c4_periodic_frame_pacing_enabled,
		"r3c4r2_worker_envelope_enabled": _r3c4r2_worker_envelope_enabled,
		"r3c4r31_replay_projection_enabled": _r3c4r31_replay_projection_enabled,
		"r3c4r31b_durable_attribution_enabled": _r3c4r31b_durable_attribution_enabled,
		"r3c4_deferred_frames": _r3c4_deferred_frames,
		"r3c4_capture_slots": _r3c4_capture_slots,
		"r3c4_forced_captures": _r3c4_forced_captures,
		"r3c2_phased_item_publication_enabled": _r3c2_phased_item_publication_enabled,
		"r3c2_postcommit_stage": int(_r3c2_postcommit_pending.get("stage", -1)),
		"r3c2_postcommit_phases_completed": _r3c2_postcommit_phases_completed,
		"r3c2_postcommit_last_stage_ms": _r3c2_postcommit_last_stage_ms,
		"r3c2_deferred_diagnostic_reports": _r3c2_deferred_diagnostic_reports,
		"r3c_async_leave_commits": _r3c_async_leave_commits,
		"r3c_deferred_admissions": _r3c_deferred_admissions.size(),
		"r3c_queued_joins": _r3c_queued_joins,
		"r3c_queued_leaves": _r3c_queued_leaves,
		"r3c_admissions_drained": _r3c_admissions_drained,
		"r3c_admissions_dropped": _r3c_admissions_dropped,
		"item_async_snapshot_holds": _p1b_item_precommit_snapshot_holds,
		"item_async_item_graph_snapshot_holds": _p1b_item_graph_snapshot_holds,
		"item_committed_view_frames": _p1b_committed_frames,
		"item_committed_view_enqueues": _p1b_committed_enqueues,
		"item_committed_view_rejections": _p1b_committed_rejections,
		"item_async_capture_ms": _p1b_item_last_capture_ms,
		"item_async_worker_ms": _p1b_item_last_worker_ms,
		"item_async_build_ms": _p1b_item_last_build_ms,
		"item_async_write_ms": _p1b_item_last_write_ms,
		"item_async_capture_breakdown": _p1b_item_capture_stages.duplicate(true),
		"item_async_ack_wait_ms": _p1b_item_last_ack_wait_ms,
		"item_async_owner": (
			_p1b_item_async_owner.get_report()
			if _p1b_item_async_owner != null else {}
		),
		"service_recovery": _service.get_recovery_report() if _service != null else {},
	}
	# A READ-ONLY, opt-in recovery oracle for a real second server process.
	# Expose just a boolean, not replay IDs or an authoritative dictionary.
	# Never enabled by product configs, and never modifies M6 ACK/durability.
	if OS.get_environment("DWS_NET_SMOOTH_TEST_HOOKS") == "1":
		var operation_id := OS.get_environment("DWS_NET_R3C2_TEST_OPERATION_ID")
		if not operation_id.is_empty():
			report["r3c2_test_operation_recovered"] = (
				_service != null
				and _service.has_durable_replay_operation(operation_id)
			)
	return report


func _gate_can_accept() -> bool:
	if not _r3c2_postcommit_pending.is_empty():
		return false
	# Persistence-free runtimes (some M7 playable fixtures) have no durable
	# contract to fence; the gate only guards persistence-enabled servers.
	if not _persistence_enabled:
		return true
	if _durable_ack_gate == null or not _durable_ack_gate.can_accept_mutation():
		return false
	# Product ACK publication is serial even if the proof kernel has multiple
	# ready slots. No new mutation may overtake an untransmitted durable reply.
	return int(_durable_ack_gate.get_report().get("ready_count", 0)) == 0


func _construction_durability_allowed() -> bool:
	# The existing Construction gateway has export/load helpers but submit()
	# does not synchronously persist a durable transaction or join the M6
	# authoritative checkpoint. Reject rather than claim a false durable ACK.
	return not _persistence_enabled


func _gate_reject_code() -> String:
	if _durable_ack_gate == null:
		return "M6_DURABLE_GATE_UNAVAILABLE"
	var report: Dictionary = _durable_ack_gate.get_report()
	return String(report.get("error_code", "")) if bool(report.get("fatal", false)) else "DURABLE_GATE_BACKPRESSURE"


func _stored_ownership_epoch(logical_id: String, payload_epoch: int) -> int:
	if payload_epoch > 0:
		return payload_epoch
	return int(_player_ownership_epochs.get(logical_id, 0))


func _gate_is_ack_head(
	operation_id: String, peer_id: String, session_id: String,
	logical_player_id: String, ownership_epoch: int
) -> bool:
	if _durable_ack_gate == null or operation_id.is_empty():
		return false
	var head: Dictionary = _durable_ack_gate.peek_ack(peer_id, session_id, logical_player_id, ownership_epoch)
	return String(head.get("operation_id", "")) == operation_id


func _gate_preflight_success_result(
	operation_id: String, peer_id: String, session_id: String,
	logical_player_id: String, ownership_epoch: int, result: Dictionary
) -> bool:
	if not _persistence_enabled or _durable_ack_gate == null or not bool(result.get("success", false)):
		return true
	if _gate_is_ack_head(operation_id, peer_id, session_id, logical_player_id, ownership_epoch):
		return true
	var report: Dictionary = _durable_ack_gate.get_report()
	if _is_replay_result(result) and int(report.get("ready_count", 0)) == 0 and not bool(report.get("pending", false)):
		return true
	# The mutation is already durable; do not fabricate a rejection or send
	# out-of-order success. Fail-stop on a broken escrow invariant.
	_enter_persistence_failure("M6_DURABLE_ACK_FIFO_PRECHECK_FAILED")
	return false


func _gate_after_result_enqueue(
	operation_id: String, peer_id: String, session_id: String,
	logical_player_id: String, ownership_epoch: int,
	result: Dictionary, enqueued: bool
) -> bool:
	if not _persistence_enabled or _durable_ack_gate == null or not bool(result.get("success", false)):
		return enqueued
	var head: Dictionary = _durable_ack_gate.peek_ack(peer_id, session_id, logical_player_id, ownership_epoch)
	if String(head.get("operation_id", "")) != operation_id:
		# M6 can replay previously delivered outcomes from a fresh transport.
		return enqueued if _is_replay_result(result) and int(_durable_ack_gate.get_report().get("ready_count", 0)) == 0 else false
	if not enqueued:
		# A failed reliable enqueue is NOT a delivered ACK. Quarantine the
		# undeliverable session result; M6 replay resolves retries after reconnect.
		var quarantined: Dictionary = _durable_ack_gate.discard_stale_session(peer_id, session_id)
		if not bool(quarantined.get("success", false)):
			_enter_persistence_failure("M6_DURABLE_ACK_QUARANTINE_FAILED")
		return false
	var marked: Dictionary = _durable_ack_gate.mark_delivered(
		operation_id, peer_id, session_id, logical_player_id, ownership_epoch
	)
	if not bool(marked.get("success", false)):
		_enter_persistence_failure(String(marked.get("error_code", "M6_DURABLE_ACK_DELIVERY_FAILED")))
		return false
	return true


func _complete_async_movement_checkpoint(wait: bool) -> void:
	# Command and periodic checkpoints share one worker; only the proof
	# owner may consume an ITEM completion.
	if not _p1b_item_pending.is_empty():
		if wait:
			_p1b_finish_item_shutdown_barrier()
		return
	if _movement_checkpoint_writer == null:
		return
	var completed: Dictionary = (
		_movement_checkpoint_writer.wait_completed() if wait
		else _movement_checkpoint_writer.poll_completed()
	)
	if completed.is_empty():
		return
	if not bool(completed.get("success", false)):
		_last_persistence_error_details = completed
		_enter_persistence_failure(String(completed.get("error_code", "M7_ASYNC_CHECKPOINT_FAILED")))
		return
	var details: Dictionary = completed.get("details", {})
	var generation := int(details.get("generation", 0))
	if generation != _checkpoint_generation + 1:
		_enter_persistence_failure("M7_ASYNC_CHECKPOINT_GENERATION_MISMATCH")
		return
	_checkpoint_generation = generation
	_last_checkpoint_operation_id = ""
	# R4.1-P1: the async movement checkpoint is an ordinary periodic generation
	# advance for the ACK gate. While an escrowed command is COMMIT_PENDING the
	# command checkpoint picks the next free generation after this barrier and
	# its complete() covers the advance; observing now would break the strict
	# single-inflight contract for no benefit.
	if _durable_ack_gate != null:
		var gate_report: Dictionary = _durable_ack_gate.get_report()
		if not bool(gate_report.get("pending", false)):
			var observed: Dictionary = _durable_ack_gate.observe_periodic_commit(generation)
			if not bool(observed.get("success", false)):
				_enter_persistence_failure(String(observed.get("error_code", "M6_DURABLE_ACK_GATE_OBSERVE_FAILED")))
				return
	_movement_checkpoints += 1
	_async_checkpoint_last = details.duplicate(true)
	_async_checkpoint_last["capture_ms"] = _async_checkpoint_capture_ms
	_async_checkpoint_last["elapsed_ms"] = float(Time.get_ticks_usec() - _async_checkpoint_started_us) / 1000.0
	if SmoothTrace.enabled():
		SmoothTrace.emit("checkpoint_complete", _async_checkpoint_last)
	if _telemetry != null:
		_telemetry.observe("persistence_duration_ms", float(details.get("worker_ms", 0.0)))
		_telemetry.observe("persistence_capture_ms", _async_checkpoint_capture_ms)
		_telemetry.increment("persistence_commits")
	# Do NOT clear dirty/counters here: movement after submission is newer than
	# the detached checkpoint. The next request will capture that newer state.
	_debug_event("MOVEMENT_CHECKPOINT_COMMITTED", {"generation": generation, "async": true})
	# get_report() recursively builds a full game/ItemGraph/M6 snapshot and
	# writes JSON to the runtime result file. It is not the atomic checkpoint
	# nor the M6 proof; during R3C2 this main-thread diagnostics-only report
	# must not create a new >100ms stall right after worker completion.
	if _r3c2_phased_item_publication_enabled:
		_r3c2_deferred_diagnostic_reports += 1
		if SmoothTrace.enabled():
			SmoothTrace.emit("r3c2_periodic_report_deferred", {
				"generation": generation,
				"worker_ms": float(details.get("worker_ms", 0.0)),
				"capture_ms": _async_checkpoint_capture_ms,
			})
	else:
		_write_report("READY", false)


func _submit_async_movement_checkpoint() -> void:
	if _movement_checkpoint_writer.is_busy():
		return
	var started := Time.get_ticks_usec()
	if _service.has_method("prepare_product_persistence_quiescence_only"):
		var quiesced: Dictionary = _service.prepare_product_persistence_quiescence_only()
		if not bool(quiesced.get("success", false)):
			_last_persistence_error_details = quiesced
			_enter_persistence_failure("USER1_SEAM_PERSISTENCE_NOT_QUIESCENT")
			return
	elif _service.has_method("prepare_product_persistence"):
		var quiesced: Dictionary = _service.prepare_product_persistence()
		if not bool(quiesced.get("success", false)):
			_last_persistence_error_details = quiesced
			_enter_persistence_failure("USER1_SEAM_PERSISTENCE_NOT_QUIESCENT")
			return
	# Both exports are captured on the authoritative thread at one quiescent
	# boundary. Workers may only consume detached value data, never live owners.
	var after_quiesce := Time.get_ticks_usec()
	var authority: Dictionary = {}
	var frozen_gameplay: Dictionary = {}
	var r31b_durable_stages: Dictionary = {}
	if _r3c4r2_worker_envelope_enabled:
		# Exactly one immutable value projection from the quiescent server
		# state; the checksum-heavy EntitySnapshot envelope is made on worker.
		if _r3c4r31b_durable_attribution_enabled:
			var profiled_source: Dictionary = (
				_recovery_authority.capture_frozen_gameplay_source_r31b_profiled()
			)
			frozen_gameplay = Dictionary(profiled_source.get("frozen_gameplay", {}))
			r31b_durable_stages = Dictionary(profiled_source.get("stages", {}))
		else:
			frozen_gameplay = _recovery_authority.capture_frozen_gameplay_source_for_worker()
	else:
		authority = _recovery_authority.export_recovery_state()
	var after_authority := Time.get_ticks_usec()
	var replay: Dictionary = {}
	var replay_stage_metrics: Dictionary = {}
	var replay_projection_result: Dictionary = {}
	if _r3c4r31_replay_projection_enabled:
		replay_projection_result = _replay_outbox.to_dict_r31_versioned()
		replay = Dictionary(replay_projection_result.get("value", {}))
	elif _r3c4r30_stage_attribution_enabled:
		var profiled_replay: Dictionary = _replay_outbox.to_dict_profiled()
		replay = Dictionary(profiled_replay.get("value", {}))
		replay_stage_metrics = Dictionary(profiled_replay.get("metrics", {}))
	else:
		replay = _replay_outbox.to_dict()
	var after_replay := Time.get_ticks_usec()
	if replay.is_empty() or (
		frozen_gameplay.is_empty() if _r3c4r2_worker_envelope_enabled
		else authority.is_empty()
	):
		_enter_persistence_failure("M7_ASYNC_CHECKPOINT_CAPTURE_EMPTY")
		return
	var generation := _checkpoint_generation + 1
	var submitted: Dictionary = {}
	if _r3c4r2_worker_envelope_enabled:
		submitted = _movement_checkpoint_writer.submit_frozen_gameplay_source(
			frozen_gameplay, replay,
			"checkpoint/m6/dedicated/%d" % generation,
			generation, _checkpoint_generation,
			_r3c4r30_stage_attribution_enabled)
	else:
		submitted = _movement_checkpoint_writer.submit(
			authority, replay, "checkpoint/m6/dedicated/%d" % generation,
			generation, _checkpoint_generation)
	if not bool(submitted.get("success", false)):
		_last_persistence_error_details = submitted
		_enter_persistence_failure(String(submitted.get("error_code", "M7_ASYNC_CHECKPOINT_SUBMIT_FAILED")))
		return
	_async_checkpoint_started_us = started
	_async_checkpoint_capture_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if SmoothTrace.enabled():
		var gameplay: Dictionary = replay.get("gameplay_replay", {})
		var capture_event: Dictionary = {"generation": generation,
			"r3c4r2_worker_envelope": _r3c4r2_worker_envelope_enabled,
			"capture_ms": _async_checkpoint_capture_ms,
			"quiesce_ms": float(after_quiesce - started) / 1000.0,
			"authority_ms": float(after_authority - after_quiesce) / 1000.0,
			"replay_ms": float(after_replay - after_authority) / 1000.0,
			"handoff_ms": float(Time.get_ticks_usec() - after_replay) / 1000.0,
			"ledger_count": Dictionary(gameplay.get("service_operation_ledger", {})).size(),
			"outbox_count": Array(replay.get("committed_outbox", [])).size()}
		if _r3c4r31b_durable_attribution_enabled:
			capture_event["r31b_durable_stages"] = r31b_durable_stages.duplicate(true)
		if _r31bp20_validator_attribution_enabled:
			capture_event["r31bp20_validator_attribution"] = true
		if _r31bp1_durable_chunks_enabled and _service != null and _service.has_method("get_r31bp1_durable_chunk_report"):
			capture_event["r31bp1_durable_chunks"] = _service.get_r31bp1_durable_chunk_report()
		if _r3c4r31_replay_projection_enabled:
			capture_event["r31_cache_hit"] = bool(
				replay_projection_result.get("cache_hit", false))
			capture_event["r31_cache_bypassed"] = String(
				replay_projection_result.get("bypassed", ""))
			capture_event["r31_projection_generation"] = int(
				replay_projection_result.get("projection_generation", -1))
		if _r3c4r30_stage_attribution_enabled:
			# replay_ms is to_dict(), *not* writer duplicate(true). The copy
			# has its own measurement returned synchronously by submit().
			capture_event["r30_replay_gameplay_ms"] = float(
				replay_stage_metrics.get("gameplay_export_ms", -1.0))
			capture_event["r30_replay_checksum_ms"] = float(
				replay_stage_metrics.get("checksum_detach_ms", -1.0))
			capture_event["r30_writer_deep_copy_ms"] = float(
				Dictionary(submitted.get("details", {})).get("handoff_copy_ms", -1.0))
			capture_event["r30_replay_ledger_count"] = int(
				replay_stage_metrics.get("service_ledger_count", -1))
			capture_event["r30_outbox_count"] = int(
				replay_stage_metrics.get("committed_outbox_count", -1))
		SmoothTrace.emit("checkpoint_capture", capture_event)
	_movement_checkpoint_dirty = false
	_movement_commands_since_checkpoint = 0
	_last_movement_checkpoint_ms = Time.get_ticks_msec()


func _maybe_persist_movement_checkpoint() -> void:
	# A durable command still owns the exact M6 publication order. Do not
	# submit a periodic generation between its worker commit and final ACK /
	# resync, even though the shared writer is technically no longer busy.
	if not _r3c2_postcommit_pending.is_empty():
		return
	if (
		_service != null
		and _service.has_method("can_persist_product_state")
		and not bool(_service.can_persist_product_state())
	):
		return
	if (
		not _playable_sandbox
		or not _persistence_enabled
		or not _movement_checkpoint_dirty
		or _fatal_persistence_failure
		or Time.get_ticks_msec() - _last_movement_checkpoint_ms < M7_MOVEMENT_CHECKPOINT_INTERVAL_MS
	):
		return
	# R3C.4: a due periodic capture never runs on the same heavy frame that
	# just prepared a 20Hz movement snapshot, unless the bounded 64ms
	# deferral elapsed. This only delays dispatch; dirty data stays live and
	# the existing single-writer pipeline below is untouched.
	if not _r3c4_periodic_capture_slot_available():
		return
	if SmoothTrace.enabled():
		SmoothTrace.emit("periodic_checkpoint_dispatch", {
			"origin": "MOVEMENT_PERIODIC",
			"route": "ASYNC_WRITER" if _movement_checkpoint_writer != null else "SYNC_FALLBACK",
			"writer_busy": _movement_checkpoint_writer != null and _movement_checkpoint_writer.is_busy(),
			"generation": _checkpoint_generation,
			"item_pending": not _p1b_item_pending.is_empty(),
		})
	if _movement_checkpoint_writer != null:
		_submit_async_movement_checkpoint()
		return
	var persisted := _persist_checkpoint("", "PERIODIC_SYNC_FALLBACK")
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M7_MOVEMENT_CHECKPOINT_FAILED")))
		return
	_movement_checkpoint_dirty = false
	_movement_checkpoints += 1
	_movement_commands_since_checkpoint = 0
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_debug_event("MOVEMENT_CHECKPOINT_COMMITTED", {"generation":_checkpoint_generation})
	_write_report("READY", false)

func _r3c4_periodic_capture_slot_available() -> bool:
	if not _r3c4_periodic_frame_pacing_enabled:
		return true
	var now_ms := Time.get_ticks_msec()
	var snapshot_this_frame := _last_movement_snapshot_tick == _server_tick
	if not snapshot_this_frame:
		# Low-work frame: the original capture pipeline owns this frame.
		_r3c4_deferral_started_ms = 0
		_r3c4_capture_slots += 1
		if SmoothTrace.enabled():
			SmoothTrace.emit("r3c4_periodic_capture_slot", {
				"tick": _server_tick,
				"forced": false,
				"deferred_frames": _r3c4_deferred_frames,
				"precapture_work_ms": _r3c4_precapture_work_ms,
			})
		return true
	if _r3c4_deferral_started_ms <= 0:
		_r3c4_deferral_started_ms = now_ms
	_r3c4_deferred_frames += 1
	var deferral_ms := now_ms - _r3c4_deferral_started_ms
	if SmoothTrace.enabled():
		SmoothTrace.emit("r3c4_periodic_frame_deferred", {
			"tick": _server_tick,
			"deferral_ms": float(deferral_ms),
			"precapture_work_ms": _r3c4_precapture_work_ms,
		})
	if deferral_ms <= R3C4_MAX_DEFERRAL_MS:
		return false
	# Bounded starvation guard: force the capture on this eligible frame even
	# though it is still heavy. No alternate generation, no dirty clearing.
	_r3c4_forced_captures += 1
	_r3c4_deferral_started_ms = 0
	_r3c4_capture_slots += 1
	if SmoothTrace.enabled():
		SmoothTrace.emit("r3c4_periodic_capture_slot", {
			"tick": _server_tick,
			"forced": true,
			"deferred_frames": _r3c4_deferred_frames,
			"precapture_work_ms": _r3c4_precapture_work_ms,
		})
	return true


func _update_runtime_telemetry() -> void:
	if _telemetry == null:
		return
	_telemetry.set_gauge("connected_gameplay_peers", float(_peer_to_player.size()))
	_telemetry.set_gauge("compatible_transport_peers", float(_peer_compatibility.size()))
	_telemetry.set_gauge("handshake_replay_count", float(_handshake_replays))
	_telemetry.set_gauge("checkpoint_generation", float(_checkpoint_generation))
	_telemetry.set_gauge("fixed_server_tick", float(_server_tick))
	_telemetry.set_gauge("pending_input_count", float(_total_pending_input_count()))
	_telemetry.set_gauge("fixed_tick_failures", float(_fixed_tick_failures))
	var boundary_snapshot: Dictionary = _boundary.get_snapshot() if _boundary != null else {}
	var port_runtime: Dictionary = boundary_snapshot.get("port_runtime", {})
	var peer_statistics: Dictionary = port_runtime.get("peer_statistics", {})
	for stats_value in peer_statistics.values():
		if not stats_value is Dictionary:
			continue
		var stats: Dictionary = stats_value
		_telemetry.observe("peer_rtt_ms", float(stats.get("rtt_ms", 0)))
		_telemetry.observe("peer_jitter_ms", float(stats.get("rtt_variance_ms", 0)))
		_telemetry.observe("peer_packet_loss_percent", float(stats.get("packet_loss_percent", 0.0)))


func _total_pending_input_count() -> int:
	var total: int = 0
	for buffer_value in _peer_input_buffers.values():
		if buffer_value != null:
			total += int(buffer_value.get_pending_count())
	return total


func _telemetry_sample() -> Dictionary:
	if _telemetry == null:
		return {}
	var result: Dictionary = _telemetry.create_sample(Time.get_ticks_msec())
	return Dictionary(result.get("details", {}).get("sample", {})).duplicate(true) if bool(result.get("success", false)) else {}


func _stall_enter(stage: String, context: Dictionary = {}) -> int:
	if _live2_stall_watchdog == null:
		return 0
	return _live2_stall_watchdog.enter(stage, context)


func _stall_exit(token: int) -> void:
	if _live2_stall_watchdog == null or token < 1:
		return
	_live2_stall_watchdog.exit(token)


func _stall_context(
	peer_id: String,
	operation_id: String,
	command_type: String
) -> Dictionary:
	return {
		"peer_id": peer_id,
		"player_id": String(_peer_to_player.get(peer_id, "")),
		"operation_id": operation_id,
		"command_type": command_type,
		"server_tick": _server_tick,
		"messages_received": _messages_received,
		"messages_sent": _messages_sent,
		"moves": _moves,
		"rejections": _rejections,
	}


func _debug_event(event_name: String, details: Dictionary = {}) -> void:
	if not _debug_logging:
		return
	print("[m7_server] %s" % JSON.stringify({
		"event":event_name,"process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),
		"details":details,
	}, "", true, true))

func detach_playable_world() -> Dictionary:
	# M3/M7 dedicated runtime owns gameplay state directly and has no separate
	# presentation world attachment. Keep SimulatorApp lifecycle polymorphic.
	return _success({"detached": false, "reason": "DEDICATED_RUNTIME_OWNS_NO_PLAYABLE_WORLD"})


func get_world_entity_store_for_kernel():
	return null

func _cleanup_setup_failure() -> void:
	set_process(false)
	if _movement_checkpoint_writer != null:
		_movement_checkpoint_writer.stop()
		_movement_checkpoint_writer = null
	if _boundary != null:
		_boundary.stop()
	elif _network_condition_simulator != null:
		_network_condition_simulator.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_network_condition_simulator = null
	_service = null
	_p1b_item_async_owner = null
	_p1b_item_pending.clear()
	_p1b_item_resync_waiters.clear()


func _setup_network_condition_simulator(config: Dictionary) -> Dictionary:
	_network_condition_presets_file = String(
		config.get("network_condition_presets_file", ConditionProfileStore.DEFAULT_PRESETS_PATH)
	).strip_edges()
	var profile_id: String = String(config.get("network_condition_profile", "LOCAL")).strip_edges().to_upper()
	var loaded: Dictionary = ConditionProfileStore.load_profile(
		profile_id, _network_condition_presets_file
	)
	if not bool(loaded.get("success", false)):
		return loaded
	_network_condition_profile = Dictionary(loaded.get("details", {}).get("profile", {})).duplicate(true)
	_network_condition_simulator = ConditionSimulatorPort.new()
	return _network_condition_simulator.setup(
		Port.new(), _network_condition_profile, _telemetry
	)


func set_network_condition_profile(profile_id: String) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	var loaded: Dictionary = ConditionProfileStore.load_profile(
		profile_id.strip_edges().to_upper(), _network_condition_presets_file
	)
	if not bool(loaded.get("success", false)):
		return loaded
	_network_condition_profile = Dictionary(loaded.get("details", {}).get("profile", {})).duplicate(true)
	return _network_condition_simulator.set_profile(_network_condition_profile)


func trigger_network_lag_spike(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	return _network_condition_simulator.trigger_lag_spike(direction, duration_ms)


func trigger_network_disconnect_blackout(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	if _network_condition_simulator == null:
		return _failure("NETWORK_CONDITION_SIMULATOR_NOT_READY")
	return _network_condition_simulator.trigger_disconnect_blackout(direction, duration_ms)


func _input_buffer_reports() -> Dictionary:
	var reports: Dictionary = {}
	for peer_id_value in _peer_input_buffers.keys():
		var peer_id: String = String(peer_id_value)
		var buffer = _peer_input_buffers[peer_id]
		if buffer != null:
			reports[peer_id] = buffer.get_report(_server_tick)
	return reports


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
		"gameplay_checkpoint": (
			M7_CHECKPOINT if _playable_sandbox
			else M6_CHECKPOINT if _persistence_enabled
			else Support.CHECKPOINT
		),
		"gameplay_build_id": (
			M7_BUILD_ID if _playable_sandbox
			else M6_BUILD_ID if _persistence_enabled
			else Support.BUILD_ID
		),
		"configured": _configured,
		"host": _host,
		"port": _port,
		"connected_peer_count": _peer_to_player.size(),
		"peer_to_player": _peer_to_player.duplicate(true),
		"joins": _joins,
		"fast_join_acks": _fast_join_acks,
		"leaves": _leaves,
		"moves": _moves,
		"presentation_updates": _presentation_updates,
		"rejections": _rejections,
		"broadcasts": _broadcasts,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"seam_messages_sent": _seam_messages_sent,
		"seam_unchanged_skipped": _seam_unchanged_skipped,
		"last_error_code": _last_error_code,
		"last_two_connected_checksum": _last_two_connected_checksum,
		"snapshot": _service.create_snapshot() if _service != null else {},
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot() if _service != null else {},
		"service": _service.get_report() if _service != null else {},
		"boundary": _boundary.get_snapshot() if _boundary != null else {},
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"direct_client_authority_references": 0,
		"persistence": _persistence_report(),
		"playable_sandbox": _playable_sandbox,
		"network_fingerprint": _fingerprint.duplicate(true),
		"network_protocol_manifest": _protocol_manifest.duplicate(true),
		"compatibility_handshake": {
			"attempts": _handshake_attempts,
			"accepts": _handshake_accepts,
			"rejections": _handshake_rejections,
			"replays": _handshake_replays,
			"last_error_code": _last_handshake_error_code,
			"compatible_peers": _peer_compatibility.duplicate(true),
		},
		"network_conditions": (
			_network_condition_simulator.get_runtime_snapshot()
			if _network_condition_simulator != null else {}
		),
		"network_telemetry": _telemetry_sample(),
		"realtime_traffic": {
			"channel_policy": RealtimeChannelPolicy.canonical_policy(),
			"movement_snapshot_interval_ms": NX2_MOVEMENT_SNAPSHOT_INTERVAL_MS,
			"movement_snapshot_interval_ticks": NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
			"movement_snapshot_rate_hz": NX3_FIXED_TICK_RATE_HZ / NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
			"movement_batches_received": _movement_batches_received,
			"movement_inputs_received": _movement_inputs_received,
			"movement_inputs_applied": _movement_inputs_applied,
			"movement_inputs_redundant": _movement_inputs_redundant,
			"movement_inputs_rejected": _movement_inputs_rejected,
			"last_movement_rejection_error_code": _last_movement_rejection_error_code,
			"last_movement_rejection_stage": _last_movement_rejection_stage,
			"movement_results_suppressed": _movement_results_suppressed,
			"movement_deltas_suppressed": _movement_deltas_suppressed,
			"movement_full_snapshots_suppressed": _movement_full_snapshots_suppressed,
			"movement_snapshots_published": _movement_snapshots_published,
			"item_graph_deltas_published": _item_graph_deltas_published,
			"item_graph_delta_build_failures": _item_graph_delta_build_failures,
			"item_graph_full_snapshots_published": _item_graph_full_snapshots_published,
			"item_graph_resync_requests": _item_graph_resync_requests,
			"compact_movement_snapshots_published": _compact_movement_snapshots_published,
			"movement_snapshot_retransmit_requests": _movement_snapshot_retransmit_requests,
			"movement_snapshot_enqueue_failures": _movement_snapshot_enqueue_failures,
			"compact_movement_snapshot_failures": _compact_movement_snapshot_failures,
		},
		"fixed_tick_simulation": {
			"schema": FixedTickScheduler.SCHEMA,
			"tick_rate_hz": NX3_FIXED_TICK_RATE_HZ,
			"tick_delta_seconds": NX3_FIXED_TICK_DELTA_SECONDS,
			"server_tick": _server_tick,
			"ticks_simulated": _fixed_ticks_simulated,
			"catch_up_batches": _fixed_tick_catch_up_batches,
			"failures": _fixed_tick_failures,
			"last_tick_duration_ms": _last_fixed_tick_duration_ms,
			"pending_input_count": _total_pending_input_count(),
			"stale_input_drops": _input_queue_stale_drops,
			"input_hold_expirations": _input_hold_expirations,
			"scheduler": _fixed_tick_scheduler.get_report() if _fixed_tick_scheduler != null else {},
			"input_buffers": _input_buffer_reports(),
		},
		"live2_server_stall_watchdog": (
			_live2_stall_watchdog.get_report()
			if _live2_stall_watchdog != null else {}
		),
		"movement_persistence": {
			"mode": "ASYNC_PERIODIC_WORLD_CHECKPOINT" if _movement_checkpoint_writer != null else "THROTTLED_WORLD_CHECKPOINT",
			"writer_busy": _movement_checkpoint_writer.is_busy() if _movement_checkpoint_writer != null else false,
			"last_async_checkpoint": _async_checkpoint_last.duplicate(true),
			"command_durability": "SYNCHRONOUS_BARRIER_PRESERVED",
			"interval_ms":M7_MOVEMENT_CHECKPOINT_INTERVAL_MS,
			"dirty":_movement_checkpoint_dirty,
			"checkpoint_count":_movement_checkpoints,
			"commands_since_checkpoint":_movement_commands_since_checkpoint,
		},
	}

func stop() -> Dictionary:
	set_process(false)
	_complete_async_movement_checkpoint(true)
	if _movement_checkpoint_writer != null:
		_movement_checkpoint_writer.stop()
		_movement_checkpoint_writer = null
	if _live2_stall_watchdog != null:
		_live2_stall_watchdog.stop()
		_live2_stall_watchdog = null
	if _persistence_enabled and not _fatal_persistence_failure and _service != null and _recovery_coordinator != null:
		var persisted: Dictionary = _persist_checkpoint("", "SHUTDOWN_FINAL")
		if not bool(persisted.get("success", false)):
			_enter_persistence_failure(String(persisted.get("error_code", "M6_FINAL_CHECKPOINT_FAILED")))
	if _fatal_persistence_failure:
		_write_report("FAILED", false)
	else:
		_write_report("STOPPED", true)
	if _boundary != null:
		_boundary.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_network_condition_simulator = null
	_service = null
	_p1b_item_async_owner = null
	_p1b_item_pending.clear()
	_p1b_committed_view.clear()
	_p1b_item_resync_waiters.clear()
	_r3c2_postcommit_pending.clear()
	_r3c4_deferral_started_ms = 0
	_r3c_deferred_admissions.clear()
	_fixed_tick_scheduler = null
	_peer_input_buffers.clear()
	_seam_sent_state_by_peer.clear()
	_configured = false
	if _fatal_persistence_failure:
		return _failure(_last_error_code if not _last_error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED")
	return _success()

func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
