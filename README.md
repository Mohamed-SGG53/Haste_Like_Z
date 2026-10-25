# HasteLike - Godot 4.5.1 Project

A Haste-inspired third-person autorunner with slope-aware landing physics, **smooth shaded procedural terrain** (no visible facets), **custom terrain shader**, **endless chunk streaming**, **mouse-look camera controls**, and a **chasing void wall**.

## Quick Start

1. **Open the project in Godot 4.5.1** (or any 4.5.x). The project file is `project.godot`.
2. Wait for the editor to import assets.
3. Press **F5** to run. The main scene is `scenes/Main.tscn`.
4. **Click in the game window** to capture the mouse for camera control.

## Controls

| Key | Action |
|-----|--------|
| **A / D** (or Left / Right) | Steer left/right (gentle nudge — Haste has no jump button) |
| **Hold Space** | **Fast fall** — pull the player down faster mid-air |
| **Mouse movement** | Orbit camera around the player (yaw + pitch) |
| **Mouse click** | Capture mouse (enables camera control) |
| **Scroll wheel** | Zoom camera in/out |
| **ESC** | Release mouse (or pause if already released) |
| **P** | Pause / unpause |
| **R** | Restart after death |

## What's Implemented

### Player model (`scenes/Player.tscn`, `scripts/Player.gd`)

