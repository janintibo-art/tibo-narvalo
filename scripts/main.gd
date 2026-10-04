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

var hand_damage := 55
var shovel_damage := 100
var game_over := false

var menu_root: Node3D
var shovel_root: Node3D
var prop_root: Node3D
var beer_scenes: Array[PackedScene] = []

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

left_hit_area.body_entered.connect(_on_hand_hit.bind("left"))
right_hit_area.body_entered.connect(_on_hand_hit.bind("right"))

left_hit_area.area_entered.connect(_on_menu_area_touched)
right_hit_area.area_entered.connect(_on_menu_area_touched)

_create_runtime_objects()
_load_beers()

player_health = player_max_health
health_hud.visible = false

xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface

if xr_interface == null or not xr_interface.is_initialized():
push_error("Tibo Narvalo : OpenXR indisponible.")
return

get_viewport().use_xr = true
get_viewport().transparent_bg = true
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


func _create_menu() -> void:
var title := Label3D.new()
title.text = "TIBO NARVALO"
title.position = Vector3(0, 1.10, 0)
title.font_size = 105
title.outline_size = 14
title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
menu_root.add_child(title)

var subtitle := Label3D.new()
subtitle.text = "Choisis ton mode puis ta difficulté"
subtitle.position = Vector3(0, 0.75, 0)
subtitle.font_size = 40
subtitle.outline_size = 8
subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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

menu_root.add_child(
_create_button(
"LANCER",
"start",
"start",
Vector3(0, -0.75, 0),
Color(0.65, 0.20, 0.85)
)
)


func _create_button(
button_text: String,
button_type: String,
value: String,
pos: Vector3,
color: Color
) -> Area3D:

var area := Area3D.new()

area.position = pos
area.collision_layer = 2
area.collision_mask = 0
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

area.add_child(label)

return area


func _create_shovel() -> Node3D:
var root := Node3D.new()

root.name = "BerniShovel"
root.position = Vector3(0.06, -0.05, -0.32)
root.rotation_degrees = Vector3(90, 0, 0)

var wood := StandardMaterial3D.new()
wood.albedo_color = Color(0.35, 0.18, 0.06)

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
blade.position.y = 0.46
blade.material_override = metal

root.add_child(blade)

return root


func _load_beers() -> void:
for path in [
"res://assets/props/Bier1.glb",
"res://assets/props/Bier2.glb"
]:
if ResourceLoader.exists(path):
var resource := load(path)

if resource is PackedScene:
beer_scenes.append(resource)


func _on_session_begun() -> void:
_enable_passthrough()


func _on_session_focussed() -> void:
_enable_passthrough()

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

shovel_root.visible = false
health_hud.visible = false
menu_root.visible = true

_clear_tibos()
_place_menu()
_spawn_beers()


func _place_menu() -> void:
var forward := -xr_camera.global_transform.basis.z
forward.y = 0

if forward.length_squared() < 0.01:
forward = Vector3.FORWARD
else:
forward = forward.normalized()

menu_root.global_position = xr_camera.global_position + forward * 2.1
menu_root.global_position.y = xr_camera.global_position.y - 0.25

var target := xr_camera.global_position
target.y = menu_root.global_position.y

menu_root.look_at(target, Vector3.UP)


func _on_menu_area_touched(area: Area3D) -> void:
if game_state != "menu":
return

if not area.has_meta("type"):
return

var button_type := String(area.get_meta("type"))
var value := String(area.get_meta("value"))

if button_type == "mode":
selected_mode = value

elif button_type == "difficulty":
selected_difficulty = value

elif button_type == "start":
_start_game()


func _start_game() -> void:
game_state = "playing"
menu_root.visible = false
health_hud.visible = true

player_health = player_max_health
wave = 0
game_over = false

if selected_difficulty == DIFF_EASY:
max_active_tibos = 1

elif selected_difficulty == DIFF_NORMAL:
max_active_tibos = 2

else:
max_active_tibos = 3

shovel_root.visible = selected_mode == MODE_BERNI

_start_wave()


func _start_wave() -> void:
if game_state != "playing":
return

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
while (
active_tibos < max_active_tibos
and wave_spawned < wave_total
and game_state == "playing"
):
_spawn_one_tibo()


func _spawn_one_tibo() -> void:
var angle := randf() * TAU
var distance := randf_range(3.2, 4.2)

var center := xr_camera.global_position
center.y -= 1.65

var position := center + Vector3(
cos(angle) * distance,
0,
sin(angle) * distance
)

var tibo := TIBO_SCENE.instantiate() as TiboEnemy

enemy_root.add_child(tibo)
tibo.global_position = position

if selected_difficulty == DIFF_EASY:
tibo.move_speed *= 0.80
tibo.attack_damage = 7
tibo.max_health = 80

elif selected_difficulty == DIFF_NORMAL:
tibo.attack_damage = 10
tibo.max_health = 100

else:
tibo.move_speed *= 1.15
tibo.attack_damage = 14
tibo.max_health = 125

tibo.player_hit.connect(_on_tibo_hit_player)
tibo.defeated.connect(_on_tibo_defeated)

wave_spawned += 1
active_tibos += 1


func _on_hand_hit(body: Node3D, hand_name: String) -> void:
if game_state != "playing":
return

if not body is TiboEnemy:
return

var damage := hand_damage

if selected_mode == MODE_BERNI and hand_name == "right":
damage = shovel_damage

(body as TiboEnemy).take_hit(damage)


func _on_tibo_hit_player(damage: int) -> void:
if game_state != "playing":
return

player_health = max(0, player_health - damage)
_update_hud()

if player_health <= 0:
_game_over()


func _on_tibo_defeated(_tibo: Node) -> void:
active_tibos = max(0, active_tibos - 1)
wave_defeated += 1

_update_hud()

if wave_defeated >= wave_total:
await get_tree().create_timer(2.0).timeout

if game_state == "playing":
_start_wave()

else:
_fill_active_slots()


func _game_over() -> void:
if game_over:
return

game_over = true
game_state = "game_over"

health_hud.text = "LES TIBO T'ONT EU 😅"

await get_tree().create_timer(3.0).timeout

_show_menu()


func _spawn_beers() -> void:
for child in prop_root.get_children():
child.queue_free()

if beer_scenes.is_empty():
return

var center := xr_camera.global_position
var floor_y := center.y - 1.65

for i in range(8):
var packed := beer_scenes[randi() % beer_scenes.size()]
var beer := packed.instantiate()

if beer is Node3D:
prop_root.add_child(beer)

var angle := randf() * TAU
var distance := randf_range(1.0, 3.5)

beer.global_position = Vector3(
center.x + cos(angle) * distance,
floor_y + 0.04,
center.z + sin(angle) * distance
)

beer.rotation.y = randf() * TAU
beer.rotation.z = randf_range(-1.1, 1.1)

beer.scale = Vector3.ONE * 0.22


func _clear_tibos() -> void:
for child in enemy_root.get_children():
child.queue_free()


func _update_hud() -> void:
if health_hud == null:
return

health_hud.text = "%s / %s\nVIE %d   VAGUE %d   TIBO %d/%d" % [
selected_mode.to_upper(),
selected_difficulty.to_upper(),
player_health,
wave,
wave_defeated,
wave_total
]
