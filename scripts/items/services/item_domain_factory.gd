extends RefCounted

const ItemRegistryScript = preload("res://scripts/items/services/item_registry.gd")
const ContainerRegistryScript = preload("res://scripts/containers/container_registry.gd")
const ValidatorScript = preload("res://scripts/items/services/item_relationship_validator.gd")
const MassServiceScript = preload("res://scripts/items/services/item_mass_service.gd")
const TransferServiceScript = preload("res://scripts/items/services/item_transfer_service.gd")
const AttachmentServiceScript = preload("res://scripts/assemblies/item_attachment_service.gd")
const JsonItemStateStoreScript = preload("res://scripts/items/persistence/json_item_state_store.gd")


static func create() -> Dictionary:
	var item_registry = ItemRegistryScript.new()
	var container_registry = ContainerRegistryScript.new()
	var validator = ValidatorScript.new()
	validator.setup(item_registry, container_registry)
	var mass_service = MassServiceScript.new()
	mass_service.setup(item_registry, container_registry)
	var transfer_service = TransferServiceScript.new()
	transfer_service.setup(item_registry, container_registry, validator, mass_service)
	var attachment_service = AttachmentServiceScript.new()
	attachment_service.setup(transfer_service, item_registry)
	return {
		"items": item_registry,
		"containers": container_registry,
		"validator": validator,
		"mass": mass_service,
		"transfer": transfer_service,
		"attachments": attachment_service,
	}


static func create_json_state_store(
	root_path: String = "user://planet_simulator/item_states"
):
	return JsonItemStateStoreScript.new(root_path)
