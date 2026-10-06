extends Node

const MODE_COMBAT := "combat"
const MODE_BERNI := "berni"
const DIFF_EASY := "facile"
const DIFF_NORMAL := "normal"
const DIFF_HARD := "difficile"
const BUTTON_MODE := "mode"
const BUTTON_DIFFICULTY := "difficulty"
const BUTTON_START := "start"
const LOGO_PATH := "res://assets/ui/logo.png"

var main: Node
var xr_camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var ui_root: Node3D
var status_label: Label3D
var instruction_label: Label3D
var description_label: Label3D
var reticle: Label3D
var left_marker: MeshInstance3D
var right_marker: MeshInstance3D
var buttons: Array[Area3D] = []
var selected_mode := MODE_COMBAT
var selected_difficulty := DIFF_EASY
var gaze_target: Area3D
var gaze_hold := 0.0
var activate_cooldown := 0.0
var was_menu := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_try_bind")


func _process(delta: float) -> void:
	_try_bind()
	if main == null or xr_camera == null or ui_root == null:
		return
	var state_value = main.get("game_state")
	if state_value == null:
		return
	var state := String(state_value)
	var menu_active := state == "menu"
	if menu_active and not was_menu:
		_on_menu_opened()
	ui_root.visible = menu_active
	if left_marker:
		left_marker.visible = menu_active
	if right_marker:
		right_marker.visible = menu_active
	if reticle:
		reticle.visible = menu_active
	if menu_active:
		_hide_legacy_menu()
		_place_menu()
		_update_interaction(delta)
	else:
		_reset_gaze()
	was_menu = menu_active


func _try_bind() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
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
	if left_marker == null and left_hand:
		left_marker = _create_hand_marker(Color(0.16, 0.80, 1.0))
		left_hand.add_child(left_marker)
	if right_marker == null and right_hand:
		right_marker = _create_hand_marker(Color(1.0, 0.58, 0.12))
		right_hand.add_child(right_marker)
	if reticle == null:
		reticle = Label3D.new()
		reticle.name = "MenuReticle"
		reticle.text = "+"
		reticle.position = Vector3(0, 0, -1.0)
		reticle.font_size = 30
		reticle.pixel_size = 0.0024
		reticle.outline_size = 7
		reticle.no_depth_test = true
		reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xr_camera.add_child(reticle)