A **3D humanoid** built from primitive Godot meshes — body, head, hair, arms, legs, and a trailing scarf (Haste's Zoe has a scarf). Limbs are driven **procedurally** in `_update_limb_animation()` — cycle rate scales with player speed so faster = more frantic swing. Includes a drop shadow that scales with height above ground.

### Physics — Haste-like

| Mechanic | Implementation |
|---|---|
| **Auto-run** | Constant forward push in `-Z` at `base_speed = 14 m/s` |
| **No jump button** | Only a "fast-fall" key (Space) adds downward force while airborne |
| **Gravity** | 22 m/s² downward; air steering limited |
| **Landing rating** | 5-tier: `Perfect! / Good! / OK / Poor / Crash!` based on slope angle and impact speed |
| **Slope-aware landing** | Lands on downhill slope → speed boost. Lands on uphill/wall → speed loss / crash |
| **Speed decay** | Speed bleeds off `1.2 m/s` per second so every landing matters |
| **Camera FOV** | Widens from 70° → 95° as speed grows for sense-of-speed |
| **Safe margin** | 0.08 m to prevent tunnelling through terrain at high speeds |
| **Floor stop on slope** | Disabled — player flies off ramps naturally |

### Terrain generation (`scripts/TerrainChunk.gd`)

- **Visual mesh:** 64×64 vertex heightmap with **smooth per-vertex normals** computed from world-space noise samples (no chunk-seam normals)
- **Collider:** 32×32 `ConcavePolygonShape3D` (cheaper than visual but still accurate for slope detection)
- **Heightmap:** 3-octave Simplex noise — rolling hills + bumps + a wide slow swell
- **Obstacles:** 4 random rocks per chunk with collision on the Obstacles physics layer

### Terrain shader (`assets/terrain.gdshader`)

A custom spatial shader that gives the ground a **smooth, natural** look with **no visible facets**:

- **Height-based color gradient:** valley (dark green) → grass (green) → dirt (brown) → rock (gray) → snow (white) at high altitude
- **Slope-based rock tint:** steep surfaces automatically get a rock color (no grass on cliffs)
- **FBM noise variation:** 5-octave fractal noise adds patches of darker/lighter ground
- **Micro noise:** tiny pebble-like variation for surface detail
- Smooth shading (interpolated normals across triangles) means **no visible polygon edges**

### World streaming (`scripts/WorldManager.gd`)

Registered as an **autoload** singleton. Maintains a 7×8 chunk grid around the player:

- Spawns new chunks ahead as the player runs (in `-Z` direction)
- Despawns chunks behind the player with a "crumble" effect (sink + tilt + queue_free)
- Truly **endless** — no upper bound on chunk coordinates
- Tracks `void_position_z` — advances at fixed `9 m/s` in `-Z` direction (less than player's base `14 m/s` so they can outrun it)

### Crumbling void (`scenes/CrumblingVoid.tscn`, `scripts/CrumblingVoid.gd`)

- Tall dark slab perpendicular to the Z axis, follows `WorldManager.void_position_z`
- Spawns `GPUParticles3D` debris emitters along its surface
- If the player's z falls within `3 m` of the void, the player dies
- Death is checked in `WorldManager._process` (which has the canonical void position)

### Camera controls (`scripts/CameraRig.gd`)

- **Third-person orbit camera** around the player
- **Mouse movement** rotates camera (yaw + pitch, with pitch clamped to prevent bird's-eye or underground views)
- **Scroll wheel** zooms in/out (clamped to 3.5–14 m)
- **Click to capture** mouse; **ESC** releases
- **Look-ahead** nudge based on player velocity for sense of motion
- Player's forward direction is **independent** of camera (auto-runs `-Z` regardless of camera orbit)

### HUD (`scenes/HUD.tscn`, `scripts/HUD.gd`)

- **Speed** (top right, color-coded by tier)
- **Distance** (top left)
- **Landing rating pop-up** (centered, color-coded by rating)
- **Hints** (bottom right)
- **Game-over overlay** with a Restart button

## File Structure

```
HasteLike_Godot/
├── project.godot              # Godot 4.5.1 project config + input map
├── icon.svg                   # Project icon
├── README.md                  # This file
├── .gitignore
├── assets/
│   └── terrain.gdshader       # Custom terrain shader (height colors + noise)
├── scenes/
│   ├── Main.tscn              # World env + sun + Player + Void + HUD
│   ├── Player.tscn            # CharacterBody3D with 3D humanoid model
│   ├── TerrainChunk.tscn      # Procedural chunk template (mesh + collider)
│   ├── CrumblingVoid.tscn     # Void wall template
│   └── HUD.tscn               # Canvas layer with labels + buttons
└── scripts/
    ├── Main.gd                # Wires everything together, handles ESC/P
    ├── Player.gd              # Haste-like movement + landing + safety net
    ├── CameraRig.gd           # Mouse-look third-person camera
    ├── TerrainChunk.gd        # Procedural mesh + smooth normals + shader
    ├── WorldManager.gd        # Autoload: chunk streaming + void tracking
    ├── CrumblingVoid.gd       # Chasing void wall (visual)
    └── HUD.gd                 # Speed/distance/landing UI
```

## Tuning

All the Haste-feel numbers live as `@export` variables at the top of `Player.gd`, `CameraRig.gd`, `WorldManager.gd`, and `TerrainChunk.gd`. Tweak them in the Godot inspector.

Key tunables:

| File | Variable | Default | Effect |
|---|---|---|---|
| `Player.gd` | `base_speed` | 14 m/s | Auto-run baseline |
| `Player.gd` | `max_speed` | 65 m/s | Hard cap from perfect landings |
| `Player.gd` | `safe_margin` | 0.08 m | Prevents tunnelling through terrain |
| `CameraRig.gd` | `mouse_sensitivity` | 0.0028 | Mouse look speed |
| `CameraRig.gd` | `zoom_default` | 7.5 m | Default camera distance |
| `WorldManager.gd` | `VOID_VELOCITY` | 9 m/s | How fast the void advances |
| `WorldManager.gd` | `VOID_LAG_DISTANCE` | 250 m | Initial gap between player and void |
| `TerrainChunk.gd` | `visual_resolution` | 64 | Vertices per side (higher = smoother) |
| `TerrainChunk.gd` | `collider_resolution` | 32 | Collider tri count (lower = cheaper) |

## Notes & Known Caveats

1. **No external 3D model file** — the player is built entirely from Godot primitive meshes so the project ships zero binary assets.

2. **Procedural animations** — the run cycle, air pose, and landing crouch are driven in code. The `AnimationPlayer` node is wired up so future keyframed animations can be added.

3. **Smooth terrain** — the visual mesh uses smooth per-vertex normals computed from world-space noise samples. This eliminates visible polygon edges across triangle boundaries and chunk seams.

4. **Endless world** — no upper bound on chunk coordinates. Memory is managed by despawning chunks out of range.

5. **Mouse capture** — clicking the game window captures the mouse for camera control. ESC releases. The mouse is also auto-released when game-over panel is shown.

---

Built for the user's Haste-like project. Adjust as needed.
