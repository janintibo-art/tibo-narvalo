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
const KNOCKBACK_SPEED := 2.2

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
var knockback := Vector3.ZERO

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
		if attack_windup <= 0.0:
			attack_in_progress = false
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
	attack_windup = 0.55

	if not attack_animations.is_empty():
		var chosen := attack_animations[randi() % attack_animations.size()]
		_play(chosen, true)


func take_hit(amount: int) -> void:
	if is_dead:
		return

	health = max(0, health - amount)
	_update_label()

	if health <= 0:
		_die()
		return

	attack_in_progress = false
	attack_timer = maxf(attack_timer, 0.6)
	stagger_timer = STAGGER_TIME

	if player_camera:
		var away := global_position - player_camera.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			knockback = away.normalized() * KNOCKBACK_SPEED

	if hit_animation != &"":
		_play(hit_animation, true)


func _update_flinch() -> void:
	if model_pivot == null:
		return

	var amount := clampf(stagger_timer / STAGGER_TIME, 0.0, 1.0)
	model_pivot.rotation = Vector3(-0.35 * amount, PI, 0.0)


func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	name_label.text = "KO !"

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
