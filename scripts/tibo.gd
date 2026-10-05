class_name TiboEnemy
extends CharacterBody3D

signal player_hit(damage: int)
signal defeated(tibo: Node)
signal projectile_spawned(projectile: Node)

@export var move_speed: float = 1.15
@export var attack_distance: float = 0.80
@export var attack_repeat: float = 1.8
@export var max_health: int = 100
@export var attack_damage: int = 12
@export var kind: String = "normal"

const STAGGER_TIME := 0.45
const KNOCKBACK_SPEED := 1.8
const ATTACK_WINDUP := 0.55
const BAR_WIDTH := 0.60
const BAR_HEIGHT := 0.07
const THROW_RANGE_MAX := 3.6
const THROW_RANGE_MIN := 2.0

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

var is_thrower := false
var windup_time: float = ATTACK_WINDUP
var warn_color := Color(1.0, 0.45, 0.05)
var base_label_color := Color.WHITE
var kind_title := "TIBO"
var base_warn_color := Color(1.0, 0.45, 0.05)
var high_attack := false
var windup_current: float = ATTACK_WINDUP
var stun_timer := 0.0
var spawn_timer := 0.0
var base_model_scale := Vector3.ONE
var shadow: MeshInstance3D
var shadow_material: StandardMaterial3D

var run_animation: StringName = &""
var strafe_dir := 1.0
var strafe_timer := 0.0
var retreat_timer := 0.0
var dash_state := 0
var dash_timer := 0.0
var dash_cooldown := 0.0
var dash_lean := 0.0
var dodge_timer := 0.0
var dodge_cooldown := 0.0
var dodge_velocity := Vector3.ZERO

static var shadow_texture: ImageTexture
var flash_color := Color(1.0, 0.1, 0.05)

var meshes: Array[MeshInstance3D] = []
var tint_material: StandardMaterial3D
var tint_on := false
var flash_tween: Tween

var bar_root: Node3D
var bar_fill: MeshInstance3D
var bar_fill_mesh: QuadMesh
var bar_fill_material: StandardMaterial3D

@onready var name_label: Label3D = $Name
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_pivot: Node3D = $ModelPivot


func _ready() -> void:
	_apply_kind()
	base_model_scale = model_pivot.scale
	health = max_health
	move_speed *= randf_range(0.88, 1.18)
	attack_repeat *= randf_range(0.85, 1.15)
	attack_timer = randf_range(0.6, 1.4)
	dash_cooldown = randf_range(2.0, 4.0)
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	strafe_timer = randf_range(1.0, 2.5)

	player_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D
	animation_player = _find_animation_player(self)

	if animation_player:
		walk_animation = _find_first_animation(["walk"])
		if walk_animation == &"":
			walk_animation = _find_first_animation(["run"])
		if walk_animation == &"":
			walk_animation = _first_real_animation()

		run_animation = _find_first_animation(["run"])
		if run_animation == &"":
			run_animation = walk_animation

		hit_animation = _find_first_animation(["hit", "damage", "impact"])
		death_animation = _find_first_animation(["death", "die", "dying", "knock"])
		attack_animations = []

		for candidate in _find_animations(["attack", "hook", "kick", "punch", "strike"]):
			if animation_player.get_animation(candidate).length <= 2.5:
				attack_animations.append(candidate)

		_play(walk_animation)

	_collect_meshes(model_pivot)
	_build_tint()
	_build_health_bar()

	var height_scale := model_pivot.scale.y
	name_label.position.y = 2.0 * height_scale
	bar_root.position.y = 1.84 * height_scale
	name_label.modulate = base_label_color

	_update_label()
	_build_shadow()
	_play_spawn()


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

	stun_timer = maxf(0.0, stun_timer - delta)

	if spawn_timer > 0.0:
		spawn_timer -= delta
		velocity = Vector3.ZERO
		return

	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity = knockback
		knockback = knockback.move_toward(Vector3.ZERO, KNOCKBACK_SPEED * 3.0 * delta)
		move_and_slide()
		_update_flinch()
		return

	_update_flinch()

	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	strafe_timer -= delta

	if strafe_timer <= 0.0:
		strafe_dir = 1.0 if randf() < 0.5 else -1.0
		strafe_timer = randf_range(1.2, 2.8)

	if dodge_timer > 0.0:
		dodge_timer -= delta
		velocity = dodge_velocity
		dodge_velocity = dodge_velocity.lerp(Vector3.ZERO, minf(1.0, delta * 5.0))
		move_and_slide()
		return

	if attack_in_progress:
		velocity = Vector3.ZERO
		move_and_slide()
		attack_windup -= delta

		var progress := 1.0 - clampf(attack_windup / windup_current, 0.0, 1.0)
		var pulse := 0.75 + 0.25 * sin(progress * 38.0)
		_set_tint(Color(warn_color.r, warn_color.g, warn_color.b, 0.55 * progress * pulse))

		if attack_windup <= 0.0:
			attack_in_progress = false
			_end_warning()

			if is_thrower:
				_throw_beer()
			elif distance <= attack_distance + 0.30:
				var main := get_tree().current_scene

				if high_attack and main != null and main.has_method("is_ducking") and main.call("is_ducking"):
					_whiff()
				else:
					if main != null and main.has_method("is_guarding") and main.call("is_guarding"):
						recoil()

					player_hit.emit(attack_damage)

			high_attack = false

			if not is_thrower and randf() < 0.4:
				retreat_timer = randf_range(0.5, 0.9)
		return

	if dash_state != 0:
		_dash_update(delta, to_player, distance)
		return

	if _try_dodge(to_player):
		return

	if is_thrower:
		_thrower_move(delta, to_player, distance)
		return

	_melee_move(delta, to_player, distance)


