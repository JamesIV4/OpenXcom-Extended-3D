## Unit Animation & Directional Attack Previewer
## Interactive 3D preview utility for OpenXcom 3D units:
## - Unit switching (Sectoid, Snakeman, Floater) and model versions (opus-v1..v6)
## - Full animation preview with playback controls, timeline scrubber, slow-motion (0.05x-2.0x), frame stepping
## - Middle mouse button rotates camera across all angles with smooth orbit controls
## - Left-click on the unit fires a hit from the camera to the clicked location
## - Health system: 3 hits to kill preview with HUD health bar & telemetry (clean 3D view, no floating text over alien)
## - Directional attack hit simulation from 8 compass directions or arbitrary 360-degree angles
## - Live relative hit sector calculation (Front / Back / Left / Right) based on unit facing
## - Visual 3D projectile tracers, muzzle flashes, and impact sparks
## - Non-lethal hits with raycasted wound decals & surface-normal blood spray
## - Lethal hits with directional recoils, ragdoll hand-off, whole-body twist toward shooter, and settle reports
## - Multiple tactical cameras (Review SE/NE/NW/SW, Top, Attacker POV, Close-up, Orbit 3D)
extends Node3D

const TILE_M := 2.0
const REVIEW_PITCH := deg_to_rad(30.0)
const REVIEW_YAW := deg_to_rad(45.0)
const MAX_HP := 3

# Preloads of unit classes
const SectoidV4Class := preload("res://scripts/sectoid_v4/sectoid_v4_lab_unit.gd")
const SnakemanV2Class := preload("res://scripts/snakeman_v2/snakeman_v2_lab_unit.gd")
const FloaterClass := preload("res://scripts/floater/floater_lab_unit.gd")
const HumanWipClass := preload("res://scripts/human_wip_unit.gd")
const LabMainClass := preload("res://scripts/lab_main.gd")

# Unit catalog
const UNITS_CATALOG := {
	"HUMAN": {
		"class": HumanWipClass,
		"label": "Human (WIP)",
		"inspection_only": true,
		"review_height": 1.0,
		"review_size": 3.7,
		"default_version": "wip-v1",
		"versions": [{"id": "wip-v1", "label": "WIP v1 (Geometry checkpoint)", "path": "res://assets/models/units/HUMAN/HUMAN.wip-v1.glb"}],
		"chest_height": 1.25,
		"head_height": 1.7,
	},
	"SECTOID": {
		"class": SectoidV4Class,
		"default_version": "opus-v6",
		"versions": [
			{"id": "opus-v6", "label": "opus-v6 (Latest fitted ragdoll & blood)", "path": "res://assets/models/units/SECTOID/SECTOID.opus-v6.gltf"},
			{"id": "opus-v5", "label": "opus-v5 (Fitted limits)", "path": "res://assets/models/units/SECTOID/SECTOID.opus-v5.gltf"},
			{"id": "opus-v4", "label": "opus-v4 (Directional hits & twist)", "path": "res://assets/models/units/SECTOID/SECTOID.opus-v4.gltf"},
			{"id": "opus-v3", "label": "opus-v3", "path": "res://assets/models/units/SECTOID/SECTOID.opus-v3.gltf"},
			{"id": "opus-v2", "label": "opus-v2 (Original)", "path": "res://assets/models/units/SECTOID/SECTOID.opus-v2.gltf"},
		],
		"chest_height": 0.82,
		"head_height": 1.25,
	},
	"SNAKEMAN": {
		"class": SnakemanV2Class,
		"default_version": "opus-v6",
		"versions": [
			{"id": "opus-v6", "label": "opus-v6 (Latest fitted coils & blood)", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v6.gltf"},
			{"id": "opus-v5", "label": "opus-v5", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v5.gltf"},
			{"id": "opus-v4", "label": "opus-v4", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v4.gltf"},
			{"id": "opus-v3", "label": "opus-v3", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v3.gltf"},
			{"id": "opus-v2", "label": "opus-v2", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v2.gltf"},
			{"id": "opus-v1", "label": "opus-v1 (Original)", "path": "res://assets/models/units/SNAKEMAN/SNAKEMAN.opus-v1.gltf"},
		],
		"chest_height": 0.95,
		"head_height": 1.40,
	},
	"FLOATER": {
		"class": FloaterClass,
		"default_version": "opus-v1",
		"versions": [
			{"id": "opus-v1", "label": "opus-v1 (Machine cybernetic hover)", "path": "res://assets/models/units/FLOATER/FLOATER.opus-v1.gltf"},
		],
		"chest_height": 0.90,
		"head_height": 1.30,
	}
}

const COMPASS_DIRS := {
	"N": {"angle": 0.0, "dir": Vector3(0, 0, 1)},
	"NE": {"angle": 45.0, "dir": Vector3(-0.707107, 0, 0.707107)},
	"E": {"angle": 90.0, "dir": Vector3(-1, 0, 0)},
	"SE": {"angle": 135.0, "dir": Vector3(-0.707107, 0, -0.707107)},
	"S": {"angle": 180.0, "dir": Vector3(0, 0, -1)},
	"SW": {"angle": 225.0, "dir": Vector3(0.707107, 0, -0.707107)},
	"W": {"angle": 270.0, "dir": Vector3(1, 0, 0)},
	"NW": {"angle": 315.0, "dir": Vector3(0.707107, 0, 0.707107)}
}

# State
var current_unit_type := "SECTOID"
var current_version_id := "opus-v6"
var current_hp := MAX_HP
var unit_facing_deg := 0.0
var attack_angle_deg := 0.0
var attack_height_mode := 1 # 0: Head, 1: Chest, 2: Pelvis/Lower, 3: Custom
var custom_height := 0.85
var speed_scale := 1.0
var is_scrubbing := false
var auto_cycle_active := false
var auto_cycle_index := 0
var auto_cycle_timer := 0.0
var auto_cycle_lethal := false

# Scene Nodes
var fx_root: Node3D
var camera: Camera3D
var unit: LabUnit
var attacker_marker: Node3D
var targeting_laser: MeshInstance3D
var facing_arrow: Node3D
var ground_compass: Node3D

# Camera Control
var cam_mode := 0 # 0..3 Review (SE, NE, NW, SW), 4: Top, 5: Attacker POV, 6: Focus, 7: Orbit
var orbit_yaw := deg_to_rad(45.0)
var orbit_pitch := deg_to_rad(25.0)
var orbit_dist := 3.8
var orbit_target := Vector3(0, 0.8, 0)
var is_orbit_dragging := false
var orbit_drag_button := 0


# UI Elements
var ui_layer: CanvasLayer
var ui_root: Control
var top_panel: PanelContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var status_panel: PanelContainer
var hp_bar_label: Label
var anim_buttons_container: VBoxContainer
var scrubber_slider: HSlider
var scrubber_label: Label
var play_pause_btn: Button
var loop_btn: CheckBox
var speed_label: Label
var unit_status_badge: Label
var sector_badge: Label
var sector_desc_label: Label
var telemetry_label: Label
var facing_slider: HSlider
var facing_label: Label
var attack_slider: HSlider
var attack_label: Label
var version_option_btn: OptionButton
var unit_type_option_btn: OptionButton
var animation_combat_controls: Array[BaseButton] = []


func _ready() -> void:
	_parse_cmdline_args()

	# Build world environment, sun light, floor with shader
	LabMainClass.build_world(self)

	# FX root for decals, blood, lasers, sparks
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)

	# Camera setup
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)

	# 3D Visual Aids
	_build_3d_helpers()

	# Build interactive HUD
	_build_ui()

	# Spawn default unit
	spawn_selected_unit()

	# Initial camera & visuals update
	_update_camera()
	_update_attacker_visuals()
	_update_relative_sector_ui()


func _parse_cmdline_args() -> void:
	var args := OS.get_cmdline_user_args()
	var u_idx := args.find("--unit")
	if u_idx >= 0 and args.size() > u_idx + 1:
		var u_name := args[u_idx + 1].to_upper()
		if UNITS_CATALOG.has(u_name):
			current_unit_type = u_name

	var v_idx := args.find("--version")
	if v_idx >= 0 and args.size() > v_idx + 1:
		current_version_id = args[v_idx + 1]


func _process(delta: float) -> void:
	# Update animation scrubber while playing
	if unit and is_instance_valid(unit) and unit.anim and not is_scrubbing:
		var ap: AnimationPlayer = unit.anim
		if ap.is_playing():
			var cur := ap.current_animation_position
			var total := ap.current_animation_length
			if total > 0.0:
				scrubber_slider.set_value_no_signal(cur / total)
				var frame_idx := int(cur * 60.0)
				var total_frames := int(total * 60.0)
				scrubber_label.text = "%.2fs / %.2fs  [F%d / %d]" % [cur, total, frame_idx, total_frames]

	# Auto-cycle logic
	if auto_cycle_active:
		auto_cycle_timer += delta
		var cycle_period := 3.2 if auto_cycle_lethal else 1.2
		if auto_cycle_timer >= cycle_period:
			auto_cycle_timer = 0.0
			_step_auto_cycle()


func _step_auto_cycle() -> void:
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var d_name: String = dirs[auto_cycle_index % dirs.size()]
	auto_cycle_index += 1
	set_attack_compass_direction(d_name)
	if auto_cycle_lethal:
		fire_attack(true)
	else:
		fire_attack(false)


# ------------------------------------------------------------------ 3D Visual Helpers
func _build_3d_helpers() -> void:
	# Ground compass ring
	ground_compass = Node3D.new()
	ground_compass.name = "GroundCompass"
	add_child(ground_compass)

	var radius := 2.25
	for dir_name in COMPASS_DIRS.keys():
		var info: Dictionary = COMPASS_DIRS[dir_name]
		var ang: float = deg_to_rad(info["angle"])
		var marker_pos := Vector3(-sin(ang), 0.015, -cos(ang)) * radius
		var lbl := Label3D.new()
		lbl.text = dir_name
		lbl.font_size = 32
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.4, 0.8, 1.0, 0.85) if (dir_name.length() == 1) else Color(0.6, 0.7, 0.8, 0.6)
		lbl.outline_modulate = Color.BLACK
		lbl.outline_size = 3
		lbl.position = marker_pos
		lbl.rotation.x = -PI * 0.5
		lbl.rotation.y = 0
		ground_compass.add_child(lbl)

	# Central tile border highlight (2m x 2m)
	var tile_box := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var c := 1.0 # half of 2m
	im.surface_add_vertex(Vector3(-c, 0.005, -c))
	im.surface_add_vertex(Vector3(c, 0.005, -c))
	im.surface_add_vertex(Vector3(c, 0.005, c))
	im.surface_add_vertex(Vector3(-c, 0.005, c))
	im.surface_add_vertex(Vector3(-c, 0.005, -c))
	im.surface_end()
	tile_box.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.2, 0.7, 1.0, 0.5)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tile_box.material_override = line_mat
	add_child(tile_box)

	# Facing arrow on ground
	facing_arrow = Node3D.new()
	facing_arrow.name = "FacingArrow"
	var arrow_mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.25, 0.45, 0.04)
	arrow_mesh.mesh = prism
	arrow_mesh.rotation.x = -PI * 0.5
	arrow_mesh.rotation.y = PI
	arrow_mesh.position = Vector3(0, 0.02, -1.2)
	var arr_mat := StandardMaterial3D.new()
	arr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arr_mat.albedo_color = Color(0.1, 1.0, 0.4, 0.85)
	arrow_mesh.material_override = arr_mat
	facing_arrow.add_child(arrow_mesh)
	add_child(facing_arrow)

	# Attacker marker (3D floating reticle)
	attacker_marker = Node3D.new()
	attacker_marker.name = "AttackerMarker"
	var reticle_mesh := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.12
	tor.outer_radius = 0.16
	reticle_mesh.mesh = tor
	reticle_mesh.rotation.x = PI * 0.5
	var ret_mat := StandardMaterial3D.new()
	ret_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ret_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.9)
	reticle_mesh.material_override = ret_mat
	attacker_marker.add_child(reticle_mesh)

	var pointer := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.25
	pointer.mesh = cone
	pointer.rotation.x = -PI * 0.5
	pointer.position = Vector3(0, 0, 0.18)
	pointer.material_override = ret_mat
	attacker_marker.add_child(pointer)
	add_child(attacker_marker)

	# Targeting laser line
	targeting_laser = MeshInstance3D.new()
	targeting_laser.name = "TargetingLaser"
	var laser_mat := StandardMaterial3D.new()
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.35)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	targeting_laser.material_override = laser_mat
	add_child(targeting_laser)


