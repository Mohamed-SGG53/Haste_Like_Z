# CrumblingVoid.gd - Visual "wall of destruction" that chases the player.
# ----------------------------------------------------------------------------
# The void is a tall dark slab perpendicular to the Z axis. It follows the
# `void_position_z` value maintained by WorldManager. The wall is centered
# on the player's X/Z (so it stays in view) and reaches from below the
# ground up to a height above the player.
#
# Death is handled by WorldManager (which checks player Z vs void Z). This
# node just renders the void visually.
# ----------------------------------------------------------------------------
extends Node3D
class_name CrumblingVoid

@export var width: float = 300.0
@export var height: float = 80.0
@export var follow_lerp: float = 4.0     # how quickly the visual matches the WM void position
@export var ground_offset: float = -25.0 # how far below the player's ground the void extends

@onready var wall: MeshInstance3D = $VoidWall
@onready var particles_root: Node3D = $ParticlesRoot

var player: Node3D = null
var is_active: bool = true


func _ready() -> void:
	# Build the void slab mesh: a big quad in the XY plane (facing +Z toward player)
	var arr_mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var uvs := PackedVector2Array()
	var h: float = height
	var w: float = width
	# Quad in the XY plane at z=0. Front faces +Z (toward player, who runs in -Z).
	verts.append(Vector3(-w * 0.5, 0, 0))
	verts.append(Vector3( w * 0.5, 0, 0))
	verts.append(Vector3(-w * 0.5, h, 0))
	verts.append(Vector3( w * 0.5, h, 0))
	uvs.append(Vector2(0, 1))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	indices.append_array([0, 1, 2, 2, 1, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	wall.mesh = arr_mesh
	wall.cast_shadow = 0  # off — we want it to glow, not cast shadows
	_spawn_particles()


func set_player(p: Node3D) -> void:
	player = p


func _process(delta: float) -> void:
	if not is_active or not is_instance_valid(player):
		return
	var wm := get_node_or_null("/root/WorldManager")
	if not wm:
		return
	# Smoothly follow the void_position_z (lerp so the wall doesn't jitter).
	var target_z: float = wm.void_position_z
	global_position.z = lerp(global_position.z, target_z, 1.0 - exp(-follow_lerp * delta))
	# Center the wall on the player's X so it always looks like it's chasing them.
	global_position.x = player.global_position.x
	# Y position: top of the void reaches above the player; bottom is well below ground.
	var ground_h: float = wm.get_ground_height(player.global_position.x, player.global_position.z)
	global_position.y = ground_h + ground_offset
	# Tilt the wall slightly so it looks like a wave, not a flat plane.
	rotation.y = lerp(rotation.y, sin(Time.get_ticks_msec() * 0.0005) * 0.05, 1.0 - exp(-2.0 * delta))


func _spawn_particles() -> void:
	for i in range(8):
		var p := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.gravity = Vector3(0.0, -5.0, 5.0)  # particles drift toward +Z (away from player)
		mat.direction = Vector3(0, 1, 1)
		mat.spread = 35.0
		mat.initial_velocity_min = 4.0
		mat.initial_velocity_max = 12.0
		mat.scale_min = 0.5
		mat.scale_max = 2.0
		mat.color = Color(0.5, 0.1, 0.7, 0.7)
		p.process_material = mat
		p.amount = 40
		p.lifetime = 2.5
		p.position = Vector3(
			randf_range(-width * 0.45, width * 0.45),
			randf_range(0, height),
			randf_range(-2.0, 2.0)
		)
		particles_root.add_child(p)
