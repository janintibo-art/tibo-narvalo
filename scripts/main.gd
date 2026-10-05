extends Node3D

const TIBO_SCENE := preload("res://scenes/Tibo.tscn")

const MODE_COMBAT := "combat"
const MODE_BERNI := "berni"

const DIFF_EASY := "facile"
const DIFF_NORMAL := "normal"
const DIFF_HARD := "difficile"

var xr_interface: OpenXRInterface

var game_state := "boot"
var selected_mode := MODE_COMBAT
var selected_difficulty := DIFF_EASY

var player_max_health := 100
var player_health := 100

var wave := 0
var wave_total := 0
var wave_spawned := 0
var wave_defeated := 0
var active_tibos := 0
var max_active_tibos := 1
var wave_transition_pending := false

var hand_damage := 55
var shovel_damage := 100
var game_over := false
var menu_input_locked := false

const PUNCH_MIN_SPEED := 1.0
const SHOVEL_MIN_SPEED := 1.4
const WHOOSH_SPEED := 2.6
const HIT_COOLDOWN_MS := 300
const COMBO_WINDOW := 1.6
const EXIT_HOLD := 1.0

var run_serial := 0
var hand_speed := {"left": 0.0, "right": 0.0, "shovel": 0.0}
var last_hand_pos := {}
var last_whoosh_ms := {"left": 0, "right": 0, "shovel": 0}
var combo := 0
var last_hit_time := 0.0
var exit_hold := 0.0
var hud_hint := ""

var menu_root: Node3D
var menu_status: Label3D
var shovel_root: Node3D
var shovel_hit_area: Area3D
var prop_root: Node3D
var beer_scenes: Array[PackedScene] = []

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var left_hit_area: Area3D = $XROrigin3D/LeftHand/HitArea
@onready var right_hit_area: Area3D = $XROrigin3D/RightHand/HitArea
@onready var enemy_root: Node3D = $EnemyRoot
@onready var health_hud: Label3D = $XROrigin3D/XRCamera3D/HealthHUD


func _ready() -> void:
	randomize()

	left_hit_area.collision_mask = 3
	right_hit_area.collision_mask = 3

	left_hand.button_pressed.connect(_on_controller_button)
	right_hand.button_pressed.connect(_on_controller_button)

	left_hit_area.area_entered.connect(_on_menu_area_entered)
	right_hit_area.area_entered.connect(_on_menu_area_entered)

	_create_runtime_objects()
	_load_beers()

	player_health = player_max_health
	health_hud.visible = false

	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null or not xr_interface.is_initialized():
		push_error("Tibo Narvalo : OpenXR indisponible.")
		return

	var viewport := get_viewport()
	viewport.use_xr = true
	viewport.transparent_bg = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)

	if not xr_interface.session_focussed.is_connected(_on_session_focussed):
		xr_interface.session_focussed.connect(_on_session_focussed)

	call_deferred("_enable_passthrough")


func _create_runtime_objects() -> void:
	prop_root = Node3D.new()
	prop_root.name = "Props"
	add_child(prop_root)

	menu_root = Node3D.new()
	menu_root.name = "MainMenu"
	add_child(menu_root)
	menu_root.visible = false
	_create_menu()

	shovel_root = _create_shovel()
	right_hand.add_child(shovel_root)
	shovel_root.visible = false

	shovel_hit_area = shovel_root.get_node("HitArea") as Area3D
	shovel_hit_area.monitoring = false