# ------------------------------------------------------------------ Unit Spawning & Health
func spawn_selected_unit() -> void:
	if unit and is_instance_valid(unit):
		unit.blood.clear()
		unit.queue_free()
		unit = null

	var u_info: Dictionary = UNITS_CATALOG[current_unit_type]
	var u_class: GDScript = u_info["class"]

	var model_path: String = ""
	for v in u_info["versions"]:
		if v["id"] == current_version_id:
			model_path = v["path"]
			break
	if model_path == "":
		model_path = u_info["versions"][0]["path"]
		current_version_id = u_info["versions"][0]["id"]

	unit = u_class.new()
	unit.name = current_unit_type.capitalize()
	unit.model_path = model_path
	unit.fx_root = fx_root
	unit.rotation.y = deg_to_rad(unit_facing_deg)
	add_child(unit)

	unit.died.connect(_on_unit_died)
	unit.play("Idle")

	# Reset HP
	current_hp = MAX_HP
	_update_hp_ui()

	_rebuild_animation_buttons()
	auto_cycle_active = false
	for control in animation_combat_controls:
		control.disabled = u_info.get("inspection_only", false)
	scrubber_slider.editable = not u_info.get("inspection_only", false)
	_update_camera()
	if u_info.get("inspection_only", false):
		_update_unit_status_badge("WIP - GEOMETRY PREVIEW")
		telemetry_label.text = "Human WIP checkpoint. Inspect with camera and facing controls. Animation and combat setup are not available yet."
	else:
		_update_unit_status_badge("ALIVE [Idle]")
	_update_attacker_visuals()
	_update_relative_sector_ui()


func _update_hp_ui() -> void:
	var hp_string := ""
	var col := Color(0.2, 1.0, 0.4)
	match current_hp:
		3:
			hp_string = "■ ■ ■  3 / 3 HP"
			col = Color(0.2, 1.0, 0.4) # Green
		2:
			hp_string = "■ ■ □  2 / 3 HP"
			col = Color(0.95, 0.9, 0.2) # Yellow
		1:
			hp_string = "■ □ □  1 / 3 HP"
			col = Color(1.0, 0.5, 0.1) # Orange
		0:
			hp_string = "□ □ □  0 / 3 HP (DEAD)"
			col = Color(1.0, 0.2, 0.2) # Red

	if hp_bar_label:
		hp_bar_label.text = " HEALTH: [ %s ]" % hp_string
		hp_bar_label.add_theme_color_override("font_color", col)