func _build_ui() -> void:
	ui_root = Node3D.new()
	ui_root.name = "PolishedMenu"
	get_tree().current_scene.add_child(ui_root)
	ui_root.visible = false
	_build_logo()

	var subtitle := _make_label("REALITE MIXTE  •  QUEST 3", Vector3(0, 0.48, 0.08), 22, 0.0026)
	subtitle.modulate = Color(0.84, 0.93, 1.0)
	ui_root.add_child(subtitle)

	_add_card(Vector3(-0.53, 0.00, 0.005), Vector3(0.92, 0.76, 0.035), Color(0.025, 0.095, 0.17))
	_add_card(Vector3(0.53, 0.00, 0.005), Vector3(0.92, 0.76, 0.035), Color(0.17, 0.075, 0.025))
	_add_accent(Vector3(-0.53, 0.365, 0.035), Vector3(0.82, 0.018, 0.018), Color(0.18, 0.70, 1.0))
	_add_accent(Vector3(0.53, 0.365, 0.035), Vector3(0.82, 0.018, 0.018), Color(1.0, 0.58, 0.14))

	var mode_title := _make_label("MODE DE JEU", Vector3(-0.53, 0.26, 0.07), 23, 0.0026)
	mode_title.modulate = Color(0.82, 0.94, 1.0)
	ui_root.add_child(mode_title)
	var diff_title := _make_label("DIFFICULTE", Vector3(0.53, 0.26, 0.07), 23, 0.0026)
	diff_title.modulate = Color(1.0, 0.92, 0.80)
	ui_root.add_child(diff_title)

	_add_button("COMBAT", BUTTON_MODE, MODE_COMBAT, Vector3(-0.53, 0.08, 0.075), Vector3(0.72, 0.20, 0.07), Color(0.08, 0.48, 0.92))
	_add_button("MODE BERNI", BUTTON_MODE, MODE_BERNI, Vector3(-0.53, -0.18, 0.075), Vector3(0.72, 0.20, 0.07), Color(0.92, 0.46, 0.08))
	_add_button("FACILE", BUTTON_DIFFICULTY, DIFF_EASY, Vector3(0.53, 0.12, 0.075), Vector3(0.68, 0.17, 0.07), Color(0.08, 0.66, 0.24))
	_add_button("NORMAL", BUTTON_DIFFICULTY, DIFF_NORMAL, Vector3(0.53, -0.08, 0.075), Vector3(0.68, 0.17, 0.07), Color(0.90, 0.68, 0.06))
	_add_button("DIFFICILE", BUTTON_DIFFICULTY, DIFF_HARD, Vector3(0.53, -0.28, 0.075), Vector3(0.68, 0.17, 0.07), Color(0.82, 0.12, 0.13))

	status_label = _make_label("", Vector3(-0.48, -0.48, 0.07), 19, 0.00245)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui_root.add_child(status_label)
	description_label = _make_label("", Vector3(0.46, -0.48, 0.07), 18, 0.00245)
	ui_root.add_child(description_label)

	_add_button("LANCER LA PARTIE", BUTTON_START, "start", Vector3(0, -0.68, 0.085), Vector3(1.05, 0.22, 0.08), Color(0.50, 0.16, 0.86))
	instruction_label = _make_label("Regarde un bouton 1 seconde  •  ou touche-le", Vector3(0, -0.86, 0.07), 17, 0.00235)
	instruction_label.modulate = Color(0.86, 0.93, 1.0)
	ui_root.add_child(instruction_label)
	_refresh_selection()


func _build_logo() -> void:
	if not ResourceLoader.exists(LOGO_PATH):
		var fallback := _make_label("TIBO NARVALO", Vector3(0, 0.84, 0.08), 48, 0.0029)
		fallback.modulate = Color.WHITE
		ui_root.add_child(fallback)
		return
	var texture := load(LOGO_PATH)
	if not texture is Texture2D:
		return
	var logo := MeshInstance3D.new()
	logo.name = "GameLogo"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.12, 0.84)
	logo.mesh = quad
	logo.position = Vector3(0, 0.92, 0.09)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture as Texture2D
	material.albedo_color = Color.WHITE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 10
	logo.material_override = material
	ui_root.add_child(logo)


