extends Node
## The difference between "a prototype" and "a game". AI reliably forgets this layer,
## so it lives in the shell and games get it for free with one-line calls:
##   Juice.hit()  Juice.shake(6)  Juice.pop(node)  Juice.flash(node)  Juice.text(pos,"+10")

var _shake := 0.0
var _shake_decay := 6.0
var _hitstop_left := 0.0

func _process(delta: float) -> void:
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		if _hitstop_left <= 0.0:
			Engine.time_scale = 1.0

	var cam := _camera()
	if cam == null:
		return
	if _shake > 0.01:
		_shake = maxf(0.0, _shake - _shake_decay * delta)
		cam.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO

func _camera() -> Camera2D:
	var vp := get_viewport()
	return vp.get_camera_2d() if vp != null else null

func shake(strength: float = 5.0) -> void:
	_shake = maxf(_shake, strength)

## Brief slow-motion on impact. Sells a hit better than any particle.
func hitstop(seconds: float = 0.06, scale: float = 0.05) -> void:
	Engine.time_scale = scale
	_hitstop_left = seconds * scale

## The standard "something important happened" combo.
func hit(strength: float = 6.0) -> void:
	shake(strength)
	hitstop()

## Squash-and-stretch pop on any Node2D.
func pop(node: Node2D, amount: float = 1.35, time: float = 0.18) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Vector2 = node.scale
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base * amount, time * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

## White flash on a sprite/canvas item (damage feedback).
func flash(node: CanvasItem, color: Color = Color.WHITE, time: float = 0.12) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Color = node.modulate
	node.modulate = color
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", base, time)

## Floating score/damage text.
func text(parent: Node, world_pos: Vector2, msg: String, color: Color = Color.WHITE) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var lbl := Label.new()
	lbl.text = msg
	lbl.modulate = color
	lbl.z_index = 100
	lbl.position = world_pos
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", world_pos + Vector2(0, -22), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(lbl.queue_free)
