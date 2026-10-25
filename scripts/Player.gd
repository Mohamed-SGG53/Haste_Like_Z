# Player.gd - Haste-inspired third-person autorunner
# ----------------------------------------------------------------------------
# Key Haste mechanics implemented here:
#   1. AUTO-RUN        - constant forward push (no walk/run button)
#   2. NO JUMP BUTTON  - only a "fast-fall" key (hold Space) that adds downward force
#   3. SLOPE-AWARE LANDING - landing on a downhill slope gives speed boost;
#                          landing on an uphill slope slows you down
#   4. LANDING RATING     - Perfect / Good / OK / Poor based on slope angle and impact speed
#   5. SPEED DECAY        - speed gradually bleeds off so each landing matters
#   6. AIR CONTROL        - WASD nudges direction slightly while airborne
# ----------------------------------------------------------------------------
extends CharacterBody3D
class_name Player

# --- Forward direction is -Z (Godot default for CharacterBody3D) ---
const FORWARD := Vector3(0, 0, -1)

# --- Tunable constants (mirror Haste's feel) ---
@export_group("Movement")
@export var base_speed: float = 14.0           # m/s, auto-run baseline
@export var max_speed: float = 65.0            # m/s, hard cap from perfect landings
@export var min_speed: float = 6.0             # m/s, floor (don't go below this)
@export var speed_decay_per_sec: float = 1.2   # natural bleed-off
@export var air_steer_strength: float = 0.18   # WASD effect in air
@export var ground_steer_strength: float = 0.45

@export_group("Gravity & Fast-Fall")
@export var gravity: float = 22.0
@export var fast_fall_force: float = 55.0     # extra downward pull when holding Space
@export var fast_fall_max_speed: float = 60.0 # terminal velocity during fast-fall

@export_group("Landing")
@export var perfect_slope_min: float = 8.0    # degrees downhill for "Perfect"
@export var good_slope_min: float = 3.0       # degrees downhill for "Good"
@export var poor_slope_max: float = -3.0       # degrees (uphill) below which is "Poor"
@export var perfect_speed_gain: float = 18.0
@export var good_speed_gain: float = 9.0
@export var ok_speed_gain: float = 1.5
@export var poor_speed_loss: float = 12.0
@export var crash_speed_loss: float = 30.0    # hitting a wall at speed

@export_group("References")
@export var camera_rig_path: NodePath = "CameraRig"
@export var model_path: NodePath = "Model"
@export var ground_ray_path: NodePath = "GroundRay"
@export var slope_ahead_ray_path: NodePath = "SlopeAheadRay"

# --- Internal state ---
var speed: float = 14.0
var energy: float = 100.0
var last_y_velocity: float = 0.0
var was_in_air: bool = false
var landing_flash_timer: float = 0.0
var last_landing_rating: String = ""
var distance_traveled: float = 0.0
var alive: bool = true
var run_anim_phase: float = 0.0
var air_anim_active: bool = false

@onready var camera_rig: Node3D = get_node(camera_rig_path)
@onready var camera: Camera3D = camera_rig.get_node("Camera3D")
@onready var model: Node3D = get_node(model_path)
@onready var ground_ray: RayCast3D = get_node(ground_ray_path)
@onready var slope_ahead_ray: RayCast3D = get_node(slope_ahead_ray_path)
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# Body parts for procedural animation
@onready var body: MeshInstance3D = $Model/Body
@onready var left_arm: MeshInstance3D = $Model/LeftArm
@onready var right_arm: MeshInstance3D = $Model/RightArm
@onready var left_leg: MeshInstance3D = $Model/LeftLeg
@onready var right_leg: MeshInstance3D = $Model/RightLeg
@onready var scarf: MeshInstance3D = $Model/Scarf
@onready var shadow_mesh: MeshInstance3D = $Shadow

