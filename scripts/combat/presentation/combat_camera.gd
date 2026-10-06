class_name CombatCamera
extends Camera3D
## Fixed 3/4 combat camera with screen shake and punch-in. Runs on real (presentation) time, not
## attack time, so a hit-stop freeze still shakes.

var _base_position: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _shake_strength: float = 0.0
var _shake_until_us: int = 0
var _shake_length_us: int = 1
var _punch_amount: float = 0.0
var _punch_until_us: int = 0
var _punch_length_us: int = 1
var _rng := RandomNumberGenerator.new()


func setup(position_value: Vector3, target: Vector3, fov_degrees: float) -> void:
	_base_position = position_value
	_target = target
	fov = fov_degrees
	transform = Transform3D(Basis.looking_at(_target - _base_position, Vector3.UP), _base_position)
	_rng.randomize()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var offset := Vector3.ZERO
	if now < _shake_until_us:
		var k := float(_shake_until_us - now) / float(_shake_length_us)
		var s := _shake_strength * k
		offset += Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), 0.0)
	if now < _punch_until_us:
		var k := float(_punch_until_us - now) / float(_punch_length_us)
		offset += (_target - _base_position).normalized() * _punch_amount * k * k
	position = _base_position + offset


## Shakes by up to `strength` world units, fading over `ms` milliseconds. Stronger shakes win.
func shake(strength: float, ms: int) -> void:
	var now := Time.get_ticks_usec()
	var current := 0.0
	if now < _shake_until_us:
		current = _shake_strength * float(_shake_until_us - now) / float(_shake_length_us)
	if strength < current:
		return
	_shake_strength = strength
	_shake_length_us = maxi(1, ms * 1000)
	_shake_until_us = now + _shake_length_us


## Moves toward the target by `amount` world units and eases back over `ms` milliseconds.
func punch(amount: float, ms: int) -> void:
	_punch_amount = amount
	_punch_length_us = maxi(1, ms * 1000)
	_punch_until_us = Time.get_ticks_usec() + _punch_length_us
