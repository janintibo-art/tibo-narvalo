class_name TiboEnemy
extends CharacterBody3D

signal player_hit(damage: int)
signal defeated(tibo: Node)

@export var move_speed: float = 1.15
@export var attack_distance: float = 0.80
@export var attack_repeat: float = 1.8
@export var max_health: int = 100
@export var attack_damage: int = 12

const STAGGER_TIME := 0.45
const KNOCKBACK_SPEED := 1.8
const ATTACK_WINDUP := 0.55
const BAR_WIDTH := 0.60
const BAR_HEIGHT := 0.07

var health: int
var player_camera: XRCamera3D
var animation_player: AnimationPlayer
var walk_animation: StringName = &""
var hit_animation: StringName = &""
var death_animation: StringName = &""
var attack_animations: Array[StringName] = []

var attack_timer: float = 0.0
var attack_windup: float = 0.0
var attack_in_progress := false
var is_dead := false
var stagger_timer: float = 0.0
var stagger_total: float = STAGGER_TIME
var knockback := Vector3.ZERO

var meshes: Array[MeshInstance3D] = []
var tint_material: StandardMaterial3D
var tint_on := false
var flash_tween: Tween

var bar_fill: MeshInstance3D
var bar_fill_mesh: QuadMesh
var bar_fill_material: StandardMaterial3D

@onready var name_label: Label3D = $Name
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_pivot: Node3D = $ModelPivot


func _ready() -> void:
	health = max_health
	move_speed *= randf_range(0.88, 1.18)
	attack_repeat *= randf_range(0.85, 1.15)
	attack_timer = randf_range(0.6, 1.4)

	player_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D
	animation_player = _find_animation_player(self)

	if animation_player:
		walk_animation = _find_first_animation(["walk"])
		if walk_animation == &"":
			walk_animation = _find_first_animation(["run"])
		if walk_animation == &"":
			walk_animation = _first_real_animation()

		hit_animation = _find_first_animation(["hit", "damage", "impact"])
		death_animation = _find_first_animation(["death", "die", "dying", "knock"])
		attack_animations = _find_animations(["attack", "hook", "kick", "punch", "strike"])

		_play(walk_animation)

	_collect_meshes(model_pivot)
	_build_tint()
	_build_health_bar()
	_update_label()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if player_camera == null:
		player_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D
		if player_camera == null:
			return

	var target := player_camera.global_position
	target.y = global_position.y

	var to_player := target - global_position
	var distance := to_player.length()

	if distance > 0.05:
		look_at(target, Vector3.UP)

	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity = knockback
		knockback = knockback.move_toward(Vector3.ZERO, KNOCKBACK_SPEED * 3.0 * delta)
		move_and_slide()
		_update_flinch()
		return

	_update_flinch()

	if attack_in_progress:
		velocity = Vector3.ZERO
		move_and_slide()
		attack_windup -= delta

		var progress := 1.0 - clampf(attack_windup / ATTACK_WINDUP, 0.0, 1.0)
		var pulse := 0.75 + 0.25 * sin(progress * 38.0)
		_set_tint(Color(1.0, 0.45, 0.05, 0.55 * progress * pulse))

		if attack_windup <= 0.0:
			attack_in_progress = false
			_end_warning()
			if distance <= attack_distance + 0.30:
				player_hit.emit(attack_damage)
		return

	if distance > attack_distance:
		var direction := to_player.normalized()
		velocity = direction * move_speed
		velocity.y = 0.0
		move_and_slide()
		_play(walk_animation)
		attack_timer = max(attack_timer - delta, 0.0)
	else:
		velocity = Vector3.ZERO
		move_and_slide()
		attack_timer -= delta
		if attack_timer <= 0.0:
			_start_attack()
			attack_timer = attack_repeat


func _start_attack() -> void:
	attack_in_progress = true
	attack_windup = ATTACK_WINDUP

	name_label.modulate = Color(1.0, 0.35, 0.25)
	GameAudio.play_sfx("windup", global_position + Vector3(0, 1.2, 0), -4.0)

	if not attack_animations.is_empty():
		var chosen := attack_animations[randi() % attack_animations.size()]
		_play(chosen, true)


func _end_warning() -> void:
	name_label.modulate = Color.WHITE
	_set_tint(Color(1, 1, 1, 0))


func take_hit(amount: int, power: float = 1.0) -> void:
	if is_dead:
		return

	health = max(0, health - amount)
	_update_label()
	_flash_hit()

	if health <= 0:
		_die()
		return

	attack_in_progress = false
	name_label.modulate = Color.WHITE
	attack_timer = maxf(attack_timer, 0.6)
	stagger_total = STAGGER_TIME * clampf(power, 0.8, 1.3)
	stagger_timer = stagger_total

	if player_camera:
		var away := global_position - player_camera.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			knockback = away.normalized() * KNOCKBACK_SPEED * clampf(power, 0.6, 1.6)

	if hit_animation != &"":
		_play(hit_animation, true)