func _on_unit_died(report: Dictionary) -> void:
	current_hp = 0
	_update_hp_ui()
	_update_unit_status_badge("DEAD [Settled]")
	var settle_t := float(report.get("settle_time_s", -1.0))
	var reason: String = report.get("settle_reason", "unknown")
	var mesh_out := float(report.get("mesh_outside_tile_m", 0.0))
	var twist := float(report.get("twist_radps", 0.0))
	var align := float(report.get("fall_alignment", 0.0))
	var lift := float(report.get("depenetration_lift_m", 0.0))

	var info_text := "RAGDOLL SETTLED:\n  Time: %.2fs (%s)\n  Mesh outside tile: %.3fm\n  Twist: %.2f rad/s\n  Fall alignment: %.2f\n  Depenetration lift: %.3fm" % [
		settle_t, reason, mesh_out, twist, align, lift
	]
	telemetry_label.text = info_text


# ------------------------------------------------------------------ Raycasting & Unit Intersection
## Raycasts against the unit via skinned mesh, physics bodies, or geometry proximity bounds.
func raycast_unit(ray_from: Vector3, ray_dir: Vector3) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {}

	# 1. Try unit's own CPU-skinned mesh raycast
	if unit.has_method("raycast_body"):
		var h: Dictionary = unit.raycast_body(ray_from, ray_dir)
		if not h.is_empty():
			return h

	# 2. Try physics raycast against ragdoll/static bodies (layer 1)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * 80.0)
	query.collision_mask = UnitRagdoll.BODY_LAYER
	var res := space_state.intersect_ray(query)
	if not res.is_empty():
		return {
			"point": res.position,
			"normal": res.normal,
			"bone": "spine_03",
			"distance_m": ray_from.distance_to(res.position)
		}

	# 3. Geometric proximity check to the unit vertical axis (allows clicking any part)
	var max_h := 1.75
	if current_unit_type == "FLOATER":
		max_h = 1.9
	elif current_unit_type == "SECTOID":
		max_h = 1.45
	elif current_unit_type == "SNAKEMAN":
		max_h = 1.85

	var base_pos: Vector3 = unit.global_position
	var p0 := base_pos + Vector3(0, 0.05, 0)
	var p1 := base_pos + Vector3(0, max_h, 0)
	var seg_dir := (p1 - p0)

	var w0 := ray_from - p0
	var a := ray_dir.dot(ray_dir)
	var b := ray_dir.dot(seg_dir)
	var c := seg_dir.dot(seg_dir)
	var d := ray_dir.dot(w0)
	var e := seg_dir.dot(w0)

	var denom := a * c - b * b
	if absf(denom) > 1e-6:
		var s := (b * e - c * d) / denom
		var t := (a * e - b * d) / denom
		if s > 0.0 and t >= 0.0 and t <= 1.0:
			var pt_ray := ray_from + ray_dir * s
			var pt_seg := p0 + seg_dir * t
			var dist := pt_ray.distance_to(pt_seg)
			var threshold_radius := 0.70
			if dist <= threshold_radius:
				var nrm := (pt_ray - pt_seg).normalized()
				if nrm.length() < 0.1:
					nrm = -ray_dir
				return {
					"point": pt_ray,
					"normal": nrm,
					"bone": "spine_03",
					"distance_m": s
				}

	return {}


# ------------------------------------------------------------------ Left Click Hit Handling
func _is_click_on_ui(screen_pos: Vector2) -> bool:
	if not ui_root.visible:
		return false
	for p: Control in [top_panel, left_panel, right_panel, status_panel]:
		if p and p.is_visible_in_tree() and p.get_global_rect().has_point(screen_pos):
			return true
	return false


func _handle_viewport_left_click(screen_pos: Vector2) -> void:
	if UNITS_CATALOG[current_unit_type].get("inspection_only", false):
		return
	if _is_click_on_ui(screen_pos):
		return

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	var hit_info := raycast_unit(ray_from, ray_dir)
	if hit_info.is_empty():
		# Proximity fallback: test distance to unit vertical axis / center
		var base_pt := unit.global_position if (unit and is_instance_valid(unit)) else Vector3.ZERO
		var target_h := get_target_height()
		var center_pt := base_pt + Vector3(0, target_h, 0)
		var to_unit := center_pt - ray_from
		var t_proj := to_unit.dot(ray_dir)
		if t_proj > 0.0:
			var ray_pt := ray_from + ray_dir * t_proj
			var dist_to_center := ray_pt.distance_to(center_pt)
			if dist_to_center <= 1.25: # Within 1.25m generous hit cylinder
				hit_info = {
					"point": center_pt + (ray_pt - center_pt).normalized() * 0.25,
					"normal": -ray_dir,
					"bone": "spine_03",
					"distance_m": t_proj
				}

	if hit_info.is_empty():
		if telemetry_label:
			telemetry_label.text = "Click missed unit. Click directly on or near the character to fire."
		return # Did not click on or near the unit

	var click_pt: Vector3 = hit_info["point"]
	var hit_nrm: Vector3 = hit_info.get("normal", -ray_dir)
	var hit_bone: String = hit_info.get("bone", "spine_03")

	# Calculate shot from camera position to clicked point
	var shot_origin := camera.global_position
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		shot_origin = click_pt - ray_dir * 4.5

	var shot_dir := (click_pt - shot_origin).normalized()

	# Update attack angle & compass in UI to match camera
	var horiz_dir := Vector3(shot_dir.x, 0, shot_dir.z).normalized()
	attack_angle_deg = fposmod(rad_to_deg(atan2(-horiz_dir.x, horiz_dir.z)), 360.0)
	attack_slider.set_value_no_signal(attack_angle_deg)
	attack_label.text = "Attack Angle: %d° (Camera Click)" % int(attack_angle_deg)
	_update_attacker_visuals()
	_update_relative_sector_ui()

	# If dead, dying, or HP depleted, reset unit first
	if current_hp <= 0 or unit == null or not is_instance_valid(unit) or unit.dead or getattr(unit, "_dying", false):
		spawn_selected_unit()

	# Decrement HP (3 hits to kill)
	current_hp = maxi(0, current_hp - 1)
	var is_lethal := (current_hp <= 0)
	_update_hp_ui()

	# Tracer from camera to clicked point
	_spawn_tracer(shot_origin, click_pt, is_lethal, func() -> void:
		_execute_hit_impact_at_point(shot_origin, shot_dir, click_pt, hit_nrm, hit_bone, is_lethal)
	)


func _execute_hit_impact_at_point(origin: Vector3, shot_dir: Vector3, click_pt: Vector3, hit_nrm: Vector3, hit_bone: String, is_lethal: bool) -> void:
	if UNITS_CATALOG[current_unit_type].get("inspection_only", false):
		return
	if unit == null or not is_instance_valid(unit):
		return

	var rec: Dictionary = {}
	if unit.has_method("shoot"):
		rec = unit.shoot(origin, shot_dir, is_lethal)
	elif is_lethal:
		unit.die(shot_dir)
	else:
		unit.hit(shot_dir)
		if unit.blood:
			unit.blood.spray(click_pt, (hit_nrm - shot_dir).normalized())

	if is_lethal:
		_update_unit_status_badge("DYING (Recoil -> Ragdoll) [0/3 HP]")
	else:
		_update_unit_status_badge("HIT (Flinch) [%d/3 HP]" % current_hp)

	var variant: String = rec.get("variant", "")
	if variant == "" and unit.has_method("variant_of"):
		variant = unit.variant_of(shot_dir)

	telemetry_label.text = "LAST SHOT RESULT:\n  Source: Camera Click on Unit\n  Bone Hit: %s\n  Hit Point: (%.3f, %.3f, %.3f)\n  Sector: %s\n  Remaining HP: %d / 3\n  Lethal: %s" % [
		hit_bone, click_pt.x, click_pt.y, click_pt.z, variant, current_hp, str(is_lethal)
	]


