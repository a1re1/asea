# ASEA • The Unwritten Sea — shared three-sine ocean height field.
#
# Shader (shaders/ocean.gdshader) and boat sampler use identical constants.
# Phase = dot(pos, direction) * TAU / wavelength - elapsed * angular_velocity
# so crests travel TOWARD the supplied wind vector. Amplitude is independent
# of wind strength (the sampler has no strength argument).
class_name SeaWaves
extends RefCounted

const A1 := 0.14
const A2 := 0.09
const A3 := 0.05
const L1 := 48.0
const L2 := 72.0
const L3 := 30.0
const W1 := 1.1
const W2 := 0.75
const W3 := 1.35
const ROT2 := 0.65
const ROT3 := -1.1
const HEIGHT_BOUND := 0.28
const FALLBACK_DIRECTION := Vector2(0.0, -1.0)


static func height_at(pos: Vector2, time: float, direction: Vector2) -> float:
	var d1 := _base_direction(direction)
	var d2 := d1.rotated(ROT2)
	var d3 := d1.rotated(ROT3)
	return (
		A1 * sin(_phase(pos, time, d1, L1, W1))
		+ A2 * sin(_phase(pos, time, d2, L2, W2))
		+ A3 * sin(_phase(pos, time, d3, L3, W3))
	)


static func slope_at(pos: Vector2, time: float, direction: Vector2) -> Vector2:
	var d1 := _base_direction(direction)
	var d2 := d1.rotated(ROT2)
	var d3 := d1.rotated(ROT3)
	return (
		_slope_term(pos, time, d1, A1, L1, W1)
		+ _slope_term(pos, time, d2, A2, L2, W2)
		+ _slope_term(pos, time, d3, A3, L3, W3)
	)


static func _base_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() > 1e-12:
		return direction.normalized()
	return FALLBACK_DIRECTION


static func _phase(pos: Vector2, time: float, direction: Vector2, wavelength: float, angular_velocity: float) -> float:
	return pos.dot(direction) * TAU / wavelength - time * angular_velocity


static func _slope_term(pos: Vector2, time: float, direction: Vector2, amp: float, wavelength: float, angular_velocity: float) -> Vector2:
	var k := TAU / wavelength
	var phase := _phase(pos, time, direction, wavelength, angular_velocity)
	# d(a sin(dot(pos,d)*k - ωt))/dpos = a cos(phase) * d * k
	return direction * (amp * cos(phase) * k)