func _add_card(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 0.48
	mesh.material_override = mat
	ui_root.add_child(mesh)


func _add_accent(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	ui_root.add_child(mesh)


func _make_label(text_value: String, pos: Vector3, size: int, px: float) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = size
	label.pixel_size = px
	label.outline_size = 7
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _add_button(text_value: String, button_type: String, value: String, pos: Vector3, size: Vector3, color: Color) -> void:
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
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	area.add_child(shape_node)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.08
	mat.roughness = 0.28
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	area.add_child(mesh)
	var label := _make_label(text_value, Vector3(0, 0, size.z * 0.65), 24, 0.00255)
	label.outline_size = 6
	area.add_child(label)
	ui_root.add_child(area)
	buttons.append(area)


func _create_hand_marker(color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "MenuPointer"
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.050
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	marker.visible = false
	return marker


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


func _place_menu() -> void:
	if ui_root == null or xr_camera == null:
		return
	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var target_position := xr_camera.global_position + forward * 1.95
	target_position.y = xr_camera.global_position.y - 0.06
	ui_root.global_position = target_position
	var look_target := xr_camera.global_position
	look_target.y = target_position.y
	ui_root.look_at(look_target, Vector3.UP)


func _update_interaction(delta: float) -> void:
	activate_cooldown = maxf(0.0, activate_cooldown - delta)
	var touched := _find_touched_button()
	if touched != null:
		_set_gaze_target(touched)
		gaze_hold = 1.0
	else:
		var looked := _find_gaze_button()
		if looked != gaze_target:
			_set_gaze_target(looked)
			gaze_hold = 0.0
		if gaze_target != null:
			gaze_hold += delta
		else:
			gaze_hold = 0.0
	_update_dwell_feedback()
	if gaze_target != null and gaze_hold >= 0.90 and activate_cooldown <= 0.0:
		_activate_button(gaze_target)
		activate_cooldown = 0.55
		gaze_hold = 0.0


func _find_touched_button() -> Area3D:
	for button in buttons:
		if _controller_inside_button(left_hand, button):
			return button
		if _controller_inside_button(right_hand, button):
			return button
	return null


func _controller_inside_button(controller: XRController3D, button: Area3D) -> bool:
	if controller == null:
		return false
	var size_value = button.get_meta("button_size")
	if not size_value is Vector3:
		return false
	var size := size_value as Vector3
	var local := button.to_local(controller.global_position)
	return absf(local.x) <= size.x * 0.57 and absf(local.y) <= size.y * 0.74 and absf(local.z) <= 0.24


func _find_gaze_button() -> Area3D:
	if xr_camera == null:
		return null
	var forward := -xr_camera.global_transform.basis.z.normalized()
	var best_button: Area3D
	var best_dot := 0.982
	for button in buttons:
		var to_button := button.global_position - xr_camera.global_position
		var distance := to_button.length()
		if distance < 0.8 or distance > 3.0:
			continue
		var alignment := forward.dot(to_button.normalized())
		if alignment > best_dot:
			best_dot = alignment
			best_button = button
	return best_button


func _set_gaze_target(new_target: Area3D) -> void:
	if gaze_target == new_target:
		return
	if gaze_target:
		gaze_target.scale = Vector3.ONE
	gaze_target = new_target
	if gaze_target:
		gaze_target.scale = Vector3.ONE * 1.06


func _reset_gaze() -> void:
	if gaze_target:
		gaze_target.scale = Vector3.ONE
	gaze_target = null
	gaze_hold = 0.0


func _update_dwell_feedback() -> void:
	if instruction_label == null:
		return
	if gaze_target == null:
		instruction_label.text = "Regarde un bouton 1 seconde  •  ou touche-le"
		return
	var progress := mini(100, int((gaze_hold / 0.90) * 100.0))
	var value := String(gaze_target.get_meta("value")).to_upper()
	instruction_label.text = "%s  •  selection %d%%" % [value, progress]


func _activate_button(button: Area3D) -> void:
	if main == null:
		return
	var button_type := String(button.get_meta("type"))
	var value := String(button.get_meta("value"))
	if button_type == BUTTON_MODE:
		selected_mode = value
		main.set("selected_mode", value)
		_refresh_selection()
	elif button_type == BUTTON_DIFFICULTY:
		selected_difficulty = value
		main.set("selected_difficulty", value)
		_refresh_selection()
	elif button_type == BUTTON_START:
		main.set("selected_mode", selected_mode)
		main.set("selected_difficulty", selected_difficulty)
		main.call("_start_game")


func _refresh_selection() -> void:
	if status_label:
		status_label.text = "MODE : %s\nDIFFICULTE : %s" % [selected_mode.to_upper(), selected_difficulty.to_upper()]
	if description_label:
		description_label.text = _get_description_text()
	for button in buttons:
		var button_type := String(button.get_meta("type"))
		var value := String(button.get_meta("value"))
		var selected := false
		if button_type == BUTTON_MODE:
			selected = value == selected_mode
		elif button_type == BUTTON_DIFFICULTY:
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
			material.albedo_color = color.lightened(0.20)
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.82
		else:
			material.albedo_color = color
			material.emission_enabled = false


func _get_description_text() -> String:
	var mode_text := "Poings rapides"
	if selected_mode == MODE_BERNI:
		mode_text = "Arsenal Berni"
	var difficulty_text := "1 Tibo actif"
	if selected_difficulty == DIFF_NORMAL:
		difficulty_text = "2 Tibo actifs"
	elif selected_difficulty == DIFF_HARD:
		difficulty_text = "3 Tibo actifs"
	return "%s\n%s" % [mode_text, difficulty_text]