func _melee_move(delta: float, to_player: Vector3, distance: float) -> void:
	var direction := to_player.normalized()
	var tangent := Vector3(direction.z, 0.0, -direction.x) * strafe_dir

	if retreat_timer > 0.0:
		retreat_timer -= delta
		velocity = (-direction + tangent * 0.3).normalized() * move_speed * 1.1
		velocity.y = 0.0
		move_and_slide()
		_play_move(walk_animation, -clampf(velocity.length() / 1.15, 0.6, 2.0))
		return

	if distance > attack_distance:
		if _can_dash(distance) and randf() < delta * 0.6:
			_start_dash()
			return

		var curve := 0.55 if distance < 3.2 else 0.0
		var move_direction := (direction + tangent * curve).normalized()
		velocity = move_direction * move_speed
		velocity.y = 0.0
		move_and_slide()
		_play_move_forward()
		attack_timer = maxf(attack_timer - delta, 0.0)
	else:
		var preferred := attack_distance * 0.85
		var radial := direction * clampf((distance - preferred) * 2.0, -move_speed, move_speed)
		velocity = tangent * move_speed * 0.5 + radial
		velocity.y = 0.0
		move_and_slide()
		_play_move(walk_animation, clampf(velocity.length() / 1.15, 0.5, 1.6))

		attack_timer -= delta

		if attack_timer <= 0.0:
			_start_attack()
			attack_timer = attack_repeat


func _play_move_forward() -> void:
	var animation_name := run_animation if kind == "rapide" else walk_animation
	var reference := 3.0 if animation_name == run_animation and run_animation != walk_animation else 1.15
	_play_move(animation_name, clampf(velocity.length() / reference, 0.6, 2.2))


func _can_dash(distance: float) -> bool:
	if is_thrower or dash_cooldown > 0.0 or attack_in_progress:
		return false

	if distance < 1.8 or distance > 3.6:
		return false

	var main := get_tree().current_scene

	if main == null:
		return false

	var wave_value = main.get("wave")
	return wave_value != null and int(wave_value) >= 2


func _start_dash() -> void:
	dash_state = 1
	dash_timer = 0.4
	name_label.modulate = Color(1.0, 0.7, 0.2)
	GameAudio.play_sfx("windup", global_position + Vector3(0, 1.0, 0), -8.0, 1.5)