# ------------------------------------------------------------------ Attack Calculation & Execution (Buttons / Angles)
func get_shot_vector() -> Vector3:
	var ang_rad := deg_to_rad(attack_angle_deg)
	return Vector3(-sin(ang_rad), 0.0, cos(ang_rad)).normalized()


func get_target_height() -> float:
	var u_info: Dictionary = UNITS_CATALOG[current_unit_type]
	match attack_height_mode:
		0: return float(u_info.get("head_height", 1.25))
		1: return float(u_info.get("chest_height", 0.85))
		2: return 0.40 # pelvis / lower
		3: return custom_height
	return 0.85


func get_attacker_position() -> Vector3:
	var target_pt := Vector3(0, get_target_height(), 0)
	var shot_dir := get_shot_vector()
	return target_pt - shot_dir * 3.5


func _update_attacker_visuals() -> void:
	var shot_dir := get_shot_vector()
	var target_pt := Vector3(0, get_target_height(), 0)
	var attacker_pt := get_attacker_position()

	attacker_marker.global_position = attacker_pt
	attacker_marker.look_at(target_pt, Vector3.UP)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(attacker_pt)
	im.surface_add_vertex(target_pt)
	im.surface_end()
	targeting_laser.mesh = im


func _update_relative_sector_ui() -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var shot_dir := get_shot_vector()
	var rel_variant := ""
	if unit.has_method("variant_of"):
		rel_variant = unit.variant_of(shot_dir)
	else:
		var l: Vector3 = unit.global_basis.inverse() * shot_dir
		var v := Vector2(l.x, -l.z).normalized()
		if v.y <= -0.7071:
			rel_variant = "Front"
		elif v.y >= 0.7071:
			rel_variant = "Back"
		else:
			rel_variant = "Left" if v.x > 0.0 else "Right"

	var color_hex := "#2ecc71"
	match rel_variant:
		"Front": color_hex = "#2ecc71"
		"Back": color_hex = "#e74c3c"
		"Left": color_hex = "#f39c12"
		"Right": color_hex = "#3498db"

	sector_badge.text = " SECTOR: %s " % rel_variant.to_upper()
	sector_badge.add_theme_color_override("font_color", Color(color_hex))

	var rel_angle_deg := fposmod(attack_angle_deg - unit_facing_deg + 180.0, 360.0) - 180.0
	sector_desc_label.text = "Attack angle: %d°  |  Facing: %d°\nRelative angle: %+d° -> Triggers Hit%s / Death%s" % [
		int(attack_angle_deg), int(unit_facing_deg), int(rel_angle_deg), rel_variant, rel_variant
	]


func set_attack_compass_direction(dir_name: String) -> void:
	if not COMPASS_DIRS.has(dir_name):
		return
	attack_angle_deg = COMPASS_DIRS[dir_name]["angle"]
	attack_slider.set_value_no_signal(attack_angle_deg)
	attack_label.text = "Attack Angle: %d° (%s)" % [int(attack_angle_deg), dir_name]
	_update_attacker_visuals()
	_update_relative_sector_ui()


func set_unit_facing(deg: float) -> void:
	unit_facing_deg = fposmod(deg, 360.0)
	if unit and is_instance_valid(unit):
		unit.rotation.y = deg_to_rad(unit_facing_deg)
	facing_arrow.rotation.y = deg_to_rad(unit_facing_deg)
	facing_slider.set_value_no_signal(unit_facing_deg)
	facing_label.text = "Unit Facing: %d°" % int(unit_facing_deg)
	_update_relative_sector_ui()


func fire_attack(is_lethal: bool) -> void:
	if UNITS_CATALOG[current_unit_type].get("inspection_only", false):
		return
	if unit == null or not is_instance_valid(unit):
		spawn_selected_unit()

	# If dead, settled, or HP depleted, respawn fresh first
	if current_hp <= 0 or unit.dead or getattr(unit, "_dying", false):
		spawn_selected_unit()

	# Update HP
	if is_lethal:
		current_hp = 0
	else:
		current_hp = maxi(0, current_hp - 1)
		if current_hp <= 0:
			is_lethal = true
	_update_hp_ui()

	var shot_dir := get_shot_vector()
	var origin := get_attacker_position()
	var target_pt := Vector3(0, get_target_height(), 0)

	_update_unit_status_badge("INCOMING FIRE..." if not is_lethal else "LETHAL STRIKE...")

	# Spawn visual tracer
	_spawn_tracer(origin, target_pt, is_lethal, func() -> void:
		_execute_hit_impact(origin, shot_dir, is_lethal)
	)


func _execute_hit_impact(origin: Vector3, shot_dir: Vector3, is_lethal: bool) -> void:
	if UNITS_CATALOG[current_unit_type].get("inspection_only", false):
		return
	if unit == null or not is_instance_valid(unit):
		return

	var rec: Dictionary = {}
	if unit.has_method("shoot"):
		rec = unit.shoot(origin, shot_dir, is_lethal)
	elif is_lethal:
		unit.die(shot_dir)
	else:
		unit.hit(shot_dir)

	if is_lethal:
		_update_unit_status_badge("DYING (Recoil -> Ragdoll) [0/3 HP]")
	else:
		_update_unit_status_badge("HIT (Flinch) [%d/3 HP]" % current_hp)

	if not rec.is_empty():
		var pt: Array = rec.get("point", [0, 0, 0])
		var bone: String = rec.get("bone", "none")
		var inc := float(rec.get("incidence_deg", 0.0))
		var ray_ms := float(rec.get("ray_ms", 0.0))
		var wound_kind: String = rec.get("wound", "none")
		var variant: String = rec.get("variant", "")

		telemetry_label.text = "LAST SHOT RESULT:\n  Variant: %s\n  Bone Hit: %s\n  Hit Point: (%.3f, %.3f, %.3f)\n  Incidence: %.1f°\n  Wound Type: %s\n  Raycast Time: %.2f ms\n  Remaining HP: %d / 3" % [
			variant, bone, pt[0], pt[1], pt[2], inc, wound_kind, ray_ms, current_hp
		]
	else:
		telemetry_label.text = "LAST SHOT RESULT:\n  Shot Vector: (%.2f, %.2f, %.2f)\n  Remaining HP: %d / 3\n  Lethal: %s" % [
			shot_dir.x, shot_dir.y, shot_dir.z, current_hp, str(is_lethal)
		]


func fire_unit_attack() -> void:
	if UNITS_CATALOG[current_unit_type].get("inspection_only", false):
		return
	if unit == null or not is_instance_valid(unit):
		spawn_selected_unit()

	if current_hp <= 0 or unit.dead or getattr(unit, "_dying", false):
		spawn_selected_unit()

	unit.play("Attack")
	_update_unit_status_badge("UNIT ATTACKING")

	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		if unit and is_instance_valid(unit) and not unit.dead:
			var forward := -unit.global_transform.basis.z.normalized()
			var muzzle_pos := unit.global_position + forward * 0.45 + Vector3.UP * 0.85
			var target_pos := muzzle_pos + forward * 6.0
			_spawn_tracer(muzzle_pos, target_pos, false, func() -> void: pass)
			_spawn_impact_flash(muzzle_pos, false)
	)


