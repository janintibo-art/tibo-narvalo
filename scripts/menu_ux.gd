extends Node

const MODE_COMBAT := "combat"
const MODE_BERNI := "berni"

const DIFF_EASY := "facile"
const DIFF_NORMAL := "normal"
const DIFF_HARD := "difficile"

const MENU_DISTANCE := 1.45
const MENU_RECENTER_ANGLE := 65.0
const GAZE_DWELL := 1.2
const LASER_MAX := 4.0

var main: Node
var xr_camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D

var ui_root: Node3D
var status_label: Label3D
var title_label: Label3D
var anim_time := 0.0
var instruction_label: Label3D
var reticle: Label3D

var left_laser: Node3D
var right_laser: Node3D
var left_was_pressed := false
var right_was_pressed := false

var buttons: Array[Area3D] = []
var selected_mode := MODE_COMBAT
var selected_difficulty := DIFF_EASY

var hover_target: Area3D
var gaze_target: Area3D
var gaze_hold := 0.0
var activate_cooldown := 0.0
var was_menu := false

const END_DELAY := 1.2

var end_root: Node3D
var end_buttons: Array[Area3D] = []
var end_record_flag: Label3D
var end_score_label: Label3D
var end_stats_label: Label3D
var end_hint_label: Label3D
var was_end := false
var was_end_visible := false
var end_timer := 0.0
var end_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_try_bind")


func _process(delta: float) -> void:
	_try_bind()

	if main == null or xr_camera == null or ui_root == null or end_root == null:
		return

	var state_value = main.get("game_state")
	if state_value == null:
		return

	var state := String(state_value)
	var menu_active := state == "menu"
	var end_active := state == "game_over"

	if menu_active and not was_menu:
		_on_menu_opened()

	if end_active and not was_end:
		_on_end_opened()

	if end_active:
		end_timer = maxf(0.0, end_timer - delta)

	end_visible = end_active and end_timer <= 0.0

	if end_visible and not was_end_visible:
		_show_end_panel()

	ui_root.visible = menu_active
	end_root.visible = end_visible

	if reticle:
		reticle.visible = menu_active or end_visible

	anim_time += delta

	if menu_active and title_label != null:
		var pulse := 1.0 + 0.025 * sin(anim_time * 2.2)
		title_label.scale = Vector3(pulse, pulse, 1.0)

	if menu_active or end_visible:
		_hide_legacy_menu()
		_recenter_if_lost()
		_update_interaction(delta)
	else:
		_set_laser(left_laser, false, 0.0)
		_set_laser(right_laser, false, 0.0)
		_reset_hover()
		left_was_pressed = false
		right_was_pressed = false

	was_menu = menu_active
	was_end = end_active
	was_end_visible = end_visible


func _try_bind() -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	if main != current_scene:
		main = current_scene

	if not is_instance_valid(xr_camera):
		xr_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D

	if xr_camera == null:
		return

	if left_hand == null:
		left_hand = xr_camera.get_parent().get_node_or_null("LeftHand") as XRController3D

	if right_hand == null:
		right_hand = xr_camera.get_parent().get_node_or_null("RightHand") as XRController3D

	if ui_root == null:
		_build_ui()

	if end_root == null:
		_build_end_ui()

	if left_laser == null and left_hand:
		left_laser = _create_laser(Color(0.20, 0.80, 1.0))
		left_hand.add_child(left_laser)

	if right_laser == null and right_hand:
		right_laser = _create_laser(Color(1.0, 0.65, 0.15))
		right_hand.add_child(right_laser)

	if reticle == null:
		reticle = Label3D.new()
		reticle.name = "MenuReticle"
		reticle.text = "+"
		reticle.position = Vector3(0, 0, -1.0)
		reticle.font_size = 56
		reticle.pixel_size = 0.00075
		reticle.outline_size = 10
		reticle.no_depth_test = true
		reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reticle.visible = false
		xr_camera.add_child(reticle)