func _dash_speed() -> float:
	if kind == "rapide":
		return 5.5

	if kind == "costaud":
		return 3.9

	return 4.6


func _dash_update(delta: float, to_player: Vector3, distance: float) -> void:
	var direction := to_player.normalized()
	dash_timer -= delta

	if dash_state == 1:
		velocity = Vector3.ZERO
		move_and_slide()

		var k := 1.0 - clampf(dash_timer / 0.4, 0.0, 1.0)
		dash_lean = 0.35 * k
		_set_tint(Color(1.0, 0.7, 0.2, 0.25 * k))
		_play_move(run_animation, 1.6)
		_update_flinch()

		if dash_timer <= 0.0:
			dash_state = 2
			dash_timer = 0.35
			GameAudio.play_sfx("whoosh", global_position + Vector3(0, 1.0, 0), -2.0, 0.7)
			CombatFX.spark(global_position + Vector3(0, 0.1, 0), Color(0.75, 0.65, 0.5), 8)
	else:
		velocity = direction * _dash_speed()
		velocity.y = 0.0
		move_and_slide()
		_play_move(run_animation, 1.4)
		_update_flinch()

		if dash_timer <= 0.0 or distance <= attack_distance * 0.95:
			_end_dash()


func _end_dash() -> void:
	dash_state = 0
	dash_lean = 0.0
	dash_cooldown = randf_range(4.0, 7.0)
	attack_timer = minf(attack_timer, 0.12)
	_end_warning()


func _try_dodge(to_player: Vector3) -> bool:
	if dodge_cooldown > 0.0 or stagger_timer > 0.0:
		return false

	var main := get_tree().current_scene

	if main == null or not main.has_method("swing_threat"):
		return false

	if not main.call("swing_threat", global_position + Vector3(0, 1.1, 0)):
		return false

	dodge_cooldown = 2.8

	var chance := 0.30
	var difficulty_value = main.get("selected_difficulty")

	if difficulty_value != null and String(difficulty_value) == "facile":
		chance = 0.15

	if kind == "rapide":
		chance += 0.15
	elif kind == "costaud":
		chance *= 0.5

	if has_meta("is_boss"):
		chance *= 0.4

	if randf() > chance:
		return false

	var direction := to_player.normalized()
	var side := Vector3(direction.z, 0.0, -direction.x) * (1.0 if randf() < 0.5 else -1.0)
	dodge_velocity = (side * 0.85 - direction * 0.5).normalized() * 4.4
	dodge_timer = 0.28
	attack_timer = minf(attack_timer, 0.4)

	GameAudio.play_sfx("whoosh", global_position + Vector3(0, 1.0, 0), -3.0, 1.4)
	CombatFX.float_text(global_position + Vector3(0, 2.3 * model_pivot.scale.y, 0), "RATE !", Color(0.8, 0.9, 1.0), 60)
	CombatFX.spark(global_position + Vector3(0, 0.1, 0), Color(0.75, 0.7, 0.6), 8)
	_play_move(walk_animation, 2.0)
	return true


func is_dodging() -> bool:
	return dodge_timer > 0.04


func _thrower_move(delta: float, to_player: Vector3, distance: float) -> void:
	var direction := to_player.normalized()

	if distance > THROW_RANGE_MAX:
		velocity = direction * move_speed
		_play_move(walk_animation, clampf(velocity.length() / 1.15, 0.6, 2.0))
	elif distance < THROW_RANGE_MIN:
		velocity = -direction * move_speed * 0.8
		_play_move(walk_animation, -clampf(velocity.length() / 1.15, 0.6, 2.0))
	else:
		var tangent := Vector3(direction.z, 0.0, -direction.x) * strafe_dir
		velocity = tangent * move_speed * 0.6
		_play_move(walk_animation, 0.8)

	velocity.y = 0.0
	move_and_slide()

	if distance <= THROW_RANGE_MAX + 0.6:
		attack_timer -= delta

		if attack_timer <= 0.0:
			_start_attack()
			attack_timer = attack_repeat


