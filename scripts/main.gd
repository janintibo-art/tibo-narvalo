extends Node3D

const TIBO_SCENE := preload("res://scenes/Tibo.tscn")
const MODE_CLASSIC := "classic"
const MODE_BERNI := "berni"

@export var player_max_health: int = 100
@export var classic_hand_damage: int = 55
@export var berni_hand_damage: int = 100

var xr_interface: OpenXRInterface
var player_health: int = 100
var wave := 0
var active_tibos := 0
var game_over := false
var current_mode := MODE_CLASSIC
var state := "boot"
var menu_locked := false
var beer_scenes: Array[PackedScene] = []

@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var enemy_root: Node3D = $EnemyRoot

var prop_root: Node3D
var menu_root: Node3D
var health_hud: Label3D
var left_hit_area: Area3D
var right_hit_area: Area3D
var shovel_root: Node3D

func _ready() -> void:
randomize()
add_to_group("game_manager")

_ensure_runtime_nodes()
_load_beer_scenes()

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

if not left_hit_area.body_entered.is_connected(_on_left_hand_body_entered):
left_hit_area.body_entered.connect(_on_left_hand_body_entered)
if not right_hit_area.body_entered.is_connected(_on_right_hand_body_entered):
right_hit_area.body_entered.connect(_on_right_hand_body_entered)

if not left_hit_area.area_entered.is_connected(_on_left_hand_area_entered):
left_hit_area.area_entered.connect(_on_left_hand_area_entered)
if not right_hit_area.area_entered.is_connected(_on_right_hand_area_entered):
right_hit_area.area_entered.connect(_on_right_hand_area_entered)

call_deferred("_enable_passthrough")

func _ensure_runtime_nodes() -> void:
prop_root = get_node_or_null("PropRoot") as Node3D
if prop_root == null:
prop_root = Node3D.new()
prop_root.name = "PropRoot"
add_child(prop_root)

health_hud = xr_camera.get_node_or_null("HealthHUD") as Label3D
if health_hud == null:
health_hud = Label3D.new()
health_hud.name = "HealthHUD"
health_hud.position = Vector3(0, -0.30, -1.25)
health_hud.font_size = 54
health_hud.outline_size = 10
health_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
xr_camera.add_child(health_hud)

left_hit_area = _ensure_hit_area(left_hand, "LeftHitArea")
right_hit_area = _ensure_hit_area(right_hand, "RightHitArea")

shovel_root = right_hand.get_node_or_null("BerniShovel") as Node3D
if shovel_root == null:
shovel_root = _create_shovel()
right_hand.add_child(shovel_root)
shovel_root.visible = false

menu_root = get_node_or_null("MenuRoot") as Node3D
if menu_root == null:
menu_root = _create_menu()
add_child(menu_root)
menu_root.visible = false

func _ensure_hit_area(hand: XRController3D, node_name: String) -> Area3D:
var area := hand.get_node_or_null(node_name) as Area3D
if area == null:
area = Area3D.new()
area.name = node_name
area.collision_layer = 0
area.collision_mask = 3
area.monitoring = true
area.monitorable = true
hand.add_child(area)

var shape := CollisionShape3D.new()
shape.name = "CollisionShape3D"
var sphere := SphereShape3D.new()
sphere.radius = 0.14
shape.shape = sphere
area.add_child(shape)

return area

func _create_menu() -> Node3D:
var root := Node3D.new()
root.name = "MenuRoot"

var title := Label3D.new()
title.name = "Title"
title.text = "TIBO NARVALO"
title.position = Vector3(0, 0.95, 0)
title.font_size = 110
title.outline_size = 14
title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
root.add_child(title)

var subtitle := Label3D.new()
subtitle.name = "Subtitle"
subtitle.text = "Touche un bouton avec la main"
subtitle.position = Vector3(0, 0.56, 0)
subtitle.font_size = 48
subtitle.outline_size = 10
subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
root.add_child(subtitle)

var info := Label3D.new()
info.name = "Info"
info.text = "Mode Berni : pelle main droite + grosses baffes"
info.position = Vector3(0, -0.15, 0)
info.font_size = 34
info.outline_size = 8
info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
root.add_child(info)

