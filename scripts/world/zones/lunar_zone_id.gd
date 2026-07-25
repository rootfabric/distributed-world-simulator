extends RefCounted

var face: int = 0
var x: int = 0
var y: int = 0


func setup(face_value: int, x_value: int, y_value: int) -> void:
    face = face_value
    x = x_value
    y = y_value


func key() -> String:
    return "zone/f%d/%02d/%02d" % [face, x, y]


func short_name() -> String:
    return "F%d Z%02d,%02d" % [face, x, y]
