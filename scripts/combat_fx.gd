extends Node

# Effets visuels du combat : etincelles, chiffres de degats, flash rouge quand on est touche.

var hurt_overlay: MeshInstance3D
var hurt_material: StandardMaterial3D
var hurt_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func hit_effect(pos: Vector3, damage: int, strong: bool, shovel: bool) -> void:
	var scene := get_tree().current_scene

	if scene == null:
		return

	var color := Color(1.0, 0.85, 0.35)
	var amount := 14
	var speed := 2.4
	var size := 0.014

	if shovel:
		color = Color(0.85, 0.92, 1.0)
		amount = 22
		speed = 3.2
	elif strong:
		color = Color(1.0, 0.55, 0.15)
		amount = 24
		speed = 3.2
		size = 0.018

	_spawn_burst(scene, pos, amount, speed, color, size)
	_spawn_number(scene, pos, damage, strong, shovel)


func ko_effect(pos: Vector3) -> void:
	var scene := get_tree().current_scene

	if scene == null:
		return

	_spawn_burst(scene, pos, 40, 4.0, Color(1.0, 0.9, 0.3), 0.022)
	_spawn_burst(scene, pos, 24, 2.2, Color(1.0, 0.35, 0.1), 0.03)


func player_hurt(damage: int) -> void:
	_ensure_overlay()

	if hurt_material == null or not is_instance_valid(hurt_overlay):
		return

	var alpha := clampf(0.22 + damage * 0.015, 0.25, 0.5)

	hurt_overlay.visible = true
	hurt_material.albedo_color = Color(0.9, 0.05, 0.05, alpha)

	if hurt_tween:
		hurt_tween.kill()

	hurt_tween = create_tween()
	hurt_tween.tween_method(_set_hurt_alpha, alpha, 0.0, 0.45)
	hurt_tween.tween_callback(_hide_hurt_overlay)


func _set_hurt_alpha(value: float) -> void:
	if hurt_material:
		hurt_material.albedo_color = Color(0.9, 0.05, 0.05, value)


func _hide_hurt_overlay() -> void:
	if is_instance_valid(hurt_overlay):
		hurt_overlay.visible = false


func _ensure_overlay() -> void:
	if is_instance_valid(hurt_overlay):
		return

	var cam := get_tree().get_first_node_in_group("xr_camera") as Node3D

	if cam == null:
		return

	hurt_overlay = MeshInstance3D.new()
	hurt_overlay.name = "HurtFlash"

	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	hurt_overlay.mesh = quad
	hurt_overlay.position = Vector3(0, 0, -0.25)

	hurt_material = StandardMaterial3D.new()
	hurt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hurt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hurt_material.no_depth_test = true
	hurt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hurt_material.render_priority = 100
	hurt_material.albedo_color = Color(0.9, 0.05, 0.05, 0.0)
	hurt_overlay.material_override = hurt_material
	hurt_overlay.visible = false

	cam.add_child(hurt_overlay)


func _spawn_burst(scene: Node, pos: Vector3, amount: int, speed: float, color: Color, size: float) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.gravity = Vector3(0, -3.5, 0)
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3

	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	particles.mesh = sphere

	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = gradient

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	particles.material_override = material

	scene.add_child(particles)
	particles.global_position = pos
	particles.emitting = true

	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


func _spawn_number(scene: Node, pos: Vector3, damage: int, strong: bool, shovel: bool) -> void:
	var label := Label3D.new()
	label.text = "%d" % damage
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0012
	label.font_size = 64
	label.outline_size = 12
	label.outline_modulate = Color(0.1, 0.0, 0.0)
	label.modulate = Color(1.0, 0.95, 0.6)

	if shovel:
		label.font_size = 90
		label.modulate = Color(0.8, 0.92, 1.0)
		label.text = "%d!" % damage
	elif strong:
		label.font_size = 90
		label.modulate = Color(1.0, 0.5, 0.1)
		label.text = "%d!" % damage

	var spot := pos + Vector3(randf_range(-0.08, 0.08), 0.12, 0.0)
	var cam := get_tree().get_first_node_in_group("xr_camera") as Node3D

	if cam:
		var toward := cam.global_position - spot
		toward.y = 0.0

		if toward.length_squared() > 0.0001:
			spot += toward.normalized() * 0.2

	scene.add_child(label)
	label.global_position = spot

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", spot.y + 0.35, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)
