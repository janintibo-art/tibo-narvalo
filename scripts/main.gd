extends Node3D

const TIBO_SCENE := preload("res://scenes/Tibo.tscn")

var xr_interface: OpenXRInterface
var first_wave_spawned := false

@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var enemy_root: Node3D = $EnemyRoot

func _ready() -> void:
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

	call_deferred("_enable_passthrough")

func _on_openxr_session_begun() -> void:
	_enable_passthrough()

func _on_openxr_session_focussed() -> void:
	_enable_passthrough()
	_spawn_first_wave()

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

func _spawn_first_wave() -> void:
	if first_wave_spawned:
		return
	first_wave_spawned = true

	await get_tree().create_timer(1.0).timeout

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

	var spawn_positions: Array[Vector3] = [
		center + forward * 3.2,
		center + forward * 3.6 + right * 1.5,
		center + forward * 3.6 - right * 1.5
	]

	for spawn_position in spawn_positions:
		var tibo := TIBO_SCENE.instantiate() as CharacterBody3D
		enemy_root.add_child(tibo)
		tibo.global_position = spawn_position

	print("Tibo Narvalo : premiere vague de 3 Tibo lachee.")