func _create_menu() -> void:
	var title := Label3D.new()
	title.name = "Title"
	title.text = "TIBO NARVALO"
	title.position = Vector3(0, 1.05, 0)
	title.font_size = 105
	title.outline_size = 14
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_root.add_child(title)

	var subtitle := Label3D.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Choisis ton mode et ta difficulte"
	subtitle.position = Vector3(0, 0.72, 0)
	subtitle.font_size = 40
	subtitle.outline_size = 8
	subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_root.add_child(subtitle)

	menu_root.add_child(
		_create_button(
			"COMBAT",
			"mode",
			MODE_COMBAT,
			Vector3(-0.65, 0.30, 0),
			Color(0.12, 0.55, 0.95)
		)
	)

	menu_root.add_child(
		_create_button(
			"MODE BERNI",
			"mode",
			MODE_BERNI,
			Vector3(0.65, 0.30, 0),
			Color(0.95, 0.65, 0.10)
		)
	)

	menu_root.add_child(
		_create_button(
			"FACILE",
			"difficulty",
			DIFF_EASY,
			Vector3(-0.85, -0.20, 0),
			Color(0.15, 0.80, 0.25)
		)
	)

	menu_root.add_child(
		_create_button(
			"NORMAL",
			"difficulty",
			DIFF_NORMAL,
			Vector3(0, -0.20, 0),
			Color(0.95, 0.75, 0.10)
		)
	)

	menu_root.add_child(
		_create_button(
			"DIFFICILE",
			"difficulty",
			DIFF_HARD,
			Vector3(0.85, -0.20, 0),
			Color(0.90, 0.20, 0.15)
		)
	)

	menu_status = Label3D.new()
	menu_status.name = "Status"
	menu_status.position = Vector3(0, -0.53, 0)
	menu_status.font_size = 32
	menu_status.outline_size = 7
	menu_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_root.add_child(menu_status)

	menu_root.add_child(
		_create_button(
			"LANCER",
			"start",
			"start",
			Vector3(0, -0.88, 0),
			Color(0.65, 0.20, 0.85)
		)
	)

	_update_menu_status()


func _create_button(
	button_text: String,
	button_type: String,
	value: String,
	pos: Vector3,
	color: Color
) -> Area3D:
	var area := Area3D.new()
	area.name = "%s_%s" % [button_type, value]
	area.position = pos
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = true
	area.monitorable = true
	area.set_meta("type", button_type)
	area.set_meta("value", value)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.72, 0.28, 0.15)
	collision.shape = shape
	area.add_child(collision)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.72, 0.28, 0.15)
	mesh.mesh = box

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.30
	mesh.material_override = material
	area.add_child(mesh)

	var label := Label3D.new()
	label.text = button_text
	label.position = Vector3(0, 0, 0.10)
	label.font_size = 38
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area.add_child(label)

	return area


func _create_shovel() -> Node3D:
	var root := Node3D.new()
	root.name = "BerniShovel"
	root.position = Vector3(0.06, -0.05, -0.30)
	root.rotation_degrees = Vector3(-65, 0, 0)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.18, 0.06)
	wood.roughness = 0.90

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.70, 0.72, 0.76)
	metal.metallic = 0.75
	metal.roughness = 0.25

	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.height = 0.80
	handle_mesh.top_radius = 0.018
	handle_mesh.bottom_radius = 0.018
	handle.mesh = handle_mesh
	handle.material_override = wood
	root.add_child(handle)

	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.22, 0.20, 0.035)
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0.48, 0)
	blade.material_override = metal
	root.add_child(blade)

	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 0
	hit_area.collision_mask = 1
	hit_area.monitoring = false
	hit_area.monitorable = false

	var hit_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.30, 0.24, 0.14)
	hit_shape.shape = box_shape
	hit_shape.position = Vector3(0, 0.48, 0)
	hit_area.add_child(hit_shape)

	root.add_child(hit_area)
	return root


func _load_beers() -> void:
	beer_scenes.clear()

	for path in [
		"res://assets/props/Bier1.glb",
		"res://assets/props/Bier2.glb"
	]:
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is PackedScene:
				beer_scenes.append(resource as PackedScene)


func _on_session_begun() -> void:
	_enable_passthrough()
	call_deferred("_show_menu_if_boot")


func _on_session_focussed() -> void:
	_enable_passthrough()
	call_deferred("_show_menu_if_boot")


func _show_menu_if_boot() -> void:
	if game_state != "boot":
		return

	await get_tree().create_timer(0.35).timeout

	if game_state == "boot":
		_show_menu()


func _enable_passthrough() -> void:
	if xr_interface == null:
		return

	var modes := xr_interface.get_supported_environment_blend_modes()

	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE


func _show_menu() -> void:
	game_state = "menu"
	game_over = false
	wave_transition_pending = false
	menu_input_locked = false
	run_serial += 1
	combo = 0
	exit_hold = 0.0
	hud_hint = ""

	_clear_tibos()

	shovel_root.visible = false
	shovel_hit_area.set_deferred("monitoring", false)

	left_hit_area.set_deferred("monitoring", true)
	right_hit_area.set_deferred("monitoring", true)

	health_hud.visible = false
	menu_root.visible = false

	_spawn_beers()
	_update_menu_status()