signal landed(rating: String, impact_speed: float, slope_deg: float)
signal died()
signal speed_changed(new_speed: float)
signal distance_changed(meters: float)


func _ready() -> void:
        # Build procedural animations at runtime so we don't depend on .res files.
        _build_animations()
        if anim_player.has_animation("run"):
                anim_player.play("run")
        # Floor stickiness on slopes: keep our downward velocity from being killed
        # by CharacterBody3D's snapping when we want to fly off ramps.
        floor_stop_on_slope = false
        floor_max_angle = deg_to_rad(60.0)
        max_slides = 2
        # CRITICAL for fast-moving bodies: increase safe margin so we don't tunnel
        # through the terrain at high speeds (common autorunner bug).
        safe_margin = 0.08
        # Make ground ray pick up everything on layer 1 (World)
        ground_ray.collision_mask = 1
        # Make sure we collide with World (layer 1) and Obstacles (layer 4).
        collision_mask = 1 | 4


func _physics_process(delta: float) -> void:
        if not alive:
                return

        # Save the pre-move vertical velocity so we can detect "just landed".
        last_y_velocity = velocity.y

        # --- Gravity ---------------------------------------------------------
        if not is_on_floor():
                velocity.y -= gravity * delta
                # Haste's signature: hold Space to plummet faster
                if Input.is_action_pressed("fast_fall"):
                        velocity.y -= fast_fall_force * delta
                        velocity.y = max(velocity.y, -fast_fall_max_speed)

        # --- Auto-run forward (this is the heart of Haste) -------------------
        # Always push forward at `speed`. Air steering nudges XZ slightly.
        var input_x := Input.get_axis("steer_left", "steer_right")
        var desired := FORWARD * speed

        if is_on_floor():
                # On ground, allow a little steering toward desired direction.
                desired.x += input_x * speed * ground_steer_strength
        else:
                # In the air, gentle nudging.
                desired.x += input_x * speed * air_steer_strength

        velocity.x = lerp(velocity.x, desired.x, 1.0 - exp(-12.0 * delta))
        velocity.z = lerp(velocity.z, desired.z, 1.0 - exp(-12.0 * delta))

        # --- Move ------------------------------------------------------------
        var was_on_floor := is_on_floor()
        move_and_slide()

        # --- Landing detection ----------------------------------------------
        # Detect the frame we transitioned from airborne -> grounded.
        if not was_on_floor and is_on_floor() and last_y_velocity < -4.0:
                _evaluate_landing(last_y_velocity)

        # Track current airborne state for next-frame landing detection.
        was_in_air = not is_on_floor()
        # Always tick down the landing flash timer.
        landing_flash_timer = max(0.0, landing_flash_timer - delta)

        # --- Speed decay so every landing matters --------------------------
        speed = clamp(speed - speed_decay_per_sec * delta, min_speed, max_speed)
        emit_signal("speed_changed", speed)

        # --- Distance traveled ----------------------------------------------
        distance_traveled += speed * delta
        emit_signal("distance_changed", distance_traveled)

        # --- Safety net: if the player somehow falls through the world,
        #     kill them so the run ends cleanly instead of falling forever.
        if global_position.y < -50.0 and alive:
                die()

        # --- Procedural limb animation (run cycle + air pose) ---------------
        _update_limb_animation(delta)

        # --- Shadow follows ground ------------------------------------------
        _update_shadow()

        # --- Tilt body slightly when steering -------------------------------
        model.rotation.z = lerp(model.rotation.z, -input_x * 0.18, 1.0 - exp(-10.0 * delta))
        # Lean forward at speed
        model.rotation.x = lerp(model.rotation.x, -0.08 * clamp(speed / 30.0, 0.0, 1.5), 1.0 - exp(-8.0 * delta))

        # --- Camera FOV widens with speed for sense-of-speed ----------------
        if camera:
                var target_fov := lerp(70.0, 95.0, clamp((speed - base_speed) / (max_speed - base_speed), 0.0, 1.0))
                camera.fov = lerp(camera.fov, target_fov, 1.0 - exp(-4.0 * delta))