func _update_flinch() -> void:
	if model_pivot == null:
		return

	var amount := clampf(stagger_timer / stagger_total, 0.0, 1.0)
	model_pivot.rotation = Vector3(-0.35 * amount, PI, 0.0)


func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	name_label.text = "KO !"
	name_label.modulate = Color(1.0, 0.9, 0.3)

	if bar_fill:
		bar_fill.get_parent().visible = false

	GameAudio.play_sfx("ko", global_position + Vector3(0, 1.0, 0))
	CombatFX.ko_effect(global_position + Vector3(0, 1.1, 0))

	if death_animation != &"":
		_play(death_animation, true)
	else:
		var tween := create_tween()
		tween.tween_property(model_pivot, "rotation", Vector3(-1.45, PI, 0.0), 0.45)

	defeated.emit(self)
	await get_tree().create_timer(1.6).timeout
	queue_free()


func _update_label() -> void:
	if name_label:
		var title := "MEGA TIBO" if has_meta("is_boss") else "TIBO"
		name_label.text = "%s  %d" % [title, health]

	_update_bar()


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)

	for child in node.get_children():
		_collect_meshes(child)


func _build_tint() -> void:
	tint_material = StandardMaterial3D.new()
	tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint_material.albedo_color = Color(1, 0.1, 0.05, 0.0)


func _set_tint(color: Color) -> void:
	if tint_material == null:
		return

	if color.a <= 0.01:
		if tint_on:
			tint_on = false
			for mesh in meshes:
				mesh.material_overlay = null
		return

	tint_material.albedo_color = color

	if not tint_on:
		tint_on = true
		for mesh in meshes:
			mesh.material_overlay = tint_material


func _flash_hit() -> void:
	if flash_tween:
		flash_tween.kill()

	_set_tint(Color(1.0, 0.1, 0.05, 0.65))

	flash_tween = create_tween()
	flash_tween.tween_method(_flash_step, 0.65, 0.0, 0.22)


func _flash_step(alpha: float) -> void:
	_set_tint(Color(1.0, 0.1, 0.05, alpha))


func _build_health_bar() -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	bar.position = Vector3(0, 1.84, 0)
	add_child(bar)

	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(BAR_WIDTH + 0.02, BAR_HEIGHT + 0.02)

	var back_material := StandardMaterial3D.new()
	back_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back_material.billboard_keep_scale = true
	back_material.no_depth_test = true
	back_material.render_priority = 1
	back_material.albedo_color = Color(0.05, 0.05, 0.05, 0.75)

	var back := MeshInstance3D.new()
	back.mesh = back_mesh
	back.material_override = back_material
	bar.add_child(back)

	bar_fill_mesh = QuadMesh.new()
	bar_fill_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	bar_fill_material = StandardMaterial3D.new()
	bar_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bar_fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_fill_material.billboard_keep_scale = true
	bar_fill_material.no_depth_test = true
	bar_fill_material.render_priority = 2
	bar_fill_material.albedo_color = Color(0.2, 0.9, 0.25, 1.0)

	bar_fill = MeshInstance3D.new()
	bar_fill.mesh = bar_fill_mesh
	bar_fill.material_override = bar_fill_material
	bar.add_child(bar_fill)


func _update_bar() -> void:
	if bar_fill_mesh == null:
		return

	var ratio := clampf(float(health) / float(maxi(1, max_health)), 0.0, 1.0)
	var width := maxf(0.001, BAR_WIDTH * ratio)

	bar_fill_mesh.size = Vector2(width, BAR_HEIGHT)
	bar_fill_mesh.center_offset = Vector3(-(BAR_WIDTH - width) * 0.5, 0, 0)
	bar_fill_material.albedo_color = Color(
		minf(1.0, 2.0 * (1.0 - ratio)),
		minf(1.0, 2.0 * ratio),
		0.15,
		1.0
	)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _first_real_animation() -> StringName:
	if animation_player == null:
		return &""

	for anim_name in animation_player.get_animation_list():
		if anim_name != &"RESET":
			return anim_name

	return &""


func _find_first_animation(keywords: Array[String]) -> StringName:
	var matches := _find_animations(keywords)
	if not matches.is_empty():
		return matches[0]
	return &""


func _find_animations(keywords: Array[String]) -> Array[StringName]:
	var matches: Array[StringName] = []
	if animation_player == null:
		return matches

	for animation_name in animation_player.get_animation_list():
		if animation_name == &"RESET":
			continue

		var lower := String(animation_name).to_lower()
		for keyword in keywords:
			if lower.contains(keyword):
				matches.append(animation_name)
				break

	return matches


func _play(animation_name: StringName, restart: bool = false) -> void:
	if animation_player == null or animation_name == &"":
		return

	if restart or animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name)
