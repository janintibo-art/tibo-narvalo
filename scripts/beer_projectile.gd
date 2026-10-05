class_name BeerProjectile
extends Area3D

# Bouteille lancee par un Tibo LANCEUR. On peut l'esquiver, la parer,
# ou la renvoyer d'un coup de poing (elle repart vers Tibo).

signal hit_player(damage: int)

const SPEED := 4.2
const RETURN_SPEED := 7.5
const PLAYER_HIT_RADIUS := 0.30
const BOTTLE_PATHS := ["res://assets/props/Bier1.glb", "res://assets/props/Bier2.glb"]

var damage := 8
var source: Node3D
var velocity := Vector3.ZERO
var deflected := false
var age := 0.0
var camera: Node3D


func _init() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("projectile")


func _ready() -> void:
	camera = get_tree().get_first_node_in_group("xr_camera") as Node3D

	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.24
	shape_node.shape = sphere
	add_child(shape_node)

	_add_visual()


func launch(start: Vector3, target: Vector3) -> void:
	global_position = start
	velocity = (target - start).normalized() * SPEED


func deflect(power: float, fallback_direction: Vector3) -> void:
	if deflected:
		return

	deflected = true

	var direction := fallback_direction

	if is_instance_valid(source) and source.get("is_dead") != true:
		direction = (source.global_position + Vector3(0, 1.1, 0) - global_position).normalized()

	velocity = direction * RETURN_SPEED * clampf(power, 0.8, 1.4)
	damage = int(55 + 25 * power)
	age = 0.0


func _physics_process(delta: float) -> void:
	age += delta
	global_position += velocity * delta
	rotate_x(delta * 9.0)
	rotate_z(delta * 6.0)

	if age > 7.0:
		queue_free()
		return

	if deflected:
		_check_enemy_hit()
		return

	if camera == null:
		return

	var head := camera.global_position + Vector3(0, -0.1, 0)

	if global_position.distance_to(head) < PLAYER_HIT_RADIUS:
		CombatFX.glass_effect(global_position)
		GameAudio.play_sfx("glass", global_position)
		hit_player.emit(damage)
		queue_free()
		return

	if global_position.distance_to(camera.global_position) > 9.0:
		queue_free()


func _check_enemy_hit() -> void:
	for node in get_tree().get_nodes_in_group("tibo"):
		var enemy := node as Node3D

		if enemy == null or enemy.get("is_dead") == true:
			continue

		var offset := global_position - enemy.global_position
		var flat := Vector2(offset.x, offset.z).length()

		if flat < 0.5 and offset.y > -0.1 and offset.y < 2.0:
			if enemy.has_method("take_hit"):
				enemy.call("take_hit", damage, 1.2)

			CombatFX.hit_effect(global_position, damage, true, false)
			CombatFX.glass_effect(global_position)
			GameAudio.play_sfx("glass", global_position)
			GameAudio.play_sfx("punch_strong", global_position, -2.0)
			queue_free()
			return


func _add_visual() -> void:
	var paths: Array[String] = []

	for path in BOTTLE_PATHS:
		if ResourceLoader.exists(path):
			paths.append(path)

	if not paths.is_empty():
		var packed := load(paths[randi() % paths.size()]) as PackedScene

		if packed:
			var model := packed.instantiate() as Node3D

			if model:
				model.scale = Vector3.ONE * 0.16
				add_child(model)
				return

	var mesh_node := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.04
	capsule.height = 0.22
	mesh_node.mesh = capsule

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.25, 0.08)
	mesh_node.material_override = material
	add_child(mesh_node)
