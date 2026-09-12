# ASEA damped stern camera — ~30 back, 16 up, far >= 8000, horizon.
extends Camera3D

const BACK := 30.0
const UP := 16.0
const LOOK_AHEAD := 48.0
const DAMP := 5.5
const MIN_DIST := 14.0
const MAX_DIST := 90.0

var target: Node3D
var frozen: bool = false
var _yaw_off: float = 0.32
var _pitch_off: float = 0.0
var _dist: float = BACK
var _dragging: bool = false


func _ready() -> void:
	current = true
	fov = 65.0
	far = 8000.0
	near = 0.2
	if target == null:
		var p := get_parent()
		if p:
			target = p.get_node_or_null("Boat") as Node3D


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist - 4.0, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist + 4.0, MIN_DIST, MAX_DIST)
	elif event is InputEventMouseMotion and _dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_yaw_off -= mm.relative.x * 0.004
		_pitch_off = clampf(_pitch_off - mm.relative.y * 0.003, -0.35, 0.55)


func _process(delta: float) -> void:
	if frozen or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_dragging = false
	if target == null:
		return
	var heading: float = 0.0
	if "heading" in target:
		heading = float(target.heading)
	var yaw: float = heading + _yaw_off
	var back := Vector3(sin(yaw), 0.0, -cos(yaw)) * -_dist
	var desired: Vector3 = target.global_position + back + Vector3(0, UP + _pitch_off * 12.0, 0)
	var k: float = 1.0 - exp(-DAMP * delta)
	global_position = global_position.lerp(desired, k)
	var look: Vector3 = target.global_position + Vector3(sin(heading), 0, -cos(heading)) * LOOK_AHEAD
	look.y = 2.0
	look_at(look, Vector3.UP)