func _build_ui() -> void:
	ui_root = Node3D.new()
	ui_root.name = "PolishedMenu"
	get_tree().current_scene.add_child(ui_root)
	ui_root.visible = false

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(2.05, 1.52, 0.035)
	panel.mesh = panel_mesh

	var panel_mat := StandardMaterial3D.new()
	panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel_mat.albedo_color = Color(1, 1, 1, 0.92)
	panel_mat.albedo_texture = _gradient_texture(Color(0.03, 0.10, 0.20), Color(0.14, 0.05, 0.22))
	panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = panel_mat
	ui_root.add_child(panel)

	_add_bar(Vector3(0, 0.71, 0.025), Vector3(1.92, 0.025, 0.025), Color(0.15, 0.65, 1.0))
	_add_bar(Vector3(0, -0.71, 0.025), Vector3(1.92, 0.025, 0.025), Color(1.0, 0.56, 0.10))
	_add_bar(Vector3(-0.985, 0, 0.025), Vector3(0.025, 1.40, 0.025), Color(0.15, 0.65, 1.0))
	_add_bar(Vector3(0.985, 0, 0.025), Vector3(0.025, 1.40, 0.025), Color(1.0, 0.56, 0.10))
	_add_bar(Vector3(0, 0.34, 0.03), Vector3(1.80, 0.006, 0.01), Color(0.35, 0.45, 0.65))

	var title_shadow := _make_label("TIBO NARVALO", Vector3(0.012, 0.548, 0.030), 64, 0.0022)
	title_shadow.modulate = Color(0, 0, 0, 0.7)
	title_shadow.outline_size = 0
	ui_root.add_child(title_shadow)

	var title := _make_label("TIBO NARVALO", Vector3(0, 0.56, 0.035), 64, 0.0022)
	title.outline_size = 18
	title.modulate = Color(1.0, 0.93, 0.62)
	title.outline_modulate = Color(0.45, 0.15, 0.02, 1.0)
	ui_root.add_child(title)
	title_label = title

	ui_root.add_child(_make_label("REALITE MIXTE - QUEST 3", Vector3(0, 0.43, 0.035), 32, 0.0018))
	ui_root.add_child(_make_label("MODE", Vector3(-0.72, 0.27, 0.035), 30, 0.0018))
	ui_root.add_child(_make_label("DIFFICULTE", Vector3(0.47, 0.27, 0.035), 30, 0.0018))

	_add_button("COMBAT", "mode", MODE_COMBAT, Vector3(-0.72, 0.08, 0.055), Vector3(0.76, 0.24, 0.07), Color(0.10, 0.45, 0.85))
	_add_button("MODE BERNI", "mode", MODE_BERNI, Vector3(-0.72, -0.22, 0.055), Vector3(0.76, 0.24, 0.07), Color(0.82, 0.47, 0.08))
	_add_button("FACILE", "difficulty", DIFF_EASY, Vector3(0.47, 0.12, 0.055), Vector3(0.72, 0.20, 0.07), Color(0.10, 0.60, 0.22))
	_add_button("NORMAL", "difficulty", DIFF_NORMAL, Vector3(0.47, -0.12, 0.055), Vector3(0.72, 0.20, 0.07), Color(0.78, 0.62, 0.08))
	_add_button("DIFFICILE", "difficulty", DIFF_HARD, Vector3(0.47, -0.36, 0.055), Vector3(0.72, 0.20, 0.07), Color(0.72, 0.12, 0.10))

	status_label = _make_label("", Vector3(-0.72, -0.47, 0.04), 26, 0.0017)
	ui_root.add_child(status_label)

	instruction_label = _make_label("", Vector3(0.47, -0.55, 0.04), 24, 0.0016)
	ui_root.add_child(instruction_label)

	_add_button("LANCER", "start", "start", Vector3(0, -0.60, 0.06), Vector3(0.62, 0.18, 0.08), Color(0.48, 0.15, 0.78))

	_refresh_selection()
	_update_instruction()


