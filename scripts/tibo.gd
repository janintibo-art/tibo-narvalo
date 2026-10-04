extends CharacterBody3D

signal player_hit(damage: int)
signal defeated(tibo: Node)

@export var move_speed: float = 1.15
@export var attack_distance: float = 1.25
@export var attack_repeat: float = 1.8
@export var max_health: int = 100
@export var attack_damage: int = 12

var health: int
var player_camera: XRCamera3D
var animation_player: AnimationPlayer
var walk_animation: StringName = &""
var hit_animation: StringName = &""
var death_animation: StringName = &""
var attack_animations: Array[StringName] = []

var attack_timer: float = 0.0
var attack_windup: float = 0.0
var attack_in_progress := false
var is_dead := false

@onready var name_label: Label3D = $Name
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
add_to_group("tibo")
health = max_health
move_speed *= randf_range(0.88, 1.18)
attack_repeat *= randf_range(0.85, 1.15)
attack_timer = randf_range(0.4, 1.1)

player_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D
animation_player = _find_animation_player(self)

if animation_player:
walk_animation = _find_first_animation(["walk", "run"])
hit_animation = _find_first_animation(["hit", "damage", "impact"])
death_animation = _find_first_animation(["death", "die", "dying", "fall"])
attack_animations = _find_animations(["attack", "hook", "kick", "punch", "strike"])

if attack_animations.is_empty():
for candidate in [&"Right_Upper_Hook_from_Guard", &"Lunge_Spin_Kick"]:
if animation_player.has_animation(candidate):
attack_animations.append(candidate)

_play(walk_animation)

_update_label()

func _physics_process(delta: float) -> void:
if is_dead:
return

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

if attack_in_progress:
velocity = Vector3.ZERO
move_and_slide()
attack_windup -= delta
if attack_windup <= 0.0:
attack_in_progress = false
if distance <= attack_distance + 0.35:
player_hit.emit(attack_damage)
return

if distance > attack_distance:
var direction := to_player.normalized()
velocity = direction * move_speed
velocity.y = 0.0
move_and_slide()
_play(walk_animation)
attack_timer = max(attack_timer - delta, 0.0)
else:
velocity = Vector3.ZERO
move_and_slide()
attack_timer -= delta
if attack_timer <= 0.0:
_start_attack()
attack_timer = attack_repeat

func _start_attack() -> void:
attack_in_progress = true
attack_windup = 0.42

if not attack_animations.is_empty():
var chosen := attack_animations[randi() % attack_animations.size()]
_play(chosen, true)

func take_hit(amount: int) -> void:
if is_dead:
return

health = max(0, health - amount)
_update_label()

if health <= 0:
_die()
elif hit_animation != &"":
_play(hit_animation, true)

func _die() -> void:
is_dead = true
velocity = Vector3.ZERO
attack_in_progress = false

if collision_shape:
collision_shape.set_deferred("disabled", true)

if name_label:
name_label.text = "TIBO\nKO"

if death_animation != &"":
_play(death_animation, true)

defeated.emit(self)
await get_tree().create_timer(1.4).timeout
queue_free()

func _update_label() -> void:
if name_label:
name_label.text = "TIBO\n%d HP" % health

func _find_animation_player(node: Node) -> AnimationPlayer:
if node is AnimationPlayer:
return node as AnimationPlayer

for child in node.get_children():
var found := _find_animation_player(child)
if found:
return found

return null

func _find_first_animation(keywords: Array[String]) -> StringName:
if animation_player == null:
return &""

var matches := _find_animations(keywords)
if not matches.is_empty():
return matches[0]

for name in animation_player.get_animation_list():
if name != &"RESET":
return name

return &""

func _find_animations(keywords: Array[String]) -> Array[StringName]:
var matches: Array[StringName] = []

if animation_player == null:
return matches

for animation_name in animation_player.get_animation_list():
if animation_name == &"RESET":
continue

var lower := String(animation_name).to_lower()
for keyword in keywords:
if lower.contains(keyword):
matches.append(animation_name)
break

return matches

func _play(animation_name: StringName, restart: bool = false) -> void:
if animation_player == null or animation_name == &"":
return

if restart or animation_player.current_animation != animation_name or not animation_player.is_playing():
animation_player.play(animation_name)