func _spawn_tracer(from_pos: Vector3, to_pos: Vector3, is_lethal: bool, on_impact: Callable) -> void:
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 0.35
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.3, 0.1) if is_lethal else Color(0.2, 0.85, 1.0)
	tracer.mesh = cyl
	tracer.material_override = mat
	fx_root.add_child(tracer)

	var dir := (to_pos - from_pos).normalized()
	var up := Vector3.UP if abs(dir.y) < 0.99 else Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var actual_up := right.cross(dir).normalized()
	tracer.global_basis = Basis(right, dir, -actual_up)
	tracer.global_position = from_pos

	var tw := create_tween()
	var speed := 42.0
	var dist := from_pos.distance_to(to_pos)
	var travel_time := clampf(dist / speed, 0.03, 0.10)
	tw.tween_property(tracer, "global_position", to_pos, travel_time).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func() -> void:
		if is_instance_valid(tracer):
			tracer.queue_free()
		_spawn_impact_flash(to_pos, is_lethal)
		on_impact.call()
	)


func _spawn_impact_flash(pos: Vector3, is_lethal: bool) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.4, 0.1) if is_lethal else Color(0.3, 0.9, 1.0)
	flash.light_energy = 3.5
	flash.omni_range = 1.6
	fx_root.add_child(flash)
	flash.global_position = pos

	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.5) if is_lethal else Color(0.7, 0.95, 1.0)
	spark.mesh = sphere
	spark.material_override = mat
	fx_root.add_child(spark)
	spark.global_position = pos

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "light_energy", 0.0, 0.14)
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.14)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(flash): flash.queue_free()
		if is_instance_valid(spark): spark.queue_free()
	)


func clear_blood_decals_only() -> void:
	if unit and is_instance_valid(unit) and unit.blood:
		unit.blood.clear()
	telemetry_label.text = "All blood decals and pools cleared."


func getattr(obj: Object, prop: String, default_val = null):
	var val = obj.get(prop)
	return val if val != null else default_val


# ------------------------------------------------------------------ Animation Controls
func _rebuild_animation_buttons() -> void:
	for c in anim_buttons_container.get_children():
		c.queue_free()

	if unit == null or not is_instance_valid(unit) or unit.anim == null:
		return

	var ap: AnimationPlayer = unit.anim
	var anim_list: Array = []
	for lib_name in ap.get_animation_library_list():
		for an in ap.get_animation_library(lib_name).get_animation_list():
			var n := String(an)
			if not anim_list.has(n):
				anim_list.append(n)

	var locomotion: Array[String] = []
	var combat: Array[String] = []
	var hits: Array[String] = []
	var deaths: Array[String] = []
	var other: Array[String] = []

	for a in anim_list:
		if a.begins_with("Hit"):
			hits.append(a)
		elif a.begins_with("Death"):
			deaths.append(a)
		elif a == "Attack":
			combat.append(a)
		elif a in ["Idle", "IdleArmed", "Walk", "WalkArmed", "Kneel", "Idle-loop", "IdleArmed-loop", "Walk-loop", "WalkArmed-loop"]:
			locomotion.append(a)
		else:
			other.append(a)

	_add_anim_group("LOCOMOTION", locomotion)
	_add_anim_group("COMBAT", combat)
	_add_anim_group("DIRECTIONAL HITS", hits)
	_add_anim_group("DIRECTIONAL DEATHS", deaths)
	if not other.is_empty():
		_add_anim_group("OTHER", other)


func _add_anim_group(title: String, clips: Array[String]) -> void:
	if clips.is_empty():
		return

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	anim_buttons_container.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	anim_buttons_container.add_child(grid)

	for clip_name in clips:
		var btn := Button.new()
		btn.text = clip_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func() -> void:
			_on_anim_button_pressed(clip_name)
		)
		grid.add_child(btn)


func _on_anim_button_pressed(clip_name: String) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit.dead:
		spawn_selected_unit()

	unit.play(clip_name)
	_update_unit_status_badge("PLAYING: " + clip_name)

	var ap: AnimationPlayer = unit.anim
	if ap:
		var total := ap.current_animation_length
		scrubber_slider.set_value_no_signal(0.0)
		scrubber_label.text = "0.00s / %.2fs  [F0 / %d]" % [total, int(total * 60.0)]


func set_anim_speed(speed: float) -> void:
	speed_scale = speed
	if unit and is_instance_valid(unit) and unit.anim:
		unit.anim.speed_scale = speed_scale
	speed_label.text = "Speed: %.2fx" % speed_scale


func step_animation(frames: int) -> void:
	if unit == null or not is_instance_valid(unit) or unit.anim == null:
		return

	var ap: AnimationPlayer = unit.anim
	ap.pause()
	play_pause_btn.text = "▶ Play"

	var dt := float(frames) / 60.0
	var cur := ap.current_animation_position + dt
	var total := ap.current_animation_length
	cur = clampf(cur, 0.0, total)
	ap.seek(cur, true)

	if total > 0.0:
		scrubber_slider.set_value_no_signal(cur / total)
		var frame_idx := int(cur * 60.0)
		var total_frames := int(total * 60.0)
		scrubber_label.text = "%.2fs / %.2fs  [F%d / %d]" % [cur, total, frame_idx, total_frames]


# ------------------------------------------------------------------ Camera System & Middle-Mouse Orbit
func _sync_orbit_from_current_cam() -> void:
	if cam_mode < 4:
		orbit_yaw = REVIEW_YAW + cam_mode * PI * 0.5
		orbit_pitch = REVIEW_PITCH
		orbit_dist = 3.8
		orbit_target = Vector3(0, 0.8, 0)
	elif cam_mode == 4:
		orbit_yaw = 0.0
		orbit_pitch = deg_to_rad(85.0)
		orbit_dist = 4.5
		orbit_target = Vector3(0, 0.8, 0)
	elif cam_mode == 5:
		var origin := get_attacker_position()
		var target := Vector3(0, get_target_height(), 0)
		var d := origin - target
		orbit_dist = d.length()
		orbit_yaw = atan2(d.x, d.z)
		orbit_pitch = asin(clampf(d.y / orbit_dist, -0.99, 0.99))
		orbit_target = target
	elif cam_mode == 6:
		orbit_dist = 1.8
		orbit_yaw = deg_to_rad(20.0)
		orbit_pitch = deg_to_rad(10.0)
		orbit_target = Vector3(0, get_target_height(), 0)


func _update_camera() -> void:
	if cam_mode < 4:
		var yaw: float = REVIEW_YAW + cam_mode * PI * 0.5
		set_review_camera(camera, yaw, Vector3(0, UNITS_CATALOG[current_unit_type].get("review_height", 0.8), 0), UNITS_CATALOG[current_unit_type].get("review_size", 2.8))
	elif cam_mode == 4:
		set_top_camera(camera, Vector3.ZERO, 4.5)
	elif cam_mode == 5:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 42.0
		var origin := get_attacker_position()
		var target := Vector3(0, get_target_height(), 0)
		camera.position = origin
		camera.look_at(target, Vector3.UP)
	elif cam_mode == 6:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 32.0
		var focus_target := Vector3(0, get_target_height(), 0)
		camera.position = focus_target + Vector3(0.5, 0.2, 1.6)
		camera.look_at(focus_target, Vector3.UP)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 40.0
		camera.position = orbit_target + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * orbit_dist
		camera.look_at(orbit_target, Vector3.UP)


