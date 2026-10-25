# TerrainChunk.gd - A single procedural terrain chunk with SMOOTH shading.
# ----------------------------------------------------------------------------
# Visual: 64x64 vertex heightmap with smooth per-vertex normals computed from
#   world-space noise samples (so chunk boundaries don't show normal seams).
#   Custom terrain shader for height-based coloring + procedural noise.
# Collider: 32x32 ConcavePolygonShape3D (cheaper than 64x64 but still accurate
#   enough for slope-aware landing). The player lands on the actual slopes.
# Crumble: when the void catches up, the chunk sinks and obstacles fall.
# ----------------------------------------------------------------------------
extends Node3D
class_name TerrainChunk

@export_group("Chunk Layout")
@export var chunk_size_x: float = 100.0
@export var chunk_size_z: float = 100.0
@export var visual_resolution: int = 64   # 64x64 visual verts = 4096 verts
@export var collider_resolution: int = 32 # 32x32 collider tris = 2048 tris (cheaper)

@export_group("Terrain Shape")
@export var height_amplitude: float = 14.0
@export var base_height: float = 0.0
@export var obstacle_count: int = 5
@export var seed_offset: int = 0

@export_group("Materials")
@export var terrain_shader: Shader = preload("res://assets/terrain.gdshader")

var noise: FastNoiseLite
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collider_shape: ConcavePolygonShape3D
var obstacles_root: Node3D
var chunk_origin: Vector2 = Vector2.ZERO
var is_crumbling: bool = false
var crumble_timer: float = 0.0
var material: ShaderMaterial = null


func _ready() -> void:
	mesh_instance = $Mesh
	static_body = $Mesh/Body
	collider_shape = $Mesh/Body/ColliderShape.shape
	obstacles_root = $ObstaclesRoot
	if noise == null:
		noise = FastNoiseLite.new()
		noise.seed = 1337
		noise.frequency = 0.012
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Build a ShaderMaterial from the terrain shader so each chunk has its
	# own material instance (otherwise all chunks share one and we can't
	# tweak per-chunk uniforms if we ever want to).
	if material == null:
		material = ShaderMaterial.new()
		material.shader = terrain_shader


# Generate the chunk at (chunk_x, chunk_z) grid coordinates.
func generate(chunk_x: int, chunk_z: int, world_seed: int) -> void:
	chunk_origin = Vector2(chunk_x * chunk_size_x, chunk_z * chunk_size_z)
	if noise == null:
		noise = FastNoiseLite.new()
	noise.seed = world_seed + seed_offset
	noise.frequency = 0.012
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_mesh()
	_build_collider()
	_spawn_obstacles()


# Build the high-resolution visual mesh with SMOOTH per-vertex normals.
# Normals are computed by sampling world-space noise just outside the vertex
# in each cardinal direction. Because the noise function is continuous in
# world space, this gives normals that match across chunk boundaries
# (no visible seam between chunks).
func _build_mesh() -> void:
	var arr_mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var res := visual_resolution
	var step_x: float = chunk_size_x / float(res)
	var step_z: float = chunk_size_z / float(res)

	# Vertex grid
	verts.resize((res + 1) * (res + 1))
	uvs.resize((res + 1) * (res + 1))
	normals.resize((res + 1) * (res + 1))
	for j in range(res + 1):
		for i in range(res + 1):
			var x_local: float = i * step_x
			var z_local: float = j * step_z
			var world_x: float = chunk_origin.x + x_local
			var world_z: float = chunk_origin.y + z_local
			var h: float = _sample_height(world_x, world_z)
			var idx: int = j * (res + 1) + i
			verts[idx] = Vector3(x_local, h - base_height, z_local)
			uvs[idx] = Vector2(float(i) / float(res), float(j) / float(res))
			# Smooth normal via world-space neighbor samples (handles edges correctly).
			var h_left: float = _sample_height(world_x - step_x, world_z)
			var h_right: float = _sample_height(world_x + step_x, world_z)
			var h_up: float = _sample_height(world_x, world_z - step_z)
			var h_down: float = _sample_height(world_x, world_z + step_z)
			var dh_dx: float = h_right - h_left
			var dh_dz: float = h_down - h_up
			# (-dh/dx, 1, -dh/dz) scaled by 2*step for correct magnitude.
			var n := Vector3(-dh_dx, 2.0 * step_x, -dh_dz)
			# Normalize (with safety for degenerate flat areas).
			var nlen: float = n.length()
			if nlen > 0.0001:
				n /= nlen
			else:
				n = Vector3.UP
			normals[idx] = n

	# Triangulate
	for j in range(res):
		for i in range(res):
			var a: int = j * (res + 1) + i
			var b: int = a + 1
			var c: int = a + (res + 1)
			var d: int = c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = arr_mesh
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(chunk_origin.x, base_height, chunk_origin.y)

	# Re-anchor the StaticBody so its collider lines up with the visual mesh.
	static_body.position = mesh_instance.position