func _place_menu() -> void:
	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0

	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var menu_position := xr_camera.global_position + forward * 2.1
	menu_position.y = xr_camera.global_position.y - 0.25
	menu_root.global_position = menu_position

	var target := xr_camera.global_position
	target.y = menu_root.global_position.y
	menu_root.look_at(target, Vector3.UP)


func _on_menu_area_entered(area: Area3D) -> void:
	if game_state != "menu" or menu_input_locked:
		return

	if not area.has_meta("type"):
		return

	menu_input_locked = true

	var button_type := String(area.get_meta("type"))
	var value := String(area.get_meta("value"))

	if button_type == "mode":
		selected_mode = value
		_update_menu_status()
	elif button_type == "difficulty":
		selected_difficulty = value
		_update_menu_status()
	elif button_type == "start":
		_start_game()

	await get_tree().create_timer(0.25).timeout
	menu_input_locked = false


func _update_menu_status() -> void:
	if menu_status == null:
		return

	menu_status.text = "MODE : %s    DIFFICULTE : %s" % [
		selected_mode.to_upper(),
		selected_difficulty.to_upper()
	]


func _start_game() -> void:
	if game_state != "menu":
		return

	game_state = "playing"
	game_over = false
	wave_transition_pending = false
	run_serial += 1
	combo = 0
	exit_hold = 0.0

	GameAudio.play_sfx("start")

	hud_hint = "MENU (manette gauche) = accueil"
	_hide_hint_later(run_serial)

	menu_root.visible = false
	health_hud.visible = true

	player_health = player_max_health
	wave = 0
	wave_total = 0
	wave_spawned = 0
	wave_defeated = 0
	active_tibos = 0

	if selected_difficulty == DIFF_EASY:
		max_active_tibos = 1
	elif selected_difficulty == DIFF_NORMAL:
		max_active_tibos = 2
	else:
		max_active_tibos = 3

	var berni_enabled := selected_mode == MODE_BERNI
	shovel_root.visible = berni_enabled
	shovel_hit_area.set_deferred("monitoring", berni_enabled)

	left_hit_area.set_deferred("monitoring", true)
	right_hit_area.set_deferred("monitoring", not berni_enabled)

	_start_wave()


func _start_wave() -> void:
	if game_state != "playing" or game_over:
		return

	wave_transition_pending = false
	wave += 1

	if selected_difficulty == DIFF_EASY:
		wave_total = mini(2 + wave, 5)
	elif selected_difficulty == DIFF_NORMAL:
		wave_total = mini(3 + wave, 7)
	else:
		wave_total = mini(4 + wave, 9)

	wave_spawned = 0
	wave_defeated = 0
	active_tibos = 0

	_fill_active_slots()
	_update_hud()


func _fill_active_slots() -> void:
	if game_state != "playing" or game_over:
		return

	while active_tibos < max_active_tibos and wave_spawned < wave_total:
		_spawn_one_tibo()


func _spawn_one_tibo() -> void:
	var angle := randf() * TAU
	var distance := randf_range(3.2, 4.2)

	var center := xr_camera.global_position
	center.y = _floor_y()

	var spawn_position := center + Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)

	var tibo := TIBO_SCENE.instantiate() as TiboEnemy

	if selected_difficulty == DIFF_EASY:
		tibo.move_speed *= 0.80
		tibo.attack_damage = 6
		tibo.max_health = 75
	elif selected_difficulty == DIFF_NORMAL:
		tibo.attack_damage = 10
		tibo.max_health = 100
	else:
		tibo.move_speed *= 1.15
		tibo.attack_damage = 14
		tibo.max_health = 125

	tibo.position = enemy_root.to_local(spawn_position)
	enemy_root.add_child(tibo)

	tibo.player_hit.connect(_on_tibo_hit_player)
	tibo.defeated.connect(_on_tibo_defeated)

	wave_spawned += 1
	active_tibos += 1
	_update_hud()


func _physics_process(delta: float) -> void:
	_update_hand_speeds(delta)

	if game_state != "playing" or game_over:
		exit_hold = 0.0
		return

	_play_swing_sounds()
	_process_hits()
	_check_exit_hold(delta)