static func set_review_camera(cam: Camera3D, yaw: float, target: Vector3, size: float) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 0.05
	cam.far = 100.0
	var dist := 20.0
	cam.position = target + Vector3(sin(yaw) * cos(REVIEW_PITCH), sin(REVIEW_PITCH), cos(yaw) * cos(REVIEW_PITCH)) * dist
	cam.look_at(target, Vector3.UP)


static func set_top_camera(cam: Camera3D, target: Vector3, size: float) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 0.05
	cam.far = 100.0
	cam.position = target + Vector3(0, 20, 0)
	cam.look_at(target, Vector3(0, 0, -1))


# ------------------------------------------------------------------ Input Handling
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		is_orbit_dragging = false
		orbit_drag_button = 0


func _input(event: InputEvent) -> void:
	# 1. Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_H:
				fire_attack(false)
			KEY_K:
				fire_attack(true)
			KEY_A:
				fire_unit_attack()
			KEY_R:
				spawn_selected_unit()
			KEY_C:
				cam_mode = (cam_mode + 1) % 8
				_update_camera()
			KEY_TAB:
				ui_root.visible = not ui_root.visible
			KEY_1: set_attack_compass_direction("N")
			KEY_2: set_attack_compass_direction("NE")
			KEY_3: set_attack_compass_direction("E")
			KEY_4: set_attack_compass_direction("SE")
			KEY_5: set_attack_compass_direction("S")
			KEY_6: set_attack_compass_direction("SW")
			KEY_7: set_attack_compass_direction("W")
			KEY_8: set_attack_compass_direction("NW")
			KEY_BRACKETLEFT:
				set_anim_speed(maxf(0.05, speed_scale - 0.25))
			KEY_BRACKETRIGHT:
				set_anim_speed(minf(2.0, speed_scale + 0.25))

	# 2. Mouse Buttons: Left click fires hit on unit; Middle/Right click activates orbit; Wheel zooms
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				if not _is_click_on_ui(event.position):
					is_orbit_dragging = true
					orbit_drag_button = event.button_index
					if cam_mode != 7:
						_sync_orbit_from_current_cam()
						cam_mode = 7 # Switch to Orbit 3D smoothly
						_update_camera()
			else:
				if event.button_index == orbit_drag_button or orbit_drag_button == 0:
					is_orbit_dragging = false
					orbit_drag_button = 0

		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _is_click_on_ui(event.position):
				_handle_viewport_left_click(event.position)

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not _is_click_on_ui(event.position):
				if cam_mode in [5, 6, 7]:
					orbit_dist = maxf(0.5, orbit_dist * 0.9)
				else:
					camera.size = maxf(0.8, camera.size * 0.9)
				_update_camera()

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not _is_click_on_ui(event.position):
				if cam_mode in [5, 6, 7]:
					orbit_dist = minf(25.0, orbit_dist / 0.9)
				else:
					camera.size = minf(14.0, camera.size / 0.9)
				_update_camera()

	# 3. Mouse Motion: Middle or Right mouse drag rotates camera (Shift+drag pans)
	elif event is InputEventMouseMotion:
		var has_drag_mask: bool = ((event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)) != 0)
		if is_orbit_dragging or has_drag_mask:
			if not is_orbit_dragging and not _is_click_on_ui(event.position):
				is_orbit_dragging = true
				orbit_drag_button = MOUSE_BUTTON_MIDDLE if (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) else MOUSE_BUTTON_RIGHT
				if cam_mode != 7:
					_sync_orbit_from_current_cam()
					cam_mode = 7

			if is_orbit_dragging:
				if event.shift_pressed:
					# Pan focus point
					orbit_target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * 0.004 * orbit_dist
				else:
					# Rotate orbit camera smoothly
					orbit_yaw -= event.relative.x * 0.006
					orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.006, -0.2, 1.5)
				_update_camera()


# ------------------------------------------------------------------ UI Construction
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	_build_top_bar()
	_build_left_panel()
	_build_right_panel()
	_build_bottom_status_bar()


func _make_panel_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.4, 0.6, 0.5)
	return style


