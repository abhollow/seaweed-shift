class_name Package
extends Area2D

# The random jackpot. Rare, instantly valuable, and it despawns -- so it
# creates a "drop everything and go get it" moment.

var value := 400
var game

@export var tex_package: Texture2D

var _life := 18.0
var _t := 0.0


func setup(pos: Vector2, g) -> void:
	# Called before add_child, so _ready() sees the final values.
	position = pos
	game = g
	value = int(randf_range(300.0, 520.0))


func _ready() -> void:
	var spr := $Sprite as Sprite2D
	var vis := $Visual as ColorRect
	if tex_package != null:
		spr.texture = tex_package
		spr.visible = true
		vis.visible = false
		var t := tex_package.get_size()
		if t.x > 0.0 and t.y > 0.0:
			spr.scale = Vector2(24.0 / t.x, 16.0 / t.y)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	_life -= delta
	# Blink faster as it is about to wash back out.
	var blink := 6.0 if _life < 4.0 else 2.0
	modulate = Color(1, 1, 1, 0.55 + 0.45 * sin(_t * blink))
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Player and game != null:
		game.add_credits(value)
		game.sfx("package")
		game.popup("+%d!" % value, global_position, Color(1.0, 0.9, 0.35))
		queue_free()