# Lower-resolution concave collider. The 32x32 triangle count is plenty for
# detecting slope angles for the player's landing system, and 4x cheaper
# than the visual mesh.
func _build_collider() -> void:
	var tris := PackedVector3Array()
	var res := collider_resolution
	var step_x: float = chunk_size_x / float(res)
	var step_z: float = chunk_size_z / float(res)
	for j in range(res):
		for i in range(res):
			var x0: float = i * step_x
			var x1: float = (i + 1) * step_x
			var z0: float = j * step_z
			var z1: float = (j + 1) * step_z
			var world_x0: float = chunk_origin.x + x0
			var world_x1: float = chunk_origin.x + x1
			var world_z0: float = chunk_origin.y + z0
			var world_z1: float = chunk_origin.y + z1
			var h00: float = _sample_height(world_x0, world_z0)
			var h10: float = _sample_height(world_x1, world_z0)
			var h01: float = _sample_height(world_x0, world_z1)
			var h11: float = _sample_height(world_x1, world_z1)
			var v00 := Vector3(x0, h00 - base_height, z0)
			var v10 := Vector3(x1, h10 - base_height, z0)
			var v01 := Vector3(x0, h01 - base_height, z1)
			var v11 := Vector3(x1, h11 - base_height, z1)
			tris.append(v00)
			tris.append(v01)
			tris.append(v10)
			tris.append(v10)
			tris.append(v01)
			tris.append(v11)
	collider_shape.set_faces(tris)


# Sample the height at a world (x, z) coordinate.
# Combines 3 octaves of Simplex noise so we get rolling hills + bumps + a
# slow wide swell. Smooth and continuous across chunk boundaries.
func _sample_height(world_x: float, world_z: float) -> float:
	var h1: float = noise.get_noise_2d(world_x * 1.0, world_z * 1.0) * height_amplitude
	var h2: float = noise.get_noise_2d(world_x * 3.5 + 1000.0, world_z * 3.5 - 500.0) * (height_amplitude * 0.25)
	var h3: float = noise.get_noise_2d(world_x * 0.35 - 700.0, world_z * 0.35 + 200.0) * (height_amplitude * 1.4)
	return base_height + h1 + h2 + h3


# Spawn a few obstacles on top of the terrain (rocks). All have colliders
# on layer 4 (Obstacles) so the player crashes into them at speed.
func _spawn_obstacles() -> void:
	for child in obstacles_root.get_children():
		child.queue_free()
	if obstacle_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(noise.seed) + (int(chunk_origin.x) * 31 + int(chunk_origin.y) * 17)) & 0x7FFFFFFF
	for i in range(obstacle_count):
		var x: float = rng.randf() * chunk_size_x
		var z: float = rng.randf() * chunk_size_z
		var world_x: float = chunk_origin.x + x
		var world_z: float = chunk_origin.y + z
		var h: float = _sample_height(world_x, world_z)
		var obs := MeshInstance3D.new()
		obs.mesh = BoxMesh.new()
		obs.mesh.size = Vector3(rng.randf_range(1.0, 2.5), rng.randf_range(2.0, 4.0), rng.randf_range(1.0, 2.5))
		obs.position = Vector3(x, h - base_height + obs.mesh.size.y * 0.5, z)
		obs.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0, TAU), rng.randf_range(-0.1, 0.1))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.3, 0.25, 1.0)
		mat.roughness = 0.85
		obs.material_override = mat
		var body := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = obs.mesh.size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		body.position = Vector3(0, -obs.mesh.size.y * 0.5, 0)
		body.collision_layer = 4
		obs.add_child(body)
		obstacles_root.add_child(obs)


# Trigger visual crumbling: sink the chunk + tilt obstacles + spawn debris.
# After `lifetime`, the chunk is removed from the scene.
func crumble(lifetime: float = 4.0) -> void:
	if is_crumbling:
		return
	is_crumbling = true
	crumble_timer = lifetime


func _process(delta: float) -> void:
	if not is_crumbling:
		return
	crumble_timer -= delta
	mesh_instance.position.y -= delta * 3.0
	for child in obstacles_root.get_children():
		child.rotation.x += delta * 1.5
		child.rotation.z += delta * 2.0
		child.position.y -= delta * 4.0
	if crumble_timer <= 0.0:
		queue_free()