func _build_end_ui() -> void:
	end_root = Node3D.new()
	end_root.name = "EndScreen"
	get_tree().current_scene.add_child(end_root)
	end_root.visible = false

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(2.05, 1.52, 0.035)
	panel.mesh = panel_mesh

	var panel_mat := StandardMaterial3D.new()
	panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel_mat.albedo_color = Color(1, 1, 1, 0.93)
	panel_mat.albedo_texture = _gradient_texture(Color(0.20, 0.04, 0.05), Color(0.08, 0.03, 0.14))
	panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = panel_mat
	end_root.add_child(panel)

	_add_bar(Vector3(0, 0.71, 0.025), Vector3(1.92, 0.025, 0.025), Color(1.0, 0.25, 0.20), end_root)
	_add_bar(Vector3(0, -0.71, 0.025), Vector3(1.92, 0.025, 0.025), Color(1.0, 0.56, 0.10), end_root)

	_add_bar(Vector3(-0.985, 0, 0.025), Vector3(0.025, 1.40, 0.025), Color(1.0, 0.25, 0.20), end_root)
	_add_bar(Vector3(0.985, 0, 0.025), Vector3(0.025, 1.40, 0.025), Color(1.0, 0.56, 0.10), end_root)

	var title := _make_label("PARTIE TERMINEE", Vector3(0, 0.56, 0.035), 64, 0.0022)
	title.outline_size = 18
	title.modulate = Color(1.0, 0.85, 0.80)
	title.outline_modulate = Color(0.35, 0.02, 0.02, 1.0)
	end_root.add_child(title)

	end_record_flag = _make_label("NOUVEAU RECORD !", Vector3(0, 0.40, 0.035), 44, 0.0019)
	end_record_flag.modulate = Color(1.0, 0.85, 0.2)
	end_record_flag.visible = false
	end_root.add_child(end_record_flag)

	end_score_label = _make_label("", Vector3(0, 0.19, 0.035), 90, 0.0024)
	end_root.add_child(end_score_label)

	end_stats_label = _make_label("", Vector3(0, -0.12, 0.035), 32, 0.0018)
	end_root.add_child(end_stats_label)

	end_hint_label = _make_label("", Vector3(0, -0.645, 0.04), 20, 0.0015)
	end_root.add_child(end_hint_label)

	var replay := _make_button("REJOUER", "replay", "replay", Vector3(-0.5, -0.46, 0.055), Vector3(0.8, 0.22, 0.07), Color(0.10, 0.60, 0.22))
	end_root.add_child(replay)
	end_buttons.append(replay)

	var home := _make_button("ACCUEIL", "home", "home", Vector3(0.5, -0.46, 0.055), Vector3(0.8, 0.22, 0.07), Color(0.10, 0.45, 0.85))
	end_root.add_child(home)
	end_buttons.append(home)

	for button in end_buttons:
		var mesh := button.get_node_or_null("Mesh") as MeshInstance3D

		if mesh and mesh.material_override is StandardMaterial3D:
			var material := mesh.material_override as StandardMaterial3D
			material.albedo_color = (button.get_meta("base_color") as Color).lightened(0.15)


