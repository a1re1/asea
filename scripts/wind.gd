# ASEA wind — RefCounted, deterministic, smoothly varying field.
# direction is a unit vector pointing TOWARD where the wind is going.
# World north is (0, -1) (heading 0, -Z). Strength is metres per second.
extends RefCounted

const MAX_SWELL_TURN_RATE := 0.00025
## Unit vector toward the wind's destination. North = (0, -1).
var direction: Vector2 = Vector2.ZERO
## Lagged swell used only by world-space wave phase (not sail drive/flag).
var swell_direction: Vector2 = Vector2.ZERO
## Wind speed in m/s.
var strength: float = 0.0

var _fixed: bool = false
var _time: float = 0.0
# Clockwise-from-north heading of the toward-vector. -PI/8 is NNW:
# a northbound spawn (heading 0) sees this as a slightly starboard tailwind.
var _base_angle: float = -PI / 8.0
var _base_strength: float = 10.0


func _init() -> void:
	_apply_field(0.0)
	swell_direction = direction


func step(delta: float) -> void:
	if _fixed or delta <= 0.0:
		return
	_time += delta
	_apply_field(_time)
	_turn_swell(delta)


func _turn_swell(delta: float) -> void:
	if swell_direction.length_squared() < 1e-12:
		swell_direction = direction
		return
	var from_ang: float = swell_direction.angle()
	var to_ang: float = direction.angle()
	var diff: float = angle_difference(from_ang, to_ang)
	var max_turn: float = MAX_SWELL_TURN_RATE * delta
	var turned: float = clampf(diff, -max_turn, max_turn)
	swell_direction = Vector2.from_angle(from_ang + turned)
	if swell_direction.length_squared() > 1e-12:
		swell_direction = swell_direction.normalized()
	else:
		swell_direction = direction


func _apply_field(t: float) -> void:
	# Multi-minute directional drift (~4–7 min) plus a tiny short wobble.
	# Amplitudes stay well under a right angle so the field never flips.
	var drift: float = 0.28 * sin(t * TAU / 240.0) + 0.12 * sin(t * TAU / 420.0 + 1.3)
	var wobble: float = 0.05 * sin(t * TAU / 22.0 + 0.4)
	var ang: float = _base_angle + drift + wobble
	direction = Vector2(sin(ang), -cos(ang))
	var dir_len: float = direction.length()
	if dir_len > 0.0001:
		direction /= dir_len
	else:
		direction = Vector2(0.0, -1.0)
	# Gentle gusts: ±~20% over ~7–11 s, never a step change.
	var gust: float = 0.12 * sin(t * TAU / 11.0) + 0.08 * sin(t * TAU / 7.3 + 2.1)
	strength = maxf(0.5, _base_strength * (1.0 + gust))


func set_fixed(p_direction: Vector2, p_strength: float) -> void:
	_fixed = true
	if p_direction.length_squared() > 0.0001:
		direction = p_direction.normalized()
	else:
		direction = Vector2(0.0, -1.0)
	strength = maxf(0.0, p_strength)
	swell_direction = direction
