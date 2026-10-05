class_name BeerPickup
extends Node3D

# Biere laissee par un Tibo vaincu : attrape-la (poing ferme) et amene-la a ta bouche pour recuperer de la vie.

const LIFETIME := 14.0
const BOTTLE_PATHS := ["res://assets/props/Bier1.glb", "res://assets/props/Bier2.glb"]

var heal_amount := 25
var age := 0.0
var held := false
var base_y := 0.0
var ring: MeshInstance3D
var tag: Label3D


func _ready() -> void:
	add_to_group("beer_pickup")
	_build_visual()


func _process(delta: float) -> void:
	if held:
		return

	age += delta
	rotation.y += delta * 1.8
	global_position.y = base_y + sin(age * 3.0) * 0.04

	if age > LIFETIME - 3.0:
		visible = int(age * 8.0) % 2 == 0

	if age >= LIFETIME:
		queue_free()


func set_held(value: bool) -> void:
	held = value
	visible = true

	if held:
		remove_from_group("beer_pickup")

	if is_instance_valid(ring):
		ring.visible = not held

	if is_instance_valid(tag):
		tag.visible = not held


func _build_visual() -> void:
	var model_added := false

	for path in BOTTLE_PATHS:
		if not ResourceLoader.exists(path):
			continue

		var packed := load(path) as PackedScene

		if packed == null:
			continue

		var model := packed.instantiate() as Node3D

		if model:
			model.scale = Vector3.ONE * 0.14
			add_child(model)
			model_added = true
			break

	if not model_added:
		var bottle := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.04
		capsule.height = 0.22
		bottle.mesh = capsule
		add_child(bottle)

	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.18
	ring.mesh = torus

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(0.3, 1.0, 0.4, 0.65)
	ring.material_override = ring_material
	ring.position = Vector3(0, -0.25, 0)
	add_child(ring)

	tag = Label3D.new()
	tag.text = "BIERE +%d" % heal_amount
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.0012
	tag.font_size = 44
	tag.outline_size = 10
	tag.modulate = Color(0.45, 1.0, 0.5)
	tag.position = Vector3(0, 0.32, 0)
	add_child(tag)