func _build_top_bar() -> void:
	top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 10
	top_panel.offset_top = 10
	top_panel.offset_right = -10
	top_panel.offset_bottom = 54
	top_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.11, 0.15, 0.92)))
	ui_root.add_child(top_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	top_panel.add_child(hbox)

	var title := Label.new()
	title.text = " X-COM 3D // UNIT & ATTACK PREVIEWER "
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0))
	hbox.add_child(title)

	hbox.add_child(VSeparator.new())

	var cam_label := Label.new()
	cam_label.text = "Camera:"
	cam_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(cam_label)

	var cam_names := ["Review SE", "Review NE", "Review NW", "Review SW", "Top-Down", "Attacker POV", "Close-Up", "Orbit 3D"]
	for i in cam_names.size():
		var btn := Button.new()
		btn.text = cam_names[i]
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func() -> void:
			cam_mode = i
			_update_camera()
		)
		hbox.add_child(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var hide_btn := Button.new()
	hide_btn.text = "Hide HUD [Tab]"
	hide_btn.add_theme_font_size_override("font_size", 11)
	hide_btn.pressed.connect(func() -> void:
		ui_root.visible = false
	)
	hbox.add_child(hide_btn)


func _build_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.offset_left = 10
	left_panel.offset_top = 64
	left_panel.offset_right = 350
	left_panel.offset_bottom = -38
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.11, 0.15, 0.90)))
	ui_root.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# --- UNIT SELECTION SECTION ---
	var unit_sec_header := Label.new()
	unit_sec_header.text = "◆ UNIT SELECTION"
	unit_sec_header.add_theme_font_size_override("font_size", 13)
	unit_sec_header.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vbox.add_child(unit_sec_header)

	var type_row := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Unit type:"
	type_label.add_theme_font_size_override("font_size", 12)
	type_row.add_child(type_label)
	unit_type_option_btn = OptionButton.new()
	unit_type_option_btn.name = "UnitTypeDropdown"
	unit_type_option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_type_option_btn.add_theme_font_size_override("font_size", 12)
	for u_name: String in UNITS_CATALOG:
		unit_type_option_btn.add_item(UNITS_CATALOG[u_name].get("label", u_name.capitalize()))
		var index := unit_type_option_btn.item_count - 1
		unit_type_option_btn.set_item_metadata(index, u_name)
		if u_name == current_unit_type:
			unit_type_option_btn.select(index)
	unit_type_option_btn.item_selected.connect(func(index: int) -> void:
		current_unit_type = unit_type_option_btn.get_item_metadata(index)
		current_version_id = UNITS_CATALOG[current_unit_type]["default_version"]
		_update_version_options()
		spawn_selected_unit()
	)
	type_row.add_child(unit_type_option_btn)
	vbox.add_child(type_row)

	var ver_hbox := HBoxContainer.new()
	var ver_lbl := Label.new()
	ver_lbl.text = "Model:"
	ver_lbl.add_theme_font_size_override("font_size", 12)
	ver_hbox.add_child(ver_lbl)

	version_option_btn = OptionButton.new()
	version_option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version_option_btn.add_theme_font_size_override("font_size", 12)
	version_option_btn.item_selected.connect(func(idx: int) -> void:
		current_version_id = version_option_btn.get_item_metadata(idx)
		spawn_selected_unit()
	)
	ver_hbox.add_child(version_option_btn)
	vbox.add_child(ver_hbox)
	_update_version_options()

	# Facing Controls
	facing_label = Label.new()
	facing_label.text = "Unit Facing: 0°"
	facing_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(facing_label)

	facing_slider = HSlider.new()
	facing_slider.min_value = 0.0
	facing_slider.max_value = 359.0
	facing_slider.value = unit_facing_deg
	facing_slider.value_changed.connect(set_unit_facing)
	vbox.add_child(facing_slider)

	var facing_quick_hbox := HBoxContainer.new()
	facing_quick_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(facing_quick_hbox)
	for f_pair in [["N (0°)", 0.0], ["E (90°)", 90.0], ["S (180°)", 180.0], ["W (270°)", 270.0]]:
		var f_btn := Button.new()
		f_btn.text = f_pair[0]
		f_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_btn.add_theme_font_size_override("font_size", 11)
		f_btn.pressed.connect(func() -> void: set_unit_facing(f_pair[1]))
		facing_quick_hbox.add_child(f_btn)

	vbox.add_child(HSeparator.new())

	# --- ANIMATION PREVIEW SECTION ---
	var anim_sec_header := Label.new()
	anim_sec_header.text = "◆ ANIMATION PLAYER"
	anim_sec_header.add_theme_font_size_override("font_size", 13)
	anim_sec_header.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	vbox.add_child(anim_sec_header)

	var play_bar := HBoxContainer.new()
	play_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(play_bar)

	play_pause_btn = Button.new()
	animation_combat_controls.append(play_pause_btn)
	play_pause_btn.text = "⏸ Pause"
	play_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_pause_btn.pressed.connect(func() -> void:
		if unit and is_instance_valid(unit) and unit.anim:
			if unit.anim.is_playing():
				unit.anim.pause()
				play_pause_btn.text = "▶ Play"
			else:
				unit.anim.play()
				play_pause_btn.text = "⏸ Pause"
	)
	play_bar.add_child(play_pause_btn)

	var step_back_btn := Button.new()
	animation_combat_controls.append(step_back_btn)
	step_back_btn.text = "◀ -1F"
	step_back_btn.tooltip_text = "Step backward 1 frame"
	step_back_btn.pressed.connect(func() -> void: step_animation(-1))
	play_bar.add_child(step_back_btn)

	var step_fwd_btn := Button.new()
	animation_combat_controls.append(step_fwd_btn)
	step_fwd_btn.text = "+1F ▶"
	step_fwd_btn.tooltip_text = "Step forward 1 frame"
	step_fwd_btn.pressed.connect(func() -> void: step_animation(1))
	play_bar.add_child(step_fwd_btn)

	scrubber_label = Label.new()
	scrubber_label.text = "0.00s / 0.00s"
	scrubber_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(scrubber_label)

	scrubber_slider = HSlider.new()
	scrubber_slider.min_value = 0.0
	scrubber_slider.max_value = 1.0
	scrubber_slider.step = 0.001
	scrubber_slider.drag_started.connect(func() -> void:
		is_scrubbing = true
		if unit and is_instance_valid(unit) and unit.anim:
			unit.anim.pause()
			play_pause_btn.text = "▶ Play"
	)
	scrubber_slider.drag_ended.connect(func(_val_changed: bool) -> void:
		is_scrubbing = false
	)
	scrubber_slider.value_changed.connect(func(val: float) -> void:
		if unit and is_instance_valid(unit) and unit.anim:
			var total := unit.anim.current_animation_length
			var target_t := val * total
			unit.anim.seek(target_t, true)
			var frame_idx := int(target_t * 60.0)
			var total_frames := int(total * 60.0)
			scrubber_label.text = "%.2fs / %.2fs  [F%d / %d]" % [target_t, total, frame_idx, total_frames]
	)
	vbox.add_child(scrubber_slider)

	speed_label = Label.new()
	speed_label.text = "Speed: 1.00x"
	speed_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(speed_label)

	var speed_presets_hbox := HBoxContainer.new()
	speed_presets_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(speed_presets_hbox)
	for sp in [["0.1x", 0.1], ["0.25x", 0.25], ["0.5x", 0.5], ["1.0x", 1.0], ["2.0x", 2.0]]:
		var s_btn := Button.new()
		animation_combat_controls.append(s_btn)
		s_btn.text = sp[0]
		s_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_btn.add_theme_font_size_override("font_size", 11)
		s_btn.pressed.connect(func() -> void: set_anim_speed(sp[1]))
		speed_presets_hbox.add_child(s_btn)

	vbox.add_child(HSeparator.new())

	anim_buttons_container = VBoxContainer.new()
	anim_buttons_container.add_theme_constant_override("separation", 6)
	vbox.add_child(anim_buttons_container)


func _update_version_options() -> void:
	version_option_btn.clear()
	var u_info: Dictionary = UNITS_CATALOG[current_unit_type]
	var versions: Array = u_info["versions"]
	for i in versions.size():
		var v: Dictionary = versions[i]
		version_option_btn.add_item(v["label"], i)
		version_option_btn.set_item_metadata(i, v["id"])
		if v["id"] == current_version_id:
			version_option_btn.select(i)


