extends RefCounted

var zone_id
var x: int = 0
var y: int = 0


func setup(zone_id_value, x_value: int, y_value: int) -> void:
    zone_id = zone_id_value
    x = x_value
    y = y_value


func key() -> String:
    return "%s/chunk/%02d/%02d" % [zone_id.key(), x, y]


func short_name() -> String:
    return "%s C%02d,%02d" % [zone_id.short_name(), x, y]