func _evaluate_landing(impact_y: float) -> void:
        # Haste's core gameplay: the slope you land on dictates your speed.
        # Compute the surface normal at the contact point and project onto
        # the player's forward direction. Positive => downhill, negative => uphill.
        var normal: Vector3 = get_floor_normal()
        if normal == Vector3.ZERO:
                # Fallback: use the slope-ahead ray
                if slope_ahead_ray.is_colliding():
                        normal = slope_ahead_ray.get_collision_normal()
                else:
                        normal = Vector3.UP

        # Slope angle in degrees (0 = flat)
        var slope_deg_flat := rad_to_deg(acos(clamp(normal.y, -1.0, 1.0)))
        # Signed slope: positive = downhill (player going down the slope)
        # We project the negative of the normal (pointing INTO the slope downward)
        # onto the player's forward direction.
        var forward_dir := -global_transform.basis.z.normalized()
        var downhill_dot := -normal.dot(Vector3.UP)  # 0 = flat, 1 = vertical wall
        var signed_slope_flat := rad_to_deg(atan2(-normal.dot(forward_dir), normal.y))

        # Haste's "perfect landing" requires:
        # 1. Going downhill (signed_slope_flat > 0)
        # 2. Reasonable impact speed (fast fall = better)
        var impact_speed := abs(impact_y)
        var rating: String = ""
        var speed_delta: float = 0.0

        if signed_slope_flat >= perfect_slope_min and impact_speed > 12.0:
                rating = "Perfect!"
                speed_delta = perfect_speed_gain
        elif signed_slope_flat >= good_slope_min:
                rating = "Good!"
                speed_delta = good_speed_gain
        elif signed_slope_flat >= poor_slope_max:
                rating = "OK"
                speed_delta = ok_speed_gain
        else:
                # Uphill or wall hit = punish
                rating = "Poor"
                speed_delta = -poor_speed_loss

        # Hard crash: very steep uphill / wall
        if signed_slope_flat < -25.0 and impact_speed > 18.0:
                rating = "Crash!"
                speed_delta = -crash_speed_loss

        speed = clamp(speed + speed_delta, min_speed, max_speed)
        last_landing_rating = rating
        landing_flash_timer = 1.2
        emit_signal("landed", rating, impact_speed, signed_slope_flat)

        # Trigger landing animation (crouch + recover)
        if anim_player and anim_player.has_animation("land"):
                anim_player.stop()
                anim_player.play("land")
                # Then resume run
                anim_player.queue("run")


# Procedural limb animation. We can't reliably bake AnimationPlayer tracks
# in .tscn without external .res files, so we drive the limbs in code.
func _update_limb_animation(delta: float) -> void:
        if not (is_instance_valid(left_leg) and is_instance_valid(right_leg) and is_instance_valid(left_arm) and is_instance_valid(right_arm)):
                return

        if is_on_floor():
                # Run cycle: speed up the cycle as player speed grows
                var cycle_rate: float = 6.0 + (speed - base_speed) * 0.18
                run_anim_phase += cycle_rate * delta
                var swing: float = 0.55
                left_leg.rotation.x = sin(run_anim_phase) * swing
                right_leg.rotation.x = sin(run_anim_phase + PI) * swing
                left_arm.rotation.x = sin(run_anim_phase + PI) * swing * 0.7
                right_arm.rotation.x = sin(run_anim_phase) * swing * 0.7
                # Subtle body bob
                body.position.y = 0.85 + sin(run_anim_phase * 2.0) * 0.04
                # Scarf trails behind (negative Z = behind player in our convention)
                scarf.rotation.x = lerp(scarf.rotation.x, -0.15 - 0.4 * clamp((speed - base_speed) / 30.0, 0.0, 1.5), 1.0 - exp(-6.0 * delta))
        else:
                # Air pose: arms up, legs slightly tucked (Haste "free fall" pose)
                var target_arm: float = -1.4 if Input.is_action_pressed("fast_fall") else -0.8
                left_arm.rotation.x = lerp(left_arm.rotation.x, target_arm, 1.0 - exp(-6.0 * delta))
                right_arm.rotation.x = lerp(right_arm.rotation.x, target_arm, 1.0 - exp(-6.0 * delta))
                left_leg.rotation.x = lerp(left_leg.rotation.x, 0.25, 1.0 - exp(-6.0 * delta))
                right_leg.rotation.x = lerp(right_leg.rotation.x, -0.25, 1.0 - exp(-6.0 * delta))
                # Scarf flicks up when falling
                scarf.rotation.x = lerp(scarf.rotation.x, 0.5, 1.0 - exp(-4.0 * delta))