func _build_right_panel() -> void:
	right_panel = PanelContainer.new()
	right_panel.offset_left = -380
	right_panel.offset_top = 64
	right_panel.offset_right = -10
	right_panel.offset_bottom = -38
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.11, 0.15, 0.90)))
	ui_root.add_child(right_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# --- UNIT HEALTH CARD (3 HITS TO KILL) ---
	var hp_panel := PanelContainer.new()
	hp_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.08, 0.12, 0.95)))
	vbox.add_child(hp_panel)

	var hp_vbox := VBoxContainer.new()
	hp_vbox.add_theme_constant_override("separation", 4)
	hp_panel.add_child(hp_vbox)

	hp_bar_label = Label.new()
	hp_bar_label.text = " HEALTH: [ ■ ■ ■ ]  3 / 3 HP"
	hp_bar_label.add_theme_font_size_override("font_size", 14)
	hp_bar_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	hp_vbox.add_child(hp_bar_label)

	var hp_hint := Label.new()
	hp_hint.text = "Left-click unit to fire from camera (3 hits to kill)\nMiddle-mouse drag to rotate camera"
	hp_hint.add_theme_font_size_override("font_size", 11)
	hp_hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	hp_vbox.add_child(hp_hint)

	vbox.add_child(HSeparator.new())

	# --- DIRECTIONAL ATTACK HITS SECTION ---
	var attack_sec_header := Label.new()
	attack_sec_header.text = "◆ DIRECTIONAL ATTACK HITS"
	attack_sec_header.add_theme_font_size_override("font_size", 13)
	attack_sec_header.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	vbox.add_child(attack_sec_header)

	var compass_grid := GridContainer.new()
	compass_grid.columns = 3
	compass_grid.add_theme_constant_override("h_separation", 4)
	compass_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(compass_grid)

	var grid_buttons := [
		["NW (315°)", "NW"], ["N (0°)", "N"],   ["NE (45°)", "NE"],
		["W (270°)", "W"],   ["🎯 UNIT", ""],  ["E (90°)", "E"],
		["SW (225°)", "SW"], ["S (180°)", "S"], ["SE (135°)", "SE"]
	]
	for item in grid_buttons:
		var btn := Button.new()
		btn.text = item[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		if item[1] != "":
			btn.pressed.connect(func() -> void: set_attack_compass_direction(item[1]))
		else:
			btn.disabled = true
		compass_grid.add_child(btn)

	attack_label = Label.new()
	attack_label.text = "Attack Angle: 0° (N)"
	attack_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(attack_label)

	attack_slider = HSlider.new()
	attack_slider.min_value = 0.0
	attack_slider.max_value = 359.0
	attack_slider.value = attack_angle_deg
	attack_slider.value_changed.connect(func(val: float) -> void:
		attack_angle_deg = val
		attack_label.text = "Attack Angle: %d°" % int(attack_angle_deg)
		_update_attacker_visuals()
		_update_relative_sector_ui()
	)
	vbox.add_child(attack_slider)

	var h_hbox := HBoxContainer.new()
	var h_lbl := Label.new()
	h_lbl.text = "Aim Height:"
	h_lbl.add_theme_font_size_override("font_size", 12)
	h_hbox.add_child(h_lbl)

	var h_opt := OptionButton.new()
	h_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_opt.add_item("Head Area (~1.3m)", 0)
	h_opt.add_item("Chest / Spine (~0.85m)", 1)
	h_opt.add_item("Pelvis / Lower (~0.40m)", 2)
	h_opt.select(1)
	h_opt.item_selected.connect(func(idx: int) -> void:
		attack_height_mode = idx
		_update_attacker_visuals()
	)
	h_hbox.add_child(h_opt)
	vbox.add_child(h_hbox)

	var sector_panel := PanelContainer.new()
	sector_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.08, 0.12, 0.95)))
	vbox.add_child(sector_panel)

	var s_vbox := VBoxContainer.new()
	s_vbox.add_theme_constant_override("separation", 4)
	sector_panel.add_child(s_vbox)

	sector_badge = Label.new()
	sector_badge.text = " SECTOR: FRONT "
	sector_badge.add_theme_font_size_override("font_size", 14)
	sector_badge.add_theme_color_override("font_color", Color("#2ecc71"))
	s_vbox.add_child(sector_badge)

	sector_desc_label = Label.new()
	sector_desc_label.text = "Attack hits FRONT sector -> Triggers HitFront / DeathFront"
	sector_desc_label.add_theme_font_size_override("font_size", 11)
	sector_desc_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	s_vbox.add_child(sector_desc_label)

	# ACTION BUTTONS
	var fire_hit_btn := Button.new()
	animation_combat_controls.append(fire_hit_btn)
	fire_hit_btn.text = "💥 FIRE HIT [1 Dmg] (Space / H)"
	fire_hit_btn.add_theme_font_size_override("font_size", 13)
	fire_hit_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	fire_hit_btn.pressed.connect(func() -> void: fire_attack(false))
	vbox.add_child(fire_hit_btn)

	var fire_kill_btn := Button.new()
	animation_combat_controls.append(fire_kill_btn)
	fire_kill_btn.text = "☠ FIRE LETHAL SHOT [Kill & Ragdoll] (K)"
	fire_kill_btn.add_theme_font_size_override("font_size", 13)
	fire_kill_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	fire_kill_btn.pressed.connect(func() -> void: fire_attack(true))
	vbox.add_child(fire_kill_btn)

	var fire_unit_attack_btn := Button.new()
	animation_combat_controls.append(fire_unit_attack_btn)
	fire_unit_attack_btn.text = "🔫 UNIT ATTACK ANIMATION (A)"
	fire_unit_attack_btn.add_theme_font_size_override("font_size", 12)
	fire_unit_attack_btn.pressed.connect(fire_unit_attack)
	vbox.add_child(fire_unit_attack_btn)

	var auto_cycle_btn := Button.new()
	animation_combat_controls.append(auto_cycle_btn)
	auto_cycle_btn.text = "🔄 AUTO-PLAY ALL 8 DIRECTIONS"
	auto_cycle_btn.add_theme_font_size_override("font_size", 12)
	auto_cycle_btn.toggle_mode = true
	auto_cycle_btn.toggled.connect(func(toggled: bool) -> void:
		auto_cycle_active = toggled
		auto_cycle_index = 0
		auto_cycle_timer = 0.0
		auto_cycle_btn.text = "⏹ STOP AUTO-PLAY" if toggled else "🔄 AUTO-PLAY ALL 8 DIRECTIONS"
	)
	vbox.add_child(auto_cycle_btn)

	var auto_lethal_cb := CheckBox.new()
	animation_combat_controls.append(auto_lethal_cb)
	auto_lethal_cb.text = "Auto-cycle Lethal Mode (Ragdoll each angle)"
	auto_lethal_cb.add_theme_font_size_override("font_size", 11)
	auto_lethal_cb.toggled.connect(func(t: bool) -> void: auto_cycle_lethal = t)
	vbox.add_child(auto_lethal_cb)

	vbox.add_child(HSeparator.new())

	var reset_hbox := HBoxContainer.new()
	reset_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(reset_hbox)

	var reset_unit_btn := Button.new()
	reset_unit_btn.text = "↺ Reset Unit (R)"
	reset_unit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_unit_btn.add_theme_font_size_override("font_size", 12)
	reset_unit_btn.pressed.connect(spawn_selected_unit)
	reset_hbox.add_child(reset_unit_btn)

	var clear_blood_btn := Button.new()
	clear_blood_btn.text = "🧹 Clear Blood"
	clear_blood_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_blood_btn.add_theme_font_size_override("font_size", 12)
	clear_blood_btn.pressed.connect(clear_blood_decals_only)
	reset_hbox.add_child(clear_blood_btn)

	vbox.add_child(HSeparator.new())

	var diag_header := Label.new()
	diag_header.text = "◆ TELEMETRY & DIAGNOSTICS"
	diag_header.add_theme_font_size_override("font_size", 12)
	diag_header.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	vbox.add_child(diag_header)

	telemetry_label = Label.new()
	telemetry_label.text = "Ready. Left-click unit to fire a hit,\nor drag Middle Mouse Button to rotate camera."
	telemetry_label.add_theme_font_size_override("font_size", 11)
	telemetry_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(telemetry_label)


func _build_bottom_status_bar() -> void:
	status_panel = PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_panel.offset_left = 10
	status_panel.offset_top = -32
	status_panel.offset_right = -10
	status_panel.offset_bottom = -6
	status_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.11, 0.95)))
	ui_root.add_child(status_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	status_panel.add_child(hbox)

	unit_status_badge = Label.new()
	unit_status_badge.text = " STATUS: ALIVE [3/3 HP] "
	unit_status_badge.add_theme_font_size_override("font_size", 12)
	unit_status_badge.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	hbox.add_child(unit_status_badge)

	hbox.add_child(VSeparator.new())

	var hints := Label.new()
	hints.text = "LMB: Shoot Unit (3 Hits to Kill)  |  MMB / RMB Drag: Rotate Camera  |  Shift+Drag: Pan  |  Wheel: Zoom  |  Space/H: Hit  |  K: Kill  |  R: Reset  |  Tab: Hide UI"
	hints.add_theme_font_size_override("font_size", 11)
	hints.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	hbox.add_child(hints)


func _update_unit_status_badge(status_text: String) -> void:
	if unit_status_badge:
		unit_status_badge.text = " STATUS: " + status_text
		if status_text.begins_with("ALIVE") or status_text.begins_with("PLAYING"):
			unit_status_badge.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		elif status_text.begins_with("DEAD"):
			unit_status_badge.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			unit_status_badge.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
