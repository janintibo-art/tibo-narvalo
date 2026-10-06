extends Node

const MODE_BERNI := "berni"

var main: Node
var xr_camera: XRCamera3D
var right_hand: XRController3D

var arsenal_root: Node3D
var weapon_label: Label3D
var weapons: Array[Node3D] = []
var hit_areas: Array[Area3D] = []
var weapon_names: Array[String] = ["PELLE", "BATTE", "POELE", "BALAI"]
var weapon_damage: Array[int] = [100, 85, 110, 65]

var current_index := -1
var current_damage := 100
var last_wave := -1
var last_state := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_try_bind")


func _process(_delta: float) -> void:
	_try_bind()

	if main == null or arsenal_root == null:
		return

	var state_value = main.get("game_state")
	var mode_value = main.get("selected_mode")
	var wave_value = main.get("wave")

	if state_value == null or mode_value == null:
		return

	var state := String(state_value)
	var mode := String(mode_value)
	var berni_active := state == "playing" and mode == MODE_BERNI

	_disable_legacy_shovel()

	arsenal_root.visible = berni_active

	if weapon_label:
		weapon_label.visible = berni_active

	if not berni_active:
		_set_all_hits(false)
		last_state = state
		return

	var current_wave := 1
	if wave_value != null:
		current_wave = maxi(1, int(wave_value))

	if last_state != "playing" or current_wave != last_wave:
		_select_weapon((current_wave - 1) % weapon_names.size())
		last_wave = current_wave

	last_state = state


func _try_bind() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	main = current_scene

	if not is_instance_valid(xr_camera):
		xr_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D

	if xr_camera == null:
		return

	if right_hand == null:
		right_hand = xr_camera.get_parent().get_node_or_null("RightHand") as XRController3D

	if right_hand == null:
		return

	if arsenal_root == null:
		_build_arsenal()


func _build_arsenal() -> void:
	arsenal_root = Node3D.new()
	arsenal_root.name = "BerniArsenal"
	arsenal_root.position = Vector3(0.10, -0.08, -0.28)
	arsenal_root.rotation_degrees = Vector3(-58, -10, 28)
	right_hand.add_child(arsenal_root)

	weapons.append(_make_shovel())
	weapons.append(_make_bat())
	weapons.append(_make_pan())
	weapons.append(_make_broom())

	for weapon in weapons:
		weapon.visible = false
		arsenal_root.add_child(weapon)

		var hit_area := weapon.get_node("HitArea") as Area3D
		hit_area.body_entered.connect(_on_weapon_body_entered)
		hit_area.monitoring = false
		hit_areas.append(hit_area)

	weapon_label = Label3D.new()
	weapon_label.name = "BerniWeaponLabel"
	weapon_label.position = Vector3(-0.62, -0.46, -1.35)
	weapon_label.font_size = 30
	weapon_label.pixel_size = 0.0025
	weapon_label.outline_size = 7
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.visible = false
	xr_camera.add_child(weapon_label)

	arsenal_root.visible = false


func _disable_legacy_shovel() -> void:
	if main == null:
		return

	var legacy_shovel = main.get("shovel_root")
	if legacy_shovel is Node3D:
		(legacy_shovel as Node3D).visible = false

	var legacy_hit = main.get("shovel_hit_area")
	if legacy_hit is Area3D:
		(legacy_hit as Area3D).set_deferred("monitoring", false)


func _select_weapon(index: int) -> void:
	if weapons.is_empty():
		return

	current_index = clampi(index, 0, weapons.size() - 1)
	current_damage = weapon_damage[current_index]

	for i in range(weapons.size()):
		weapons[i].visible = i == current_index
		hit_areas[i].set_deferred("monitoring", i == current_index)

	if weapon_label:
		weapon_label.text = "BERNI : %s\n%d DEGATS" % [
			weapon_names[current_index],
			current_damage
		]

	if right_hand:
		right_hand.trigger_haptic_pulse("haptic", 0.0, 0.45, 0.10, 0.0)


func _set_all_hits(enabled: bool) -> void:
	for i in range(hit_areas.size()):
		var should_enable := enabled and current_index >= 0 and i == current_index
		hit_areas[i].set_deferred("monitoring", should_enable)


func _on_weapon_body_entered(body: Node3D) -> void:
	if main == null:
		return

	var state_value = main.get("game_state")
	var mode_value = main.get("selected_mode")

	if state_value == null or mode_value == null:
		return

	if String(state_value) != "playing" or String(mode_value) != MODE_BERNI:
		return

	if not body.is_in_group("tibo"):
		return

	if not body.has_method("take_hit"):
		return

	body.call("take_hit", current_damage)

	if right_hand:
		var amplitude := 0.70
		var duration := 0.10

		if current_damage >= 100:
			amplitude = 1.0
			duration = 0.14

		right_hand.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