func _gradient_texture(top: Color, bottom: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = 128
	return texture


func _add_bar(pos: Vector3, size: Vector3, color: Color, root: Node3D = null) -> void:
	var parent := root if root != null else ui_root
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	parent.add_child(mesh)


func _make_label(text_value: String, pos: Vector3, size: int, px: float) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = size * 2
	label.pixel_size = px * 0.5
	label.outline_size = 12
	label.outline_modulate = Color(0.02, 0.04, 0.10, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _add_button(
	text_value: String,
	button_type: String,
	value: String,
	pos: Vector3,
	size: Vector3,
	color: Color
) -> void:
	var area := _make_button(text_value, button_type, value, pos, size, color)
	ui_root.add_child(area)
	buttons.append(area)


func _make_button(
	text_value: String,
	button_type: String,
	value: String,
	pos: Vector3,
	size: Vector3,
	color: Color
) -> Area3D:
	var area := Area3D.new()
	area.name = "%s_%s" % [button_type, value]
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta("type", button_type)
	area.set_meta("value", value)
	area.set_meta("base_color", color)
	area.set_meta("button_size", size)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mesh.material_override = mat
	area.add_child(mesh)

	var label := _make_label(text_value, Vector3(0, 0, size.z * 0.52 + 0.004), 34, 0.0019)
	label.outline_size = 10
	area.add_child(label)

	return area


func _create_laser(color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "MenuLaser"
	pivot.visible = false

	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cylinder := CylinderMesh.new()
	cylinder.height = 1.0
	cylinder.top_radius = 0.0035
	cylinder.bottom_radius = 0.0035
	cylinder.radial_segments = 6
	cylinder.rings = 1
	beam.mesh = cylinder
	beam.position = Vector3(0, 0, -0.5)
	beam.rotation_degrees = Vector3(90, 0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	pivot.add_child(beam)

	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var sphere := SphereMesh.new()
	sphere.radius = 0.018
	sphere.height = 0.036
	dot.mesh = sphere
	dot.material_override = mat
	pivot.add_child(dot)

	return pivot


func _set_laser(laser: Node3D, visible_value: bool, length: float) -> void:
	if laser == null:
		return

	laser.visible = visible_value

	if not visible_value:
		return

	var beam := laser.get_node("Beam") as Node3D
	var dot := laser.get_node("Dot") as Node3D
	var safe_length := maxf(length, 0.01)

	beam.scale = Vector3(1, safe_length, 1)
	beam.position = Vector3(0, 0, -safe_length * 0.5)
	dot.position = Vector3(0, 0, -safe_length)


func _on_menu_opened() -> void:
	var mode_value = main.get("selected_mode")
	var diff_value = main.get("selected_difficulty")

	if mode_value != null:
		selected_mode = String(mode_value)

	if diff_value != null:
		selected_difficulty = String(diff_value)

	_refresh_selection()
	_hide_legacy_menu()
	_place_menu()
	activate_cooldown = 0.6


func _hide_legacy_menu() -> void:
	if main == null:
		return

	var legacy := main.get_node_or_null("MainMenu") as Node3D

	if legacy == null:
		return

	legacy.visible = false
	_disable_legacy_areas(legacy)


func _disable_legacy_areas(node: Node) -> void:
	if node is Area3D:
		var area := node as Area3D
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false

	for child in node.get_children():
		_disable_legacy_areas(child)


func _flat_forward() -> Vector3:
	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0

	if forward.length_squared() < 0.01:
		return Vector3.FORWARD

	return forward.normalized()


func _active_root() -> Node3D:
	return end_root if end_visible else ui_root


func _active_buttons() -> Array[Area3D]:
	return end_buttons if end_visible else buttons


func _place_menu() -> void:
	var root := _active_root()

	if root == null or xr_camera == null:
		return

	var forward := _flat_forward()
	var target_position := xr_camera.global_position + forward * MENU_DISTANCE
	target_position.y = xr_camera.global_position.y - 0.12

	root.global_position = target_position

	var away := target_position + forward
	root.look_at(away, Vector3.UP)


func _on_end_opened() -> void:
	end_timer = END_DELAY
	activate_cooldown = END_DELAY + 1.0
	_fill_end_stats()


func _show_end_panel() -> void:
	_fill_end_stats()
	_place_menu()

	var hud = main.get("health_hud")

	if hud is Label3D:
		(hud as Label3D).visible = false

	var stats = main.get("end_stats")

	if stats is Dictionary and bool(stats.get("new_record", false)):
		GameAudio.play_sfx("record")


func _fill_end_stats() -> void:
	var stats = main.get("end_stats")

	if not stats is Dictionary:
		return

	var seconds := int(stats.get("seconds", 0))

	end_score_label.text = "SCORE  %d" % int(stats.get("score", 0))
	end_record_flag.visible = bool(stats.get("new_record", false))
	end_stats_label.text = "VAGUE %d     KO %d\nMEILLEUR COMBO x%d     DUREE %d:%02d\nRECORD : %d  (vague %d)" % [
		int(stats.get("wave", 0)),
		int(stats.get("kos", 0)),
		int(stats.get("best_combo", 0)),
		seconds / 60,
		seconds % 60,
		int(stats.get("record_score", 0)),
		int(stats.get("record_wave", 0))
	]


func _recenter_if_lost() -> void:
	var root := _active_root()
	var to_menu := root.global_position - xr_camera.global_position
	to_menu.y = 0.0

	if to_menu.length_squared() < 0.01:
		return

	var angle := rad_to_deg(_flat_forward().angle_to(to_menu.normalized()))

	if angle > MENU_RECENTER_ANGLE:
		_place_menu()


func _update_interaction(delta: float) -> void:
	activate_cooldown = maxf(0.0, activate_cooldown - delta)

	var left_result := _laser_hit(left_hand)
	var right_result := _laser_hit(right_hand)

	_set_laser(left_laser, left_hand != null, float(left_result.get("distance", LASER_MAX)))
	_set_laser(right_laser, right_hand != null, float(right_result.get("distance", LASER_MAX)))

	var left_button := left_result.get("button") as Area3D
	var right_button := right_result.get("button") as Area3D

	var left_pressed := _is_select_pressed(left_hand)
	var right_pressed := _is_select_pressed(right_hand)

	var pointed: Area3D = right_button if right_button != null else left_button

	if right_pressed and not right_was_pressed and right_button != null:
		_try_activate(right_button)
	elif left_pressed and not left_was_pressed and left_button != null:
		_try_activate(left_button)

	left_was_pressed = left_pressed
	right_was_pressed = right_pressed

	if pointed != null:
		_set_hover(pointed)
		gaze_target = null
		gaze_hold = 0.0
	else:
		var looked := _find_gaze_button()

		if looked != gaze_target:
			gaze_target = looked
			gaze_hold = 0.0

		if gaze_target != null:
			gaze_hold += delta

			if gaze_hold >= GAZE_DWELL:
				_try_activate(gaze_target)
				gaze_hold = 0.0

		_set_hover(gaze_target)

	_update_instruction()


func _is_select_pressed(controller: XRController3D) -> bool:
	if controller == null or not controller.get_is_active():
		return false

	if controller.is_button_pressed("trigger_click"):
		return true

	if controller.get_float("trigger") > 0.7:
		return true

	return controller.is_button_pressed("ax_button")


func _laser_hit(controller: XRController3D) -> Dictionary:
	var result := {"button": null, "distance": LASER_MAX}

	if controller == null or not controller.get_is_active():
		return result

	var origin := controller.global_position
	var direction := -controller.global_transform.basis.z.normalized()
	var best := LASER_MAX

	for button in _active_buttons():
		var size_value = button.get_meta("button_size")

		if not size_value is Vector3:
			continue

		var hit := _ray_box_distance(button, size_value as Vector3, origin, direction)

		if hit >= 0.0 and hit < best:
			best = hit
			result["button"] = button

	if result["button"] == null:
		var panel_hit := _ray_box_distance(_active_root(), Vector3(2.05, 1.52, 0.035), origin, direction)

		if panel_hit >= 0.0:
			best = panel_hit

	result["distance"] = best
	return result


func _ray_box_distance(node: Node3D, size: Vector3, origin: Vector3, direction: Vector3) -> float:
	var inv := node.global_transform.affine_inverse()
	var local_origin := inv * origin
	var local_dir := inv.basis * direction
	var half := size * 0.5

	var t_min := -INF
	var t_max := INF

	for axis in 3:
		var o: float = local_origin[axis]
		var d: float = local_dir[axis]
		var h: float = half[axis]

		if absf(d) < 0.000001:
			if o < -h or o > h:
				return -1.0
			continue

		var t1: float = (-h - o) / d
		var t2: float = (h - o) / d

		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap

		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)

		if t_min > t_max:
			return -1.0

	if t_max < 0.0:
		return -1.0

	var hit_local := local_origin + local_dir * maxf(t_min, 0.0)
	return origin.distance_to(node.global_transform * hit_local)


func _find_gaze_button() -> Area3D:
	if xr_camera == null:
		return null

	var forward := -xr_camera.global_transform.basis.z.normalized()
	var best_button: Area3D
	var best_dot := 0.990

	for button in _active_buttons():
		var to_button := button.global_position - xr_camera.global_position
		var distance := to_button.length()

		if distance < 0.5 or distance > 3.0:
			continue

		var alignment := forward.dot(to_button.normalized())

		if alignment > best_dot:
			best_dot = alignment
			best_button = button

	return best_button


func _set_hover(new_target: Area3D) -> void:
	if hover_target == new_target:
		return

	if is_instance_valid(hover_target):
		hover_target.scale = Vector3.ONE

	hover_target = new_target

	if hover_target:
		hover_target.scale = Vector3.ONE * 1.08

		if right_hand:
			right_hand.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.03, 0.0)


func _reset_hover() -> void:
	if is_instance_valid(hover_target):
		hover_target.scale = Vector3.ONE

	hover_target = null
	gaze_target = null
	gaze_hold = 0.0


func _update_instruction() -> void:
	if instruction_label == null:
		return

	var text_value := "Vise avec la manette\npuis appuie sur la gachette"

	if gaze_target != null and hover_target == gaze_target:
		var progress := mini(100, int((gaze_hold / GAZE_DWELL) * 100.0))
		text_value = "Selection %d%%" % progress

	instruction_label.text = text_value

	if end_hint_label:
		end_hint_label.text = text_value.replace("\n", " ")


func _try_activate(button: Area3D) -> void:
	if activate_cooldown > 0.0 or button == null:
		return

	activate_cooldown = 0.45
	_activate_button(button)


func _activate_button(button: Area3D) -> void:
	if main == null:
		return

	var button_type := String(button.get_meta("type"))
	var value := String(button.get_meta("value"))

	if right_hand:
		right_hand.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.08, 0.0)

	if button_type == "mode":
		selected_mode = value
		main.set("selected_mode", value)
		GameAudio.play_sfx("click")
		_refresh_selection()

	elif button_type == "difficulty":
		selected_difficulty = value
		main.set("selected_difficulty", value)
		GameAudio.play_sfx("click")
		_refresh_selection()

	elif button_type == "start":
		main.set("selected_mode", selected_mode)
		main.set("selected_difficulty", selected_difficulty)
		_reset_hover()
		main.call("_start_game")

	elif button_type == "replay":
		_reset_hover()
		main.call("_replay")

	elif button_type == "home":
		_reset_hover()
		main.call("_go_home")


func _refresh_selection() -> void:
	if status_label:
		var record := 0

		if main != null and main.has_method("get_record_score"):
			record = int(main.call("get_record_score", selected_mode, selected_difficulty))

		status_label.text = "MODE : %s\nDIFFICULTE : %s\nRECORD : %d" % [
			selected_mode.to_upper(),
			selected_difficulty.to_upper(),
			record
		]

	for button in buttons:
		var button_type := String(button.get_meta("type"))
		var value := String(button.get_meta("value"))
		var selected := false

		if button_type == "mode":
			selected = value == selected_mode
		elif button_type == "difficulty":
			selected = value == selected_difficulty

		var mesh := button.get_node_or_null("Mesh") as MeshInstance3D

		if mesh == null:
			continue

		var material := mesh.material_override as StandardMaterial3D

		if material == null:
			continue

		var base_color = button.get_meta("base_color")

		if not base_color is Color:
			continue

		var color := base_color as Color

		if selected:
			material.albedo_color = color.lightened(0.30)
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.9
		else:
			material.albedo_color = color.darkened(0.25)
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.3