root.add_child(_create_menu_button("JOUER", MODE_CLASSIC, Vector3(0, 0.20, 0), Color(0.16, 0.55, 0.95)))
root.add_child(_create_menu_button("MODE BERNI", MODE_BERNI, Vector3(0, -0.30, 0), Color(0.95, 0.72, 0.12)))

return root

func _create_menu_button(button_text: String, mode: String, pos: Vector3, color: Color) -> Area3D:
var area := Area3D.new()
area.name = "%sButton" % mode
area.position = pos
area.collision_layer = 2
area.collision_mask = 0
area.monitorable = true
area.monitoring = true
area.set_meta("mode", mode)

var shape := CollisionShape3D.new()
var box_shape := BoxShape3D.new()
box_shape.size = Vector3(1.15, 0.30, 0.18)
shape.shape = box_shape
area.add_child(shape)

var mesh_instance := MeshInstance3D.new()
var box_mesh := BoxMesh.new()
box_mesh.size = Vector3(1.15, 0.30, 0.18)
mesh_instance.mesh = box_mesh

var material := StandardMaterial3D.new()
material.albedo_color = color
material.roughness = 0.35
mesh_instance.material_override = material
area.add_child(mesh_instance)

var label := Label3D.new()
label.text = button_text
label.position = Vector3(0, 0, 0.12)
label.font_size = 44
label.outline_size = 8
label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
area.add_child(label)

return area

func _create_shovel() -> Node3D:
var root := Node3D.new()
root.name = "BerniShovel"
root.position = Vector3(0.10, -0.10, -0.18)
root.rotation_degrees = Vector3(0, 0, 35)

var wood_material := StandardMaterial3D.new()
wood_material.albedo_color = Color(0.40, 0.24, 0.10)
wood_material.roughness = 0.9

var metal_material := StandardMaterial3D.new()
metal_material.albedo_color = Color(0.65, 0.67, 0.72)
metal_material.metallic = 0.7
metal_material.roughness = 0.28

var handle := MeshInstance3D.new()
var handle_mesh := CylinderMesh.new()
handle_mesh.top_radius = 0.018
handle_mesh.bottom_radius = 0.018
handle_mesh.height = 0.72
handle.mesh = handle_mesh
handle.material_override = wood_material
root.add_child(handle)

var head := MeshInstance3D.new()
var head_mesh := BoxMesh.new()
head_mesh.size = Vector3(0.18, 0.12, 0.035)
head.mesh = head_mesh
head.position = Vector3(0, 0.35, 0)
head.material_override = metal_material
root.add_child(head)

var blade := MeshInstance3D.new()
var blade_mesh := BoxMesh.new()
blade_mesh.size = Vector3(0.13, 0.16, 0.028)
blade.mesh = blade_mesh
blade.position = Vector3(0, 0.45, 0)
blade.rotation_degrees = Vector3(0, 0, 12)
blade.material_override = metal_material
root.add_child(blade)

return root

func _load_beer_scenes() -> void:
beer_scenes.clear()

for path in [
"res://assets/props/Bier1.glb",
"res://assets/props/Bier2.glb"
]:
if ResourceLoader.exists(path):
var scene := load(path)
if scene is PackedScene:
beer_scenes.append(scene as PackedScene)

func _on_openxr_session_begun() -> void:
_enable_passthrough()

func _on_openxr_session_focussed() -> void:
_enable_passthrough()
if state == "boot":
_show_menu()

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

func _show_menu() -> void:
state = "menu"
menu_locked = false
game_over = false
wave = 0
active_tibos = 0
player_health = player_max_health

_clear_tibos()
_populate_beer_cans(16)
_place_menu_in_front_of_player()

menu_root.visible = true
shovel_root.visible = false
health_hud.visible = false
right_hit_area.scale = Vector3.ONE
_update_hud()

func _place_menu_in_front_of_player() -> void:
var forward := -xr_camera.global_transform.basis.z
forward.y = 0.0
if forward.length_squared() < 0.01:
forward = Vector3(0, 0, -1)
else:
forward = forward.normalized()

var pos := xr_camera.global_position + forward * 2.1
pos.y = xr_camera.global_position.y - 0.15
menu_root.global_position = pos

var look_target := xr_camera.global_position
look_target.y = menu_root.global_position.y
menu_root.look_at(look_target, Vector3.UP)

func _start_game(mode: String) -> void:
if menu_locked:
return

menu_locked = true
current_mode = mode
state = "playing"
game_over = false
wave = 0
active_tibos = 0
player_health = player_max_health

