extends SceneTree

const HealthyServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd")
const P4HardenedServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd")
const FaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_fault.gd")
const RecoveryServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_resume.gd")
const RecoveryFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_fault.gd")
const ActiveRecoveryServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd")
const ActiveRecoveryFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery_fault.gd")
const TransactionRecoveryServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd")
const TransactionFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_fault.gd")
const TransactionMixedFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_fault_mixed.gd")
const RecoveryChainFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd")
const RecoveryPerformanceServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd")
const RecoveryPerformanceV2ServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance_v2.gd")
const NetworkDelayServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_network_delay.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const H2_2_RECOVERY_FAULT_PROFILE := "h2-target-crash-after-commit-persist-v1"
const H2_3_RECOVERY_FAULT_PROFILE := "h2-source-crash-after-retire-persist-v1"
const H2_4_ACTIVE_RECOVERY_FAULT_PROFILE := "h2-active-owner-crash-after-move-persist-v1"
const H3_3_TRANSACTION_FAULT_PROFILE := "h3-inflight-dual-outage-after-source-retire-v1"
const H3_4_TRANSACTION_FAULT_PROFILE := "h3-commit-decision-dual-outage-v1"
const H3_5_TRANSACTION_FAULT_PROFILE := "h3-activation-dual-outage-before-ack-v1"
const H4_1_TRANSACTION_FAULT_PROFILE := "h4-repeated-activation-dual-outage-v1"
const H4_2_TRANSACTION_FAULT_PROFILE := "h4-mixed-boundary-dual-outage-v1"
const H4_3_RECOVERY_CHAIN_FAULT_PROFILE := "h4-recovery-of-recovery-same-transfer-v1"
const P2_1_RECOVERY_PERFORMANCE_PROFILE := "p21"
const P2_2_RECOVERY_PERFORMANCE_PROFILE := "p22"
const P3_1_NETWORK_PROFILE := "p31-controlled-latency-v1"


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", ""))
	var zone_id := String(options.get("zone-id", ""))
	if authority_id.is_empty():
		authority_id = Contracts.AUTHORITY_A
	if zone_id.is_empty():
		zone_id = Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B
	var fault_profile := String(options.get("fault-profile", OS.get_environment("SM0_FAULT_PROFILE"))).strip_edges()
	var recovery_dir := String(options.get("recovery-dir", "")).strip_edges()
	var recovery_performance := String(options.get("recovery-performance", "")).strip_edges().to_lower()
	var active_recovery_text := String(options.get("active-owner-recovery", "0")).strip_edges().to_lower()
	var active_owner_recovery := active_recovery_text in ["1", "true", "yes"]
	var transaction_recovery_text := String(options.get("transaction-recovery", "0")).strip_edges().to_lower()
	var transaction_recovery := transaction_recovery_text in ["1", "true", "yes"]
	var network_profile := String(options.get("network-profile", "")).strip_edges().to_lower()
	var p4_fast := OS.get_environment("SM0_P4_FAST_HANDOFF").strip_edges().to_lower() in ["1", "true", "yes", "on"]
	if not network_profile.is_empty() and network_profile != P3_1_NETWORK_PROFILE:
		push_error("Unsupported SM0 network profile: %s" % network_profile)
		quit(2)
		return
	if (
		not network_profile.is_empty()
		and (
			not fault_profile.is_empty()
			or not recovery_dir.is_empty()
			or not recovery_performance.is_empty()
			or active_owner_recovery
			or transaction_recovery
		)
	):
		push_error("SM0 P3.1 network shaping cannot be combined with fault/recovery profiles.")
		quit(2)
		return
	print("[SM0_BOOT] authority=%s zone=%s gameplay_port=%s control_port=%s peer_control_port=%s fault_profile=%s recovery_dir=%s recovery_performance=%s active_owner_recovery=%s transaction_recovery=%s network_profile=%s p4_fast=%s" % [
		authority_id,
		zone_id,
		String(options.get("gameplay-port", "24580")),
		String(options.get("control-port", "24680")),
		String(options.get("peer-control-port", "24681")),
		fault_profile if not fault_profile.is_empty() else "none",
		recovery_dir if not recovery_dir.is_empty() else "none",
		recovery_performance if not recovery_performance.is_empty() else "none",
		active_owner_recovery,
		transaction_recovery,
		network_profile if not network_profile.is_empty() else "none",
		p4_fast,
	])
	var server
	if fault_profile == H4_3_RECOVERY_CHAIN_FAULT_PROFILE and recovery_performance == P2_2_RECOVERY_PERFORMANCE_PROFILE:
		server = RecoveryPerformanceV2ServerNode.new()
	elif fault_profile == H4_3_RECOVERY_CHAIN_FAULT_PROFILE and recovery_performance == P2_1_RECOVERY_PERFORMANCE_PROFILE:
		server = RecoveryPerformanceServerNode.new()
	elif fault_profile == H4_3_RECOVERY_CHAIN_FAULT_PROFILE:
		server = RecoveryChainFaultServerNode.new()
	elif fault_profile == H4_2_TRANSACTION_FAULT_PROFILE:
		server = TransactionMixedFaultServerNode.new()
	elif fault_profile in [
		H3_3_TRANSACTION_FAULT_PROFILE,
		H3_4_TRANSACTION_FAULT_PROFILE,
		H3_5_TRANSACTION_FAULT_PROFILE,
		H4_1_TRANSACTION_FAULT_PROFILE,
	]:
		server = TransactionFaultServerNode.new()
	elif fault_profile == H2_4_ACTIVE_RECOVERY_FAULT_PROFILE:
		server = ActiveRecoveryFaultServerNode.new()
	elif fault_profile in [H2_2_RECOVERY_FAULT_PROFILE, H2_3_RECOVERY_FAULT_PROFILE]:
		server = RecoveryFaultServerNode.new()
	elif not fault_profile.is_empty():
		server = FaultServerNode.new()
	elif network_profile == P3_1_NETWORK_PROFILE:
		server = NetworkDelayServerNode.new()
	elif transaction_recovery:
		server = TransactionRecoveryServerNode.new()
	elif active_owner_recovery:
		server = ActiveRecoveryServerNode.new()
	elif p4_fast:
		server = P4HardenedServerNode.new()
	elif not recovery_dir.is_empty():
		server = RecoveryServerNode.new()
	else:
		server = HealthyServerNode.new()
	server.name = "Sm0AuthorityServer"
	root.add_child(server)
	server.finished.connect(_on_finished)
	var result: Dictionary = server.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"gameplay_host": String(options.get("gameplay-host", "127.0.0.1")),
		"gameplay_port": int(options.get("gameplay-port", "24580")),
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "24680")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "24681")),
		"stop_file": String(options.get("stop-file", "")),
		"manifest_hash": String(options.get("manifest-hash", "sm0-two-zone-v1")),
		"fault_profile": fault_profile,
		"recovery_dir": recovery_dir,
		"recovery_performance": recovery_performance,
		"network_profile": network_profile,
		"network_latency_ms": int(options.get("network-latency-ms", "0")),
		"network_jitter_ms": int(options.get("network-jitter-ms", "0")),
		"network_seed": int(options.get("network-seed", "431")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 server setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_BOOT] setup_success authority=%s fault_profile=%s recovery_dir=%s recovery_performance=%s active_owner_recovery=%s transaction_recovery=%s network_profile=%s p4_fast=%s" % [
		authority_id,
		fault_profile if not fault_profile.is_empty() else "none",
		recovery_dir if not recovery_dir.is_empty() else (OS.get_environment("SM0_P4_RECOVERY_DIR") if p4_fast else "none"),
		recovery_performance if not recovery_performance.is_empty() else "none",
		active_owner_recovery,
		transaction_recovery,
		network_profile if not network_profile.is_empty() else "none",
		p4_fast,
	])


func _on_finished(exit_code: int) -> void:
	quit(exit_code)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg_value in args:
		var arg := String(arg_value)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var separator := arg.find("=")
		result[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
	return result
