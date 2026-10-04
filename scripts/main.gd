extends Node3D

const TIBO_SCENE := preload("res://scenes/Tibo.tscn")

@export var player_max_health: int = 100
@export var hand_damage: int = 55

var xr_interface: OpenXRInterface
var player_health: int
var wave := 0
var active_tibos := 0
var game_over := false
var wave_started := false

@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var enemy_root: Node3D = $EnemyRoot
@onready var health_hud: Label3D = $XROrigin3D/XRCamera3D/HealthHUD
@onready var left_hit_area: Area3D = $XROrigin3D/LeftHand/HitArea
@onready var right_hit_area: Area3D = $XROrigin3D/RightHand/HitArea

func _ready() -> void:
	add_to_group("game_manager")
	player_health = player_max_health
	_update_hud()

	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null or not xr_interface.is_initialized():
		push_error("Tibo Narvalo : OpenXR indisponible ou non initialise.")
		return

	var viewport := get_viewport()
	viewport.use_xr = true
	viewport.transparent_bg = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	if not xr_interface.session_begun.is_connected(_on_openxr_session_begun):
		xr_interface.session_begun.connect(_on_openxr_session_begun)
	if not xr_interface.session_focussed.is_connected(_on_openxr_session_focussed):
		xr_interface.session_focussed.connect(_on_openxr_session_focussed)

	left_hit_area.body_entered.connect(_on_hand_body_entered.bind($XROrigin3D/LeftHand))
	right_hit_area.body_entered.connect(_on_hand_body_entered.bind($XROrigin3D/RightHand))

	call_deferred("_enable_passthrough")

func _on_openxr_session_begun() -> void:
	_enable_passthrough()

func _on_openxr_session_focussed() -> void:
	_enable_passthrough()
	if not wave_started:
		wave_started = true
		call_deferred("_start_next_wave")

func _enable_passthrough() -> void:
	if xr_interface == null:
		return

	var modes := xr_interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		print("Tibo Narvalo : passthrough alpha actif.")
	elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		print("Tibo Narvalo : passthrough additif actif.")
	else:
		push_warning("Tibo Narvalo : passthrough non supporte par ce runtime.")

func _start_next_wave() -> void:
	if game_over:
		return

	await get_tree().create_timer(1.0).timeout
	wave += 1

	var count := mini(4 + wave * 2, 10)
	active_tibos = count
	_update_hud()

	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, -1)
	else:
		forward = forward.normalized()

	var right := xr_camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var floor_y := xr_camera.global_position.y - 1.65
	var center := xr_camera.global_position
	center.y = floor_y

	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var direction := (forward * cos(angle) + right * sin(angle)).normalized()
		var distance := randf_range(3.2, 4.2)
		var spawn_position := center + direction * distance

		var tibo := TIBO_SCENE.instantiate() as TiboEnemy
		enemy_root.add_child(tibo)
		tibo.global_position = spawn_position
		tibo.player_hit.connect(_on_tibo_hit_player)
		tibo.defeated.connect(_on_tibo_defeated)

	print("Tibo Narvalo : vague %d, %d Tibo tout autour du joueur." % [wave, count])

func _on_hand_body_entered(body: Node3D, hand: XRController3D) -> void:
	if game_over or not body.is_in_group("tibo") or not body is TiboEnemy:
		return

	var tibo := body as TiboEnemy
	tibo.take_hit(hand_damage)

	var hand_name := "gauche" if hand.tracker == &"left_hand" else "droite"
	print("Tibo frappe avec la main %s !" % hand_name)

func _on_tibo_hit_player(damage: int) -> void:
	if game_over:
		return

	player_health = max(0, player_health - damage)
	_update_hud()

	if player_health <= 0:
		_game_over()

func _on_tibo_defeated(_tibo: Node) -> void:
	active_tibos = max(0, active_tibos - 1)
	_update_hud()

	if active_tibos == 0 and not game_over:
		call_deferred("_start_next_wave")

func _game_over() -> void:
	game_over = true
	health_hud.text = "TIBO T'A EU 😅\nRETOUR DANS 3..."
	print("Tibo Narvalo : joueur KO.")

	await get_tree().create_timer(3.0).timeout

	for child in enemy_root.get_children():
		child.queue_free()

	await get_tree().process_frame
	player_health = player_max_health
	wave = 0
	active_tibos = 0
	game_over = false
	_update_hud()
	call_deferred("_start_next_wave")

func _update_hud() -> void:
	if health_hud == null:
		return

	health_hud.text = "VIE %d/%d   VAGUE %d   TIBO %d" % [
		player_health,
		player_max_health,
		wave,
		active_tibos
	]
