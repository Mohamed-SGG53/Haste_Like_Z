# WorldManager.gd - Registered as an autoload in project.godot.
# ----------------------------------------------------------------------------
# Streams TerrainChunks around the player to create an ENDLESS world:
#  - Spawns chunks in a 7x8 grid around the player (more ahead than behind
#    since the autorunner runs in -Z)
#  - Despawns chunks that fall out of range, crumbling them visually
#  - Tracks the "void Z" — a fixed-velocity wall of destruction that
#    advances in -Z (the direction the player is running). If the player
#    slows below the void's velocity, it catches up and kills them.
# ----------------------------------------------------------------------------
extends Node

const CHUNK_SIZE: float = 100.0
const GRID_RADIUS: int = 3            # spawn 7x8 chunk grid around the player
const WORLD_SEED: int = 72451
const VOID_LAG_DISTANCE: float = 250.0    # initial gap between player and void
const VOID_VELOCITY: float = 9.0           # m/s, void advances in -Z at this rate
const VOID_KILL_DISTANCE: float = 3.0      # if player within 3m of void = death

var player: Node3D = null
var chunks: Dictionary = {}  # key: "x,z" -> TerrainChunk instance
var chunk_scene: PackedScene = null
var void_position_z: float = 250.0  # initial void position (250m behind player at z=0)
var game_started: bool = false

signal chunk_destroyed(chunk_x: int, chunk_z: int)
signal void_advanced(world_z: float)


func _ready() -> void:
        chunk_scene = load("res://scenes/TerrainChunk.tscn")
        # Default void_position_z is set so the void is `VOID_LAG_DISTANCE` behind
        # the player's spawn point (z=0). The void advances in -Z direction.
        void_position_z = VOID_LAG_DISTANCE


func set_player(p: Node3D) -> void:
        player = p
        game_started = true


func _process(delta: float) -> void:
        if not is_instance_valid(player) or chunk_scene == null:
                return

        # --- Advance the void in -Z direction at fixed velocity -----------------
        # The void does NOT track the player's position. It just moves at a
        # constant velocity in -Z. If the player outruns it, great. If they
        # slow below VOID_VELOCITY, it catches up.
        void_position_z -= VOID_VELOCITY * delta
        emit_signal("void_advanced", void_position_z)

        # --- Death check: if the player is too close to (or behind) the void ---
        # The void is at `void_position_z` in world space. The player runs in -Z
        # so player.z is decreasing. The player is "behind" the void (i.e., has
        # been caught) when player.z > void_position_z (player at higher z than void).
        if player.global_position.z > void_position_z - VOID_KILL_DISTANCE:
                if player.has_method("die"):
                        player.die()

        # --- Player's current chunk coords --------------------------------------
        var player_chunk_x: int = int(floor(player.global_position.x / CHUNK_SIZE))
        var player_chunk_z: int = int(floor(player.global_position.z / CHUNK_SIZE))

        # --- Spawn chunks in radius around player -------------------------------
        # More chunks ahead (negative z) than behind (positive z) since the
        # autorunner runs in -Z. The grid is:
        #   x: [-GRID_RADIUS, GRID_RADIUS]
        #   z: [-GRID_RADIUS - 1, GRID_RADIUS]  (extra chunk ahead)
        for dz in range(-GRID_RADIUS - 1, GRID_RADIUS + 1):
                for dx in range(-GRID_RADIUS, GRID_RADIUS + 1):
                        var cx: int = player_chunk_x + dx
                        var cz: int = player_chunk_z + dz
                        var key: String = "%d,%d" % [cx, cz]
                        if not chunks.has(key):
                                _spawn_chunk(cx, cz)

        # --- Despawn chunks that are too far away ------------------------------
        # Use a typed Array[String] so the loop variable has a known type and
        # String.split() can be type-inferred properly.
        var to_remove: Array[String] = []
        for key: String in chunks.keys():
                # Explicit PackedStringArray type because String.split returns
                # PackedStringArray, but `key` may still be Variant-typed at parse
                # time inside a Dictionary iteration in older Godot 4.x versions.
                var parts: PackedStringArray = key.split(",")
                var cx: int = int(parts[0])
                var cz: int = int(parts[1])
                var dz: int = cz - player_chunk_z
                var dx: int = abs(cx - player_chunk_x)
                # Despawn if too far in any direction. The threshold is asymmetric:
                # despawn behind (dz > GRID_RADIUS + 1) sooner than ahead (dz < -GRID_RADIUS - 2).
                if dz > GRID_RADIUS + 1 or dz < -GRID_RADIUS - 2 or dx > GRID_RADIUS + 1:
                        to_remove.append(key)

        for key: String in to_remove:
                var chunk: Node = chunks[key]
                var parts2: PackedStringArray = key.split(",")
                var cz: int = int(parts2[1])
                # Crumble chunks behind the player (positive dz = behind, in +Z direction).
                if cz > player_chunk_z:
                        chunk.crumble(2.0)
                else:
                        chunk.queue_free()
                chunks.erase(key)
                emit_signal("chunk_destroyed", int(parts2[0]), cz)


func _spawn_chunk(cx: int, cz: int) -> void:
        var chunk: TerrainChunk = chunk_scene.instantiate()
        add_child(chunk)
        chunk.chunk_size_x = CHUNK_SIZE
        chunk.chunk_size_z = CHUNK_SIZE
        chunk.visual_resolution = 64
        chunk.collider_resolution = 32
        chunk.height_amplitude = 14.0
        chunk.base_height = 0.0
        chunk.obstacle_count = 4
        chunk.seed_offset = (cx * 7 + cz * 13) % 1000
        chunk.generate(cx, cz, WORLD_SEED)
        var key: String = "%d,%d" % [cx, cz]
        chunks[key] = chunk


# Public API: get the height of the terrain at a world (x, z).
# Useful for the CrumblingVoid or HUD to know where the ground is.
# Uses a single shared noise to keep results consistent across chunks.
func get_ground_height(world_x: float, world_z: float) -> float:
        var noise := FastNoiseLite.new()
        noise.seed = WORLD_SEED
        noise.frequency = 0.012
        noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
        var h1: float = noise.get_noise_2d(world_x, world_z) * 14.0
        var h2: float = noise.get_noise_2d(world_x * 3.5 + 1000.0, world_z * 3.5 - 500.0) * (14.0 * 0.25)
        var h3: float = noise.get_noise_2d(world_x * 0.35 - 700.0, world_z * 0.35 + 200.0) * (14.0 * 1.4)
        return h1 + h2 + h3


# Reset the world state for a new run (called when the game restarts).
func reset_world() -> void:
        for key: String in chunks.keys():
                (chunks[key] as Node).queue_free()
        chunks.clear()
        void_position_z = VOID_LAG_DISTANCE
