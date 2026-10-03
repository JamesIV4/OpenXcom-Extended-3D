# X-COM 3D Unit Animation & Directional Attack Previewer

An interactive 3D utility for real-time preview and inspection of unit animations, directional attack hits, projectile trajectories, wound decal placement, surface-normal blood sprays, and ragdoll death transitions across all 3D unit types.

---

## Quick Start

You can run the utility using any of the following methods:

### Method 1: Double-Click (Windows)
Double-click `run_unit_preview.bat` in the repository root.

### Method 2: PowerShell
Run from the repository root:
```powershell
powershell -ExecutionPolicy Bypass -File .\run_unit_preview.ps1
```

Options:
```powershell
# Specify unit type and model version:
powershell -ExecutionPolicy Bypass -File .\run_unit_preview.ps1 -Unit SNAKEMAN -Version opus-v6

# Launch in custom resolution:
powershell -ExecutionPolicy Bypass -File .\run_unit_preview.ps1 -Resolution 1920x1080 -Fullscreen
```

### Method 3: Direct Godot Command
```powershell
C:/GameDev/Godot_v4.7-stable_win64/Godot_v4.7-stable_win64_console.exe --path xcom-3d-godot/unit-lab res://scenes/unit_previewer.tscn
```

---

## Key Features

### Blood particles

Hit sprays use five one-shot `GPUParticles3D` emitters: three size/lifetime bands totaling 220 independent droplets (50% fine, 32% medium, 18% large), seven original mist puffs, and a tapered emission of much larger drifting mist puffs. Droplets vary in direction, speed, size, and lifetime, with larger size bands tending to survive longer; mist expands and fades smoothly. The large plume tapers its emission over about 0.22?0.24 seconds, fades early, and curves gently downward under gravity. Each hit uses fresh particle randomness. The existing surface raycast supplies the origin, with a 4 mm outward nudge for directional hits. Particles remain in world space as the unit reacts.

Droplet silhouettes are procedural and independently randomized: rounded uneven blobs, asymmetric drops with trailing necks, and small connected liquid lobes. Each particle keeps its shape seed throughout its life, with slight continuous deformation and varied aspect/tilt, so the outlines do not flicker or replay a flipbook. Fine/medium/large size and lifetime bands still apply; mist behavior is unchanged.

