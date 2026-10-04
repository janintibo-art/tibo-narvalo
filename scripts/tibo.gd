extends CharacterBody3D

@export var move_speed: float = 1.15
@export var attack_distance: float = 1.15
@export var attack_repeat: float = 1.6

var player_camera: XRCamera3D
var animation_player: AnimationPlayer
var walk_animation: StringName = &""
var attack_animation: StringName = &""
var attack_timer: float = 0.0

func _ready() -> void:
	player_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D
	animation_player = _find_animation_player(self)
	if animation_player:
		walk_animation = _pick_animation([&"Walking", &"Running", &"Armature|clip0|baselayer"])
		attack_animation = _pick_animation([&"Right_Upper_Hook_from_Guard", &"Lunge_Spin_Kick"])
		_play(walk_animation)

func _physics_process(delta: float) -> void:
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

	if distance > attack_distance:
		var direction := to_player.normalized()
		velocity = direction * move_speed
		velocity.y = 0.0
		move_and_slide()
		_play(walk_animation)
		attack_timer = min(attack_timer, 0.25)
	else:
		velocity = Vector3.ZERO
		move_and_slide()
		attack_timer -= delta
		if attack_timer <= 0.0:
			_play(attack_animation, true)
			attack_timer = attack_repeat

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _pick_animation(candidates: Array[StringName]) -> StringName:
	if animation_player == null:
		return &""
	for candidate in candidates:
		if animation_player.has_animation(candidate):
			return candidate
	var available := animation_player.get_animation_list()
	for name in available:
		if name != &"RESET":
			return name
	return &""

func _play(animation_name: StringName, restart: bool = false) -> void:
	if animation_player == null or animation_name == &"":
		return
	if restart or animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name)
