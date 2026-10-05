extends Node

# Fleches rouges sur le bord de la vue : montrent d'ou viennent les Tibo (et les bouteilles)
# qui sont hors du champ de vision, surtout ceux qui arrivent dans le dos.

const MAX_ARROWS := 6
const HIDE_ANGLE := 50.0

var cam: XRCamera3D
var arrows: Array[MeshInstance3D] = []
var materials: Array[StandardMaterial3D] = []
var clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	clock += delta

	if not is_instance_valid(cam):
		cam = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D

		if cam == null:
			return

		_build_arrows()

	var main := get_tree().current_scene
	var playing := false

	if main:
		var state_value = main.get("game_state")
		playing = state_value != null and String(state_value) == "playing"

	if not playing:
		_hide_from(0)
		return

	var inverse := cam.global_transform.affine_inverse()
	var threats: Array[Dictionary] = []

	for node in get_tree().get_nodes_in_group("tibo"):
		var enemy := node as Node3D

		if enemy == null or enemy.get("is_dead") == true:
			continue

		threats.append(_make_threat(inverse * enemy.global_position, Color(1.0, 0.12, 0.08)))

	for node in get_tree().get_nodes_in_group("projectile"):
		var bottle := node as Node3D

		if bottle == null or bottle.get("deflected") == true:
			continue

		threats.append(_make_threat(inverse * bottle.global_position, Color(1.0, 0.85, 0.1)))

	threats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])

	var shown := 0

	for threat in threats:
		if shown >= MAX_ARROWS:
			break

		var angle: float = threat["angle"]

		if absf(rad_to_deg(angle)) < HIDE_ANGLE:
			continue

		var dist: float = threat["dist"]
		var arrow := arrows[shown]
		var material := materials[shown]
		var color: Color = threat["color"]

		arrow.visible = true
		arrow.position = Vector3(sin(angle) * 0.45, cos(angle) * 0.28, -1.0)
		arrow.rotation = Vector3(0, 0, -angle)
		arrow.scale = Vector3.ONE * lerpf(1.7, 0.8, clampf(dist / 4.0, 0.0, 1.0))

		var alpha := 0.75

		if dist < 2.2:
			alpha = 0.6 + 0.4 * sin(clock * 12.0)

		material.albedo_color = Color(color.r, color.g, color.b, clampf(alpha, 0.2, 1.0))
		shown += 1

	_hide_from(shown)


func _make_threat(local: Vector3, color: Color) -> Dictionary:
	return {
		"angle": atan2(local.x, -local.z),
		"dist": Vector2(local.x, local.z).length(),
		"color": color
	}


func _hide_from(index: int) -> void:
	for i in range(index, arrows.size()):
		arrows[i].visible = false


func _build_arrows() -> void:
	arrows.clear()
	materials.clear()

	for i in MAX_ARROWS:
		var arrow := MeshInstance3D.new()
		arrow.name = "ThreatArrow%d" % i

		var prism := PrismMesh.new()
		prism.size = Vector3(0.10, 0.12, 0.01)
		arrow.mesh = prism

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.render_priority = 90
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1, 0.1, 0.1, 0.8)
		arrow.material_override = material
		arrow.visible = false

		cam.add_child(arrow)
		arrows.append(arrow)
		materials.append(material)