Shape research: [CGHOW?s hit-blood breakdown](https://cghow.com/hit-blood-impact-unreal-engine-niagara-tutorial/) combines drop and splash layers with randomized motion, lifetime, and separate mist. This implementation uses that layered approach with procedural silhouettes instead of its animated textures. [Godot?s spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) documents particle instance data; a randomized animation-offset channel carries the stable shape seed without playing animation frames.

All unit blood classes inherit this effect from `scripts/unit_blood.gd`, using `scripts/blood_particles.gd` and `shaders/blood_particle.gdshader`. Both layers use the sidecar's `per_unit_parameter.blood_color_srgb`. Future species require no spray texture or species-specific particle code. Skin impact decals (including the bullet hole) use a higher sorting offset than the blood runs, keeping the wound above overlapping drips as the camera or unit moves. Drip width and length are scaled to 65% of their sidecar sizes.

The reference lifespan comes from `spray.runtime.lifetime_s` (0.4 seconds when absent; current newer profiles use 0.45 seconds). Legacy `particle_quad_m` supplies overall species scale; old flipbook animation, velocity, inset, and depth-pull settings no longer drive the spray. Optional `spray.particles` settings override the shared defaults:

| Setting | Default | Meaning |
| --- | --- | --- |
| `lifetime_s` | Existing runtime value | Reference life: small/medium/large droplets use 0.65/0.95/1.3 times this, original mist 1 times, large mist 1.55 times; individual lives vary randomly |
| `size_scale` | Legacy quad size / 0.95 | Scales droplet/puff sizes and travel |
| `droplet_count`, `mist_count` | 220, 7 | Particles per hit |
| `droplet_diameter_m` | [0.006, 0.075] | Droplet width range before species scale |
| `mist_diameter_m` | [0.20, 0.42] | Fully expanded puff diameter range |
| `velocity_mps`, `mist_velocity_mps` | [0.45, 2.6], [0.18, 0.65] | Launch speed ranges before species scale |
| `large_mist_count`, `large_mist_diameter_m` | 14 maximum, [0.75, 1.35] | Additional conical translucent plume traveling toward the attacker |
| `large_mist_lifetime_scale`, `large_mist_velocity_mps` | 1.55, [0.7, 1.5] | Lingering cloud duration multiplier and launch speed |
| `spread_deg`, `mist_spread_deg` | 26, 38 | Emission cone spread |

Run the rendered regression check with a GPU (not headless):

```powershell
& C:/GameDev/Godot_v4.7-stable_win64/Godot_v4.7-stable_win64_console.exe --path xcom-3d-godot/unit-lab --fixed-fps 60 --script res://tools/check_blood_particles.gd
```

It checks surface placement, species tint, lifespan, automatic cleanup, clearing during emission, and a texture-free future species with a different random burst on repeated hits. Captures at 0.05, 0.15, 0.30, 0.55, and 0.75 seconds go to `%APPDATA%/Godot/app_userdata/Unit Lab/blood_particles_check`.

### 1. Unit & Model Version Selection

Use the **Unit type** dropdown to switch units and the **Model** dropdown to select a version.

- **HUMAN (WIP)**: `wip-v1`, the unfinished XCOM_1 male geometry checkpoint. Supports camera inspection and facing controls. Animation, combat, and ragdoll controls are disabled until those assets exist. Launch directly with `./run_unit_preview.ps1 -Unit HUMAN`.

The preview copy is exported from `art/team/units_opus55/editable/v01/XCOM_1_male_geometry.blend` without changing the source or marking it finished. Regenerate it with Blender in background mode using `--python xcom-3d-godot/unit-lab/tools/export_human_wip.py`.

- **SECTOID**: `opus-v6` (Latest fitted ragdoll & materials), `opus-v5`, `opus-v4` (Directional hits & twist), `opus-v3`, `opus-v2`.
- **SNAKEMAN**: `opus-v6` (Latest fitted coils & blood), `opus-v5`, `opus-v4`, `opus-v3`, `opus-v2`, `opus-v1`.
- **FLOATER**: `opus-v1` (Machine cybernetic body & hover), with surface-hit wound variants and growing drips attached to the hit bone, using its purple blood color (`#975db4`). Both camera clicks and directional attacks place these effects on impact; lethal hits use the same localized wounds.
- **Unit Facing Controls**: Adjust unit facing 0°–360° (with quick `N`, `E`, `S`, `W` buttons). Facing updates the ground indicator arrow in real-time.

### 2. Animation Player & Timeline Inspector
- Categorized animation buttons:
  - **Locomotion**: `Idle`, `IdleArmed`, `Walk`, `WalkArmed`, `Kneel`
  - **Combat**: `Attack`
  - **Directional Hits**: `HitFront`, `HitBack`, `HitLeft`, `HitRight`, `Hit`
  - **Directional Deaths**: `DeathFront`, `DeathBack`, `DeathLeft`, `DeathRight`, `Death`, `DeathBaked`
- **Controls**:
  - Play / Pause toggle
  - Speed scale slider & presets (`0.1x`, `0.25x`, `0.5x`, `1.0x`, `2.0x`) for high-fidelity slow-motion inspection
  - Interactive Scrubber timeline with real-time frame and timestamp display (`current / total`)
  - Frame stepping (`◀ -1F` and `+1F ▶`) for frame-by-frame analysis

### 3. Directional Attack Hits System
- **Attack Direction**:
  - 8 Quick Compass direction buttons (`N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`)
  - 360° smooth attack angle slider
  - Target height selector (`Head ~1.3m`, `Chest ~0.85m`, `Pelvis/Lower ~0.4m`)
- **Live Relative Sector Computation**:
  - Automatically calculates relative angle between attacker trajectory and current unit facing.
  - Displays color-coded sector badge:
    - **FRONT** (Green): `HitFront` / `DeathFront`
    - **BACK** (Red): `HitBack` / `DeathBack`
    - **LEFT** (Orange): `HitLeft` / `DeathLeft`
    - **RIGHT** (Blue): `HitRight` / `DeathRight`
- **Hit Simulation Actions**:
  - **Non-Lethal Hit** (`Space` / `H`):
    - Fires projectile tracer from attacker marker to target.
    - Raycasts against skinned mesh to pinpoint exact impact bone.
    - Places entry wound decal attached to hit bone (follows animation/ragdoll).
    - Spawns blood spray bursting back out along surface normal towards shooter.
    - Triggers directional flinch reaction.
  - **Lethal Attack (Kill)** (`K`):
    - Triggers projectile tracer and impact flash.
    - Applies entry wound decal.
    - Spawns blood spray and floor splatter.
    - Triggers directional death recoil animation (`DeathFront`, `DeathBack`, etc.).
    - Hands off to ragdoll physics with impulse and whole-body twist toward shooter.
    - On settling, freezes pose and spawns blood pool under torso.
    - Reports settle metrics (settle time, reason, mesh outside tile).
  - **Unit Attack Animation** (`A`):
    - Unit performs its attack animation with weapon visible and fires a muzzle flash and projectile forward.
  - **Auto-Play 8 Directions**:
    - Automatically sequences attacks across all 8 compass directions.

### 4. Interactive Health & Camera-Fire System (3 Hits to Kill)
- **Left-Click on Unit**:
  - Casts a ray from the camera through the mouse click directly onto the unit's body (head, chest, arms, coils, etc.).
  - Fires a projectile tracer directly from the camera to the clicked location.
  - Places a wound decal at the clicked bone and triggers normal-aligned blood spray.
  - Plays the directional reaction corresponding to the camera's angle relative to the unit's facing.
- **3 Hits to Kill Preview**:
  - The character starts with **3 / 3 HP**.
  - **Hit 1 & 2**: Non-lethal hits (flinch animation, entry wound decal attached to hit bone, directional blood spray along surface normal, HUD updates to `2/3` then `1/3`).
  - **Hit 3 (Fatal)**: Lethal strike (directional death recoil, whole-body twist toward camera, seamless physics ragdoll hand-off, settling into blood pool, HUD updates to `0/3 HP DEAD`).
  - **Auto-Revive on Click**: Clicking on a dead or dying character automatically revives them to 3 HP and immediately begins a fresh sequence.
- **Clean 3D Alien Visuals**:
  - The 3D view of the alien remains completely clean and unobstructed (no floating health bars or damage numbers rendered over the alien).
  - Health is displayed prominently in the HUD right panel card (`HEALTH: [ ■ ■ ■ ] 3/3 HP`) and bottom status bar, color-coded from Green (3 HP) -> Yellow (2 HP) -> Orange (1 HP) -> Red (0 HP DEAD).

### 5. Camera Controls & Navigation
- **Middle Mouse Button (MMB Drag)** or **Right Mouse Button (RMB Drag)**: **Rotates / orbits the camera** smoothly around the unit from any view without jumping.
- **Shift + MMB / RMB Drag**: Pans the camera focus point.
- **Mouse Wheel**: Zooms in and out (smooth distance zoom in perspective modes, orthogonal scale zoom in review/top-down modes).
- **Preset Cameras**:
  - **Review SE (Battlescape Default)**: 30° orthographic camera from South-East (yaw 45°).
  - **Review NE / NW / SW**: Quarter-turn review angles.
  - **Top-Down**: Orthogonal bird's-eye view with 2m tile outline.
  - **Attacker POV**: First-person perspective looking down the sights of the shooter directly at the unit.
  - **Close-Up Focus**: Zoomed perspective focused on the chest/head impact area.
  - **Orbit 3D**: Free orbit camera.

### 6. Telemetry & Diagnostics
- Live readout of:
  - Relative hit variant (`Front`, `Back`, `Left`, `Right`)
  - Remaining HP (`3/3`, `2/3`, `1/3`, `0/3 DEAD`)
  - Bone hit (e.g. `head`, `spine_03`, `upperarm_l`)
  - Hit coordinates `(X, Y, Z)`
  - Surface normal and angle of incidence
  - Raycast calculation time in milliseconds
  - Ragdoll settle metrics (settle time, reason, mesh outside tile, twist rad/s)
- **Reset Unit** (`R`): Clears wounds, ragdoll bodies, and restores fresh unit at 3/3 HP.
- **Clear Blood Only**: Removes decals and pools while preserving current animation pose.

---

## Hotkey Reference

| Key / Mouse | Action |
| :--- | :--- |
| **`Left-Click on Unit`** | **Fire shot directly from camera to clicked point** (3 hits to kill) |
| **`Middle-Click Drag`** or **`Right-Click Drag`** | **Rotate camera** (smooth orbit around unit) |
| **`Shift + Drag (MMB / RMB)`** | Pan camera focus point |
| **`Mouse Wheel`** | Zoom camera in / out |
| **`Space`** or **`H`** | Fire Non-Lethal Hit (deals 1 damage) |
| **`K`** | Fire Lethal Attack (instant kill / ragdoll) |
| **`A`** | Trigger Unit Attack animation & fire weapon |
| **`R`** | Reset Unit to fresh 3/3 HP state |
| **`C`** | Cycle through Camera presets |
| **`1` .. `8`** | Quick-set attack compass directions (`N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`) |
| **`[`** / **`]`** | Decrease / Increase animation playback speed |
| **`Tab`** | Toggle / Hide UI overlay for unobstructed view |