func _update_hand_speeds(delta: float) -> void:
	if delta <= 0.0:
		return

	_track_speed("left", left_hand.global_position, left_hand.get_is_active(), delta)
	_track_speed("right", right_hand.global_position, right_hand.get_is_active(), delta)

	if shovel_hit_area != null:
		_track_speed("shovel", shovel_hit_area.global_position, right_hand.get_is_active(), delta)


func _track_speed(key: String, pos: Vector3, active: bool, delta: float) -> void:
	if not active:
		hand_speed[key] = 0.0
		last_hand_pos.erase(key)
		return

	if last_hand_pos.has(key):
		var previous: Vector3 = last_hand_pos[key]
		var raw := minf(pos.distance_to(previous) / delta, 12.0)
		hand_speed[key] = lerpf(float(hand_speed[key]), raw, 0.6)

	last_hand_pos[key] = pos


func _hand_position(key: String) -> Vector3:
	if key == "left":
		return left_hand.global_position

	if key == "shovel" and shovel_hit_area != null:
		return shovel_hit_area.global_position

	return right_hand.global_position


func _play_swing_sounds() -> void:
	var now := Time.get_ticks_msec()

	for key in ["left", "right", "shovel"]:
		if key == "shovel" and selected_mode != MODE_BERNI:
			continue

		if key == "right" and selected_mode == MODE_BERNI:
			continue

		var speed: float = hand_speed[key]

		if speed >= WHOOSH_SPEED and now - int(last_whoosh_ms[key]) > 400:
			last_whoosh_ms[key] = now
			GameAudio.play_sfx("whoosh", _hand_position(key), clampf(speed - 8.0, -8.0, 0.0))


func _process_hits() -> void:
	if selected_mode == MODE_BERNI:
		_hit_with(shovel_hit_area, "shovel", shovel_damage, SHOVEL_MIN_SPEED, true)
		_hit_with(left_hit_area, "left", hand_damage, PUNCH_MIN_SPEED, false)
	else:
		_hit_with(left_hit_area, "left", hand_damage, PUNCH_MIN_SPEED, false)
		_hit_with(right_hit_area, "right", hand_damage, PUNCH_MIN_SPEED, false)


func _hit_with(area: Area3D, key: String, base_damage: int, min_speed: float, is_shovel: bool) -> void:
	if area == null or not area.monitoring:
		return

	var speed: float = hand_speed[key]

	if speed < min_speed:
		return

	for body in area.get_overlapping_bodies():
		if not body is TiboEnemy:
			continue

		var enemy := body as TiboEnemy

		if enemy.is_dead:
			continue

		var meta_key := "last_hit_" + key
		var now := Time.get_ticks_msec()

		if now - int(enemy.get_meta(meta_key, -10000)) < HIT_COOLDOWN_MS:
			continue

		enemy.set_meta(meta_key, now)
		_land_hit(enemy, key, area.global_position, base_damage, speed, is_shovel)


func _land_hit(
	enemy: TiboEnemy,
	key: String,
	hit_pos: Vector3,
	base_damage: int,
	speed: float,
	is_shovel: bool
) -> void:
	var power := clampf(speed / 3.0, 0.5, 1.6)
	var damage := maxi(1, int(round(base_damage * power)))
	var strong := power >= 1.15

	enemy.take_hit(damage, power)

	CombatFX.hit_effect(hit_pos, damage, strong, is_shovel)

	if is_shovel:
		GameAudio.play_sfx("shovel", hit_pos)
	elif strong:
		GameAudio.play_sfx("punch_strong", hit_pos)
	else:
		GameAudio.play_sfx("punch", hit_pos, -2.0)

	var controller: XRController3D = left_hand if key == "left" else right_hand
	var amplitude := clampf(0.35 + 0.45 * power, 0.0, 1.0)
	var duration := 0.06 + 0.06 * power
	controller.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)

	_register_combo()


func _register_combo() -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if now - last_hit_time <= COMBO_WINDOW:
		combo += 1
	else:
		combo = 1

	last_hit_time = now

	if combo >= 2:
		GameFeedback.show_combo(combo)

	if combo >= 3:
		GameAudio.play_sfx("combo", null, -4.0, 1.0 + minf(combo, 8) * 0.04)