func _update_shadow() -> void:
        # Place a soft blob shadow on the ground beneath us, fading with height.
        if not ground_ray.is_colliding():
                shadow_mesh.visible = false
                return
        shadow_mesh.visible = true
        var hit_pos: Vector3 = ground_ray.get_collision_point()
        shadow_mesh.global_position = hit_pos + Vector3(0, 0.02, 0)
        # Scale & fade by distance to ground
        var dist_to_ground: float = global_position.y - hit_pos.y
        var scale_factor: float = clamp(1.0 - dist_to_ground / 10.0, 0.4, 1.0)
        shadow_mesh.scale = Vector3(scale_factor, 1.0, scale_factor)
        var mat: StandardMaterial3D = shadow_mesh.material_override
        if mat:
                mat.albedo_color.a = 0.35 * scale_factor


# Build basic AnimationPlayer animations procedurally.
# We expose them as named animations so other systems (landing) can call them.
func _build_animations() -> void:
        if not anim_player:
                return
        var lib := AnimationLibrary.new()

        # RUN animation: a no-op placeholder. The actual limb motion is driven
        # by _update_limb_animation() above. We keep this 1-frame animation so
        # the player can be in "run state" via anim_player.play("run").
        var run_anim := Animation.new()
        run_anim.length = 0.1
        run_anim.loop_mode = Animation.LOOP
        lib.add_animation("run", run_anim)

        # LAND animation: a quick crouch (lower the model) and recover.
        # We animate Model:position.y so the whole body dips.
        var land_anim := Animation.new()
        land_anim.length = 0.45
        land_anim.loop_mode = Animation.LOOP_NONE
        var track_path := "Model:position"
        land_anim.add_track(Animation.TYPE_VALUE)
        land_anim.track_set_path(0, track_path)
        land_anim.track_insert_key(0, 0.0, Vector3(0, 0, 0))
        land_anim.track_insert_key(0, 0.08, Vector3(0, -0.18, 0))
        land_anim.track_insert_key(0, 0.25, Vector3(0, -0.08, 0))
        land_anim.track_insert_key(0, 0.45, Vector3(0, 0, 0))
        lib.add_animation("land", land_anim)

        # FALL animation: arms up, body slightly tucked. Same idea - mostly
        # driven in code, this just acts as a state marker.
        var fall_anim := Animation.new()
        fall_anim.length = 0.2
        fall_anim.loop_mode = Animation.LOOP
        lib.add_animation("fall", fall_anim)

        anim_player.add_animation_library("", lib)


func die() -> void:
        if not alive:
                return
        alive = false
        emit_signal("died")
        # Stop forward motion so death feels weighty
        velocity = Vector3.ZERO


func reset(spawn_pos: Vector3) -> void:
        global_position = spawn_pos
        speed = base_speed
        energy = 100.0
        distance_traveled = 0.0
        alive = true
        was_in_air = false
        last_landing_rating = ""
        if anim_player and anim_player.has_animation("run"):
                anim_player.play("run")