func _throw_beer() -> void:
	if player_camera == null or get_parent() == null:
		return

	var forward := -global_transform.basis.z
	forward.y = 0.0

	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD

	var start := global_position + Vector3(0, 1.45, 0) + forward.normalized() * 0.4
	var target := player_camera.global_position + Vector3(0, -0.08, 0)

	var projectile := BeerProjectile.new()
	projectile.damage = int(attack_damage * 1.3)
	projectile.source = self
	get_parent().add_child(projectile)
	projectile.launch(start, target)

	GameAudio.play_sfx("whoosh", start, -2.0, 0.8)
	projectile_spawned.emit(projectile)


func recoil() -> void:
	if is_dead:
		return

	attack_in_progress = false
	attack_timer = maxf(attack_timer, 1.0)
	stagger_total = 0.6
	stagger_timer = 0.6
	_flash_hit(Color(0.4, 0.7, 1.0))

	if player_camera:
		var away := global_position - player_camera.global_position
		away.y = 0.0

		if away.length_squared() > 0.0001:
			knockback = away.normalized() * 2.6


func _start_attack() -> void:
	attack_in_progress = true

	var main := get_tree().current_scene
	var wave_number := 0
	var easy := false

	if main != null:
		var wave_value = main.get("wave")
		var difficulty_value = main.get("selected_difficulty")

		if wave_value != null:
			wave_number = int(wave_value)

		easy = difficulty_value != null and String(difficulty_value) == "facile"

	var high_chance := 0.25 if easy else 0.35

	if kind == "costaud":
		high_chance *= 0.7

	high_attack = not is_thrower and wave_number >= 2 and randf() < high_chance

	if high_attack:
		windup_current = maxf(windup_time, 0.8)
		warn_color = Color(1.0, 0.95, 0.2)
		GameFeedback.show_message("BAISSE-TOI !", 0.9)
		GameAudio.play_sfx("alert", null, -2.0)
	else:
		windup_current = windup_time
		warn_color = base_warn_color

	attack_windup = windup_current

	name_label.modulate = Color(1.0, 0.35, 0.25)
	GameAudio.play_sfx("windup", global_position + Vector3(0, 1.2, 0), -4.0)

	if not attack_animations.is_empty():
		_play(_pick_attack_animation(high_attack), true)


func _pick_attack_animation(high: bool) -> StringName:
	var wanted := "kick" if high else "hook"

	for animation_name in attack_animations:
		if String(animation_name).to_lower().contains(wanted):
			return animation_name

	return attack_animations[randi() % attack_animations.size()]


func _whiff() -> void:
	stun_timer = 1.3
	stagger_total = 1.0
	stagger_timer = 1.0
	knockback = Vector3.ZERO
	attack_timer = maxf(attack_timer, 1.2)
	_flash_hit(Color(1.0, 0.9, 0.2))

	var head := global_position + Vector3(0, 2.3 * model_pivot.scale.y, 0)
	GameFeedback.show_message("ESQUIVE !", 0.9)
	GameAudio.play_sfx("whoosh", global_position + Vector3(0, 1.2, 0), 0.0, 1.2)
	CombatFX.float_text(head, "ETOURDI !", Color(1.0, 0.9, 0.2), 70)


func damage_multiplier() -> float:
	return 1.5 if stun_timer > 0.0 else 1.0


func _end_warning() -> void:
	name_label.modulate = base_label_color
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
	dash_state = 0
	dash_lean = 0.0
	retreat_timer = 0.0
	name_label.modulate = base_label_color
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
	model_pivot.rotation = Vector3(-0.35 * amount + dash_lean, PI, 0.0)


