extends RefCounted

static func construct_id(index: int) -> String:
	return "construct/c21/%06d" % index

static func plan_id(index: int) -> String:
	return "build-plan/c21/%05d" % index

static func agent_id(index: int) -> String:
	return "agent/c21/%04d" % index

static func fabrication_job_id(index: int) -> String:
	return "fabrication-job/c21/%05d" % index

static func order_id(index: int) -> String:
	return "procurement-order/c21/%05d" % index

static func shipment_id(index: int) -> String:
	return "shipment/c21/%05d" % index

static func warehouse_id(index: int) -> String:
	return "warehouse/c21/%03d" % index

static func server_id(index: int) -> String:
	return "server/c21/%03d" % index

static func command_operation_id(tick: int, slot: int) -> String:
	return "operation/c21/command/%08d/%04d" % [tick, slot]

static func migration_operation_id(index: int) -> String:
	return "operation/c21/migration/%06d" % index

static func reconnect_operation_id(wave: int, slot: int) -> String:
	return "operation/c21/reconnect/%04d/%04d" % [wave, slot]

static func deterministic_index(seed: int, tick: int, slot: int, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var mixed: int = seed
	mixed = int((mixed * 1103515245 + 12345 + tick * 2654435761 + slot * 97) & 0x7fffffff)
	return mixed % modulo