func _make_shovel() -> Node3D:
	var root := Node3D.new()
	root.name = "Pelle"

	var wood := _material(Color(0.42, 0.25, 0.10), 0.0, 0.92)
	var metal := _material(Color(0.72, 0.74, 0.78), 0.78, 0.22)
	var dark := _material(Color(0.25, 0.27, 0.30), 0.72, 0.28)

	root.add_child(_cylinder_part(Vector3(0, 0, 0), 0.84, 0.017, 0.017, wood))
	root.add_child(_box_part(Vector3(-0.06, -0.46, 0), Vector3(0.024, 0.12, 0.024), wood))
	root.add_child(_box_part(Vector3(0.06, -0.46, 0), Vector3(0.024, 0.12, 0.024), wood))
	root.add_child(_box_part(Vector3(0, -0.515, 0), Vector3(0.15, 0.025, 0.025), wood))
	root.add_child(_cylinder_part(Vector3(0, 0.40, 0), 0.10, 0.027, 0.022, dark))
	root.add_child(_box_part(Vector3(0, 0.53, 0), Vector3(0.19, 0.16, 0.036), metal))
	root.add_child(_box_part(Vector3(0, 0.65, 0), Vector3(0.14, 0.15, 0.032), metal, Vector3(0, 0, 8)))
	root.add_child(_box_part(Vector3(0, 0.75, 0), Vector3(0.08, 0.12, 0.026), metal, Vector3(0, 0, 16)))

	root.add_child(_make_hit_area(Vector3(0, 0.61, 0), Vector3(0.31, 0.34, 0.16)))
	return root


func _make_bat() -> Node3D:
	var root := Node3D.new()
	root.name = "Batte"

	var wood := _material(Color(0.55, 0.30, 0.09), 0.0, 0.72)
	var grip := _material(Color(0.08, 0.08, 0.09), 0.10, 0.70)

	root.add_child(_cylinder_part(Vector3(0, 0.06, 0), 0.78, 0.052, 0.025, wood))
	root.add_child(_cylinder_part(Vector3(0, -0.39, 0), 0.18, 0.029, 0.029, grip))
	root.add_child(_cylinder_part(Vector3(0, -0.50, 0), 0.04, 0.036, 0.036, wood))

	root.add_child(_make_hit_area(Vector3(0, 0.24, 0), Vector3(0.18, 0.58, 0.18)))
	return root


func _make_pan() -> Node3D:
	var root := Node3D.new()
	root.name = "Poele"

	var metal := _material(Color(0.22, 0.24, 0.27), 0.82, 0.24)
	var edge := _material(Color(0.08, 0.09, 0.10), 0.70, 0.30)
	var grip := _material(Color(0.05, 0.05, 0.06), 0.05, 0.78)

	root.add_child(_cylinder_part(Vector3(0, -0.16, 0), 0.48, 0.022, 0.022, grip))

	var pan_head := MeshInstance3D.new()
	var pan_mesh := CylinderMesh.new()
	pan_mesh.height = 0.045
	pan_mesh.top_radius = 0.15
	pan_mesh.bottom_radius = 0.15
	pan_head.mesh = pan_mesh
	pan_head.position = Vector3(0, 0.20, 0)
	pan_head.rotation_degrees = Vector3(90, 0, 0)
	pan_head.material_override = metal
	root.add_child(pan_head)

	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.height = 0.060
	rim_mesh.top_radius = 0.165
	rim_mesh.bottom_radius = 0.165
	rim.mesh = rim_mesh
	rim.position = Vector3(0, 0.20, -0.01)
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.material_override = edge
	root.add_child(rim)

	root.add_child(_make_hit_area(Vector3(0, 0.20, 0), Vector3(0.38, 0.38, 0.16)))
	return root


func _make_broom() -> Node3D:
	var root := Node3D.new()
	root.name = "Balai"

	var wood := _material(Color(0.46, 0.28, 0.11), 0.0, 0.90)
	var bristle := _material(Color(0.68, 0.53, 0.25), 0.0, 0.96)
	var band := _material(Color(0.24, 0.26, 0.29), 0.68, 0.30)

	root.add_child(_cylinder_part(Vector3(0, -0.02, 0), 0.92, 0.016, 0.016, wood))
	root.add_child(_box_part(Vector3(0, 0.47, 0), Vector3(0.27, 0.055, 0.09), band))
	root.add_child(_box_part(Vector3(0, 0.56, 0), Vector3(0.31, 0.15, 0.11), bristle))

	root.add_child(_make_hit_area(Vector3(0, 0.53, 0), Vector3(0.36, 0.24, 0.18)))
	return root


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _box_part(pos: Vector3, size: Vector3, mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rotation_deg
	mesh_instance.material_override = mat
	return mesh_instance


func _cylinder_part(pos: Vector3, height: float, top_radius: float, bottom_radius: float, mat: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = height
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	mesh_instance.mesh = cylinder
	mesh_instance.position = pos
	mesh_instance.material_override = mat
	return mesh_instance


func _make_hit_area(pos: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = "HitArea"
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = false
	area.monitorable = false

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	area.add_child(shape_node)

	return area