func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	name_label.text = "KO !"
	name_label.modulate = Color(1.0, 0.9, 0.3)

	stun_timer = 0.0

	if bar_fill:
		bar_fill.get_parent().visible = false

	if shadow_material:
		var fade := create_tween()
		fade.tween_property(shadow_material, "albedo_color:a", 0.0, 0.9)

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
		var title := "MEGA TIBO" if has_meta("is_boss") else kind_title
		name_label.text = "%s  %d" % [title, health]

	_update_bar()


func _apply_kind() -> void:
	if kind == "rapide":
		kind_title = "TIBO RAPIDE"
		base_label_color = Color(0.4, 0.9, 1.0)
		move_speed *= 1.45
		max_health = maxi(20, int(max_health * 0.6))
		attack_damage = maxi(3, int(attack_damage * 0.8))
		attack_repeat *= 0.75
		model_pivot.scale = Vector3.ONE * 0.92
	elif kind == "costaud":
		kind_title = "TIBO COSTAUD"
		base_label_color = Color(1.0, 0.6, 0.2)
		move_speed *= 0.72
		max_health = int(max_health * 2.0)
		attack_damage = int(attack_damage * 1.6)
		attack_repeat *= 1.3
		attack_distance = 0.95
		windup_time = 0.7
		model_pivot.scale = Vector3.ONE * 1.22

		var shape := collision_shape.shape.duplicate() as CapsuleShape3D

		if shape:
			shape.radius = 0.34
			shape.height = 2.0
			collision_shape.shape = shape
			collision_shape.position = Vector3(0, 1.0, 0)
	elif kind == "lanceur":
		kind_title = "TIBO LANCEUR"
		base_label_color = Color(0.85, 0.5, 1.0)
		is_thrower = true
		move_speed *= 0.85
		max_health = int(max_health * 0.8)
		attack_repeat = 2.8
		windup_time = 0.8
		base_warn_color = Color(0.6, 1.0, 0.2)
		warn_color = base_warn_color


static func _get_shadow_texture() -> ImageTexture:
	if shadow_texture == null:
		var size := 64
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

		for y in size:
			for x in size:
				var dx := (x + 0.5) / size * 2.0 - 1.0
				var dy := (y + 0.5) / size * 2.0 - 1.0
				var strength := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
				image.set_pixel(x, y, Color(0, 0, 0, strength * strength * 0.6))

		shadow_texture = ImageTexture.create_from_image(image)

	return shadow_texture


func _build_shadow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)

	shadow_material = StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.albedo_texture = _get_shadow_texture()

	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.material_override = shadow_material
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	shadow.position = Vector3(0, 0.012, 0)
	add_child(shadow)


func _play_spawn() -> void:
	spawn_timer = 0.5
	model_pivot.scale = base_model_scale * 0.05
	shadow.scale = Vector3.ONE * 0.1

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(model_pivot, "scale", base_model_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(shadow, "scale", Vector3.ONE * base_model_scale.x, 0.45)

	CombatFX.spawn_effect(global_position, kind == "costaud")
	GameAudio.play_sfx("spawn", global_position + Vector3(0, 0.5, 0), -3.0)


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


func _flash_hit(color: Color = Color(1.0, 0.1, 0.05)) -> void:
	if flash_tween:
		flash_tween.kill()

	flash_color = color
	_set_tint(Color(color.r, color.g, color.b, 0.65))

	flash_tween = create_tween()
	flash_tween.tween_method(_flash_step, 0.65, 0.0, 0.22)


func _flash_step(alpha: float) -> void:
	_set_tint(Color(flash_color.r, flash_color.g, flash_color.b, alpha))


func _build_health_bar() -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	bar.position = Vector3(0, 1.84, 0)
	add_child(bar)
	bar_root = bar

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


func _play_move(animation_name: StringName, speed: float = 1.0) -> void:
	if animation_player == null or animation_name == &"":
		return

	animation_player.speed_scale = speed

	if animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name, 0.15, 1.0, speed < 0.0)


func _play(animation_name: StringName, restart: bool = false) -> void:
	if animation_player == null or animation_name == &"":
		return

	animation_player.speed_scale = 1.0

	if restart or animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name)
