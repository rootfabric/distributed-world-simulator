extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix1.gd"

# Compatibility entry point for the rev6 inventory enhancer.
#
# The first rev6 candidate placed the implementation in this file and layered a
# small fix1 script on top. Godot 4.7 exposed a compile failure in that inheritance
# chain during the focused test. The production/runtime entry point is now the
# standalone fix1 implementation; keep this path as a compatibility alias for
# any older preload/reference without reintroducing a second implementation.