func _check_exit_hold(delta: float) -> void:
	var both_pressed := (
		left_hand.get_is_active()
		and right_hand.get_is_active()
		and left_hand.is_button_pressed("ax_button")
		and right_hand.is_button_pressed("ax_button")
	)

	if both_pressed:
		exit_hold += delta
		health_hud.text = "RETOUR ACCUEIL %d%%" % mini(100, int(exit_hold / EXIT_HOLD * 100.0))

		if exit_hold >= EXIT_HOLD:
			exit_hold = 0.0
			_go_home()
	elif exit_hold > 0.0:
		exit_hold = 0.0
		_update_hud()


func _on_controller_button(button_name: String) -> void:
	if button_name == "menu_button":
		_go_home()


func _go_home() -> void:
	if game_state != "playing" and game_state != "game_over":
		return

	GameAudio.play_sfx("back")
	_show_menu()


func _hide_hint_later(serial: int) -> void:
	await get_tree().create_timer(7.0).timeout

	if serial == run_serial and hud_hint != "":
		hud_hint = ""

		if game_state == "playing" and not game_over:
			_update_hud()


func _on_tibo_hit_player(damage: int) -> void:
	if game_state != "playing" or game_over:
		return

	player_health = max(0, player_health - damage)
	combo = 0
	_update_hud()

	GameAudio.play_sfx("hurt")
	CombatFX.player_hurt(damage)

	if player_health <= 0:
		call_deferred("_game_over")


func _on_tibo_defeated(_tibo: Node) -> void:
	if game_state != "playing":
		return

	active_tibos = max(0, active_tibos - 1)
	wave_defeated += 1
	_update_hud()

	if wave_defeated >= wave_total:
		if not wave_transition_pending:
			wave_transition_pending = true
			call_deferred("_next_wave_after_pause")
	else:
		call_deferred("_replacement_after_pause")


func _replacement_after_pause() -> void:
	var serial := run_serial
	await get_tree().create_timer(0.75).timeout

	if serial == run_serial and game_state == "playing" and not game_over:
		_fill_active_slots()


func _next_wave_after_pause() -> void:
	var serial := run_serial
	await get_tree().create_timer(1.75).timeout

	if serial == run_serial and game_state == "playing" and not game_over:
		_start_wave()


func _game_over() -> void:
	if game_over:
		return

	game_over = true
	game_state = "game_over"

	shovel_hit_area.set_deferred("monitoring", false)
	left_hit_area.set_deferred("monitoring", false)
	right_hit_area.set_deferred("monitoring", false)

	_clear_tibos()

	health_hud.visible = true
	health_hud.text = "LES TIBO T'ONT EU !\nRetour au menu..."
	GameAudio.play_sfx("gameover")

	var serial := run_serial
	await get_tree().create_timer(3.0).timeout

	if serial == run_serial and game_state == "game_over":
		_show_menu()


func _spawn_beers() -> void:
	for child in prop_root.get_children():
		child.queue_free()

	if beer_scenes.is_empty():
		return

	var center := xr_camera.global_position
	var floor_y := _floor_y()

	for i in range(8):
		var packed := beer_scenes[randi() % beer_scenes.size()]
		var beer := packed.instantiate()

		if not beer is Node3D:
			continue

		prop_root.add_child(beer)

		var beer_node := beer as Node3D
		var angle := randf() * TAU
		var distance := randf_range(1.0, 3.5)

		beer_node.global_position = Vector3(
			center.x + cos(angle) * distance,
			floor_y + 0.04,
			center.z + sin(angle) * distance
		)

		beer_node.rotation = Vector3(
			randf_range(-0.20, 1.10),
			randf() * TAU,
			randf_range(-1.10, 1.10)
		)

		beer_node.scale = Vector3.ONE * 0.22


func _floor_y() -> float:
	var origin_y := xr_origin.global_position.y
	var head_height := xr_camera.global_position.y - origin_y

	if head_height > 0.9 and head_height < 2.3:
		return origin_y

	return xr_camera.global_position.y - 1.65


func _clear_tibos() -> void:
	for child in enemy_root.get_children():
		child.queue_free()

	active_tibos = 0


func _update_hud() -> void:
	if health_hud == null:
		return

	var remaining: int = maxi(0, wave_total - wave_defeated)

	var hud_text := "VIE %d   VAGUE %d   RESTE %d" % [
		player_health,
		wave,
		remaining
	]

	if hud_hint != "":
		hud_text += "\n" + hud_hint

	health_hud.text = hud_text
