@tool
extends EditorPlugin
## Breakpoint MCP — EditorPlugin entry point.
##
## Spins up a loopback TCP server (bridge_server.gd) when the plugin is enabled
## and tears it down when disabled. All engine interaction happens on the main
## thread: the server polls its socket from _process, so every request handler
## already runs in a main-thread context (no marshaling needed for this scaffold).
##
## D3: also watches the editor selection and the edited scene, and asks the
## bridge server to push a "resource.changed" event when either moves, so a
## subscribed MCP host can emit notifications/resources/updated.

const BridgeServer := preload("res://addons/breakpoint_mcp/bridge_server.gd")
const StatusDock := preload("res://addons/breakpoint_mcp/status_dock.gd")
const PauseLatch := preload("res://addons/breakpoint_mcp/pause_latch.gd")
const RUNTIME_AUTOLOAD := "BreakpointRuntimeBridge"
const RUNTIME_SCRIPT := "res://addons/breakpoint_mcp/runtime_bridge.gd"

var _server: Node = null
var _dock: Control = null
var _selection: EditorSelection = null
var _owns_runtime_autoload: bool = false


func _enter_tree() -> void:
	_server = BridgeServer.new()
	_server.name = "BreakpointBridgeServer"
	_server.setup(self)
	add_child(_server)
	# Phase-4 status/config dock: a thin panel that reports bridge health across
	# the editor/runtime/LSP/DAP planes and offers a one-click MCP-client config.
	# Connection/status/config only — not a chat UI. Reads the server in-process.
	var dock := StatusDock.new()
	dock.set_server(_server)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_dock = dock
	# A project may deliberately track the runtime bridge in project.godot. In that
	# case the plugin must NOT re-register it: EditorPlugin.add_autoload_singleton()
	# rewrites ProjectSettings and can canonicalize a stable res:// entry to uid://
	# during editor/import startup. Only own and later remove an autoload that this
	# plugin actually had to create for a project that did not already declare it.
	_ensure_runtime_autoload()
	# D3: emit resources/updated triggers. Selection + edited scene are reflected
	# in godot://editor-state; the edited tree in godot://scene-tree.
	_selection = EditorInterface.get_selection()
	if _selection and not _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.connect(_on_selection_changed)
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	# Pause is a session control: clear any flag left over from a prior session so a
	# fresh editor always starts running (never silently paused by a stale file).
	PauseLatch.set_paused(false)
	print("[breakpoint_mcp] plugin enabled")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _selection and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	_selection = null
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _owns_runtime_autoload:
		remove_autoload_singleton(RUNTIME_AUTOLOAD)
		_owns_runtime_autoload = false
	if _server:
		_server.shutdown()
		_server.queue_free()
		_server = null
	# Don't leave the agent latched paused once the plugin (and its dock) are gone.
	PauseLatch.set_paused(false)
	print("[breakpoint_mcp] plugin disabled")


func _ensure_runtime_autoload() -> void:
	_owns_runtime_autoload = false
	var setting_name := "autoload/%s" % RUNTIME_AUTOLOAD
	if ProjectSettings.has_setting(setting_name):
		return
	add_autoload_singleton(RUNTIME_AUTOLOAD, RUNTIME_SCRIPT)
	_owns_runtime_autoload = true


## D3: the editor selection changed — godot://editor-state reflects the selection.
func _on_selection_changed() -> void:
	if _server:
		_server.broadcast_event("godot://editor-state")


## D3: a different scene is being edited — both the tree and editor state change.
func _on_scene_changed(_scene_root: Node) -> void:
	if _server:
		_server.broadcast_event("godot://scene-tree")
		_server.broadcast_event("godot://editor-state")