menu_root.visible = false
health_hud.visible = true
shovel_root.visible = current_mode == MODE_BERNI
right_hit_area.scale = Vector3.ONE * (1.35 if current_mode == MODE_BERNI else 1.0)

_populate_beer_cans(12)
_update_hud()
call_deferred("_start_next_wave")

func _start_next_wave() -> void:
if state != "playing" or game_over:
return

await get_tree().create_timer(1.0).timeout

if state != "playing" or game_over:
return

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
var angle := TAU * float(index) / float(count) + randf_range(-0.20, 0.20)
var direction := (forward * cos(angle) + right * sin(angle)).normalized()
var distance := randf_range(3.0, 4.3)
var spawn_position := center + direction * distance

var tibo := TIBO_SCENE.instantiate()
enemy_root.add_child(tibo)

if tibo is Node3D:
(tibo as Node3D).global_position = spawn_position

if tibo.has_signal("player_hit"):
tibo.player_hit.connect(_on_tibo_hit_player)
if tibo.has_signal("defeated"):
tibo.defeated.connect(_on_tibo_defeated)

print("Tibo Narvalo : vague %d, %d Tibo laches." % [wave, count])

func _populate_beer_cans(count: int) -> void:
_clear_props()

if beer_scenes.is_empty():
return

var center := xr_camera.global_position
var floor_y := center.y - 1.65

for i in range(count):
var packed := beer_scenes[randi() % beer_scenes.size()]
var can := packed.instantiate()

if not can is Node3D:
continue

prop_root.add_child(can)
var can_node := can as Node3D

var angle := randf() * TAU
var distance := randf_range(0.8, 4.0)

can_node.global_position = Vector3(
center.x + cos(angle) * distance,
floor_y + 0.05,
center.z + sin(angle) * distance
)
can_node.rotation = Vector3(
randf_range(-0.25, 1.15),
randf() * TAU,
randf_range(-1.15, 1.15)
)
can_node.scale = Vector3.ONE * randf_range(0.18, 0.26)

func _clear_props() -> void:
if prop_root == null:
return

for child in prop_root.get_children():
child.queue_free()

func _clear_tibos() -> void:
for child in enemy_root.get_children():
child.queue_free()

func _on_left_hand_body_entered(body: Node3D) -> void:
_handle_hand_hit(body, "left")

func _on_right_hand_body_entered(body: Node3D) -> void:
_handle_hand_hit(body, "right")

func _handle_hand_hit(body: Node3D, hand_name: String) -> void:
if state != "playing" or game_over:
return
if body == null:
return
if not body.is_in_group("tibo"):
return
if not body.has_method("take_hit"):
return

var damage := classic_hand_damage
if current_mode == MODE_BERNI and hand_name == "right":
damage = berni_hand_damage

body.take_hit(damage)

func _on_left_hand_area_entered(area: Area3D) -> void:
_handle_menu_touch(area)

func _on_right_hand_area_entered(area: Area3D) -> void:
_handle_menu_touch(area)

func _handle_menu_touch(area: Area3D) -> void:
if state != "menu" or menu_locked:
return
if area == null or not area.has_meta("mode"):
return

var mode := String(area.get_meta("mode"))
_start_game(mode)

func _on_tibo_hit_player(damage: int) -> void:
if game_over or state != "playing":
return

player_health = max(0, player_health - damage)
_update_hud()

if player_health <= 0:
call_deferred("_game_over")

func _on_tibo_defeated(_tibo: Node) -> void:
active_tibos = max(0, active_tibos - 1)
_update_hud()

if active_tibos == 0 and state == "playing" and not game_over:
call_deferred("_start_next_wave")

func _game_over() -> void:
if game_over:
return

game_over = true
state = "game_over"
health_hud.visible = true
health_hud.text = "VOUS ETES KO !\nRetour a l'accueil..."
await get_tree().create_timer(3.0).timeout
_show_menu()

func _update_hud() -> void:
if health_hud == null:
return

var mode_label := "CLASSIQUE"
if current_mode == MODE_BERNI:
mode_label = "BERNI + PELLE"

health_hud.text = "TIBO NARVALO - %s\nVie %d/%d   Vague %d   Tibo %d" % [
mode_label,
player_health,
player_max_health,
wave,
active_tibos
]
