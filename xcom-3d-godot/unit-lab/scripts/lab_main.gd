## Unit lab scene: floor with a 2 m tile grid, game-review lighting (same values as the native
## TacticalLevelViewer), the 30-degree orthographic review camera and a free orbit camera.
##
## Interactive keys:
##   1 Idle  2 Walk  3 Attack  4 Hit  5 DeathBaked  6 Kneel
##   K  kill: the shot travels from the current camera towards the unit
##   R  reset the unit         C  cycle camera (review SE/NE/NW/SW, top, orbit)
##   Orbit camera: right-drag rotate, wheel zoom, middle-drag pan
## Automated review:  Godot --path unit-lab -- --capture <absolute output folder>
extends Node3D

const TILE_M := 2.0
const FLOOR_VISUAL_LAYER := 1
const REVIEW_PITCH := deg_to_rad(30.0)   # native viewer: pitch 30 deg, yaw 45 deg (camera in the SE)
const REVIEW_YAW := deg_to_rad(45.0)

var unit: LabUnit
var fx_root: Node3D
var camera: Camera3D
var hud: Label
var cam_mode := 0                # 0..3 review quarter turns (SE, NE, NW, SW), 4 top, 5 orbit
var orbit_yaw := deg_to_rad(45.0)
var orbit_pitch := deg_to_rad(25.0)
var orbit_dist := 4.0
var orbit_target := Vector3(0, 0.8, 0)


func _ready() -> void:
	build_world(self)
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	spawn_unit()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i >= 0:
		var out_dir := args[i + 1] if args.size() > i + 1 else ProjectSettings.globalize_path("user://capture")
		var cap := preload("res://scripts/lab_capture.gd").new()
		add_child(cap)
		cap.run(self, out_dir)
		return
	_build_hud()
	_update_camera()


## Floor, collision, sun, environment. Static so the capture runner can reuse it.
static func build_world(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.07, .10, .14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.70, .78, .91)
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = .75
	env.ssao_intensity = 1.15
	# Neutral reflection-only sky, identical to TacticalLevelViewer::create_world (default ON
	# since 2026-10-02, art/review/reflections/; was a constant 0.35 grey here): metals and wet
	# blood reflect it. Background, ambient, tonemap, exposure, sun and specular are unchanged.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(.50, .50, .50)
	sky_mat.sky_horizon_color = Color(.42, .42, .42)
	sky_mat.ground_horizon_color = Color(.42, .42, .42)
	sky_mat.ground_bottom_color = Color(.25, .25, .25)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-51, -28, 0)
	sun.light_color = Color(1, .94, .83)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	parent.add_child(sun)
	# Visual floor: 9 x 9 tiles with the grid shader.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(9 * TILE_M, 9 * TILE_M)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/floor_grid.gdshader")
	plane.material = mat
	floor_mesh.mesh = plane
	floor_mesh.layers = 1 << (FLOOR_VISUAL_LAYER - 1)
	parent.add_child(floor_mesh)
	# Floor collision: a thick box whose top is the walking surface (y = 0).
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	body.collision_layer = UnitRagdoll.FLOOR_LAYER
	body.collision_mask = UnitRagdoll.BODY_LAYER
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	parent.add_child(body)


func spawn_unit(facing_yaw := 0.0) -> LabUnit:
	if unit:
		unit.blood.clear()
		unit.queue_free()
	unit = LabUnit.new()
	unit.name = "Sectoid"
	unit.fx_root = fx_root
	unit.rotation.y = facing_yaw
	add_child(unit)
	unit.play("Idle")
	return unit


# ------------------------------------------------------------------ interactive

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)
	_update_hud()


func _update_hud(extra := "") -> void:
	if hud == null:
		return
	var names := ["review SE", "review NE", "review NW", "review SW", "top", "orbit"]
	hud.text = "1 Idle  2 Walk  3 Attack  4 Hit  5 DeathBaked  6 Kneel  |  K kill (shot from camera)  R reset  C camera [%s]\n%s" % [names[cam_mode], extra]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: unit.play("Idle")
			KEY_2: unit.play("Walk")
			KEY_3: unit.play("Attack")
			KEY_4: unit.hit(_shot_dir())
			KEY_5: unit.play("DeathBaked")
			KEY_6: unit.play("Kneel")
			KEY_K:
				unit.died.connect(func(r: Dictionary) -> void: _update_hud("settled %.2f s (%s), mesh past tile edge %.2f m" % [r["settle_time_s"], r["settle_reason"], r["mesh_outside_tile_m"]]))
				unit.die(_shot_dir())
			KEY_R:
				spawn_unit()
				_update_hud()
			KEY_C:
				cam_mode = (cam_mode + 1) % 6
				_update_camera()
				_update_hud()
	elif event is InputEventMouseMotion and cam_mode == 5:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			orbit_yaw -= event.relative.x * 0.006
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.006, -0.2, 1.5)
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			orbit_target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * 0.004 * orbit_dist
			_update_camera()
	elif event is InputEventMouseButton and event.pressed and cam_mode == 5:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = maxf(0.6, orbit_dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = minf(30.0, orbit_dist / 0.9)
		_update_camera()


## Shot direction for K / 4: from the camera towards the unit, horizontal.
func _shot_dir() -> Vector3:
	var d := unit.global_position - camera.global_position
	return Vector3(d.x, 0, d.z).normalized()


func _update_camera() -> void:
	if cam_mode < 4:
		set_review_camera(camera, REVIEW_YAW + cam_mode * PI * 0.5, Vector3(0, 0.8, 0), 2.6)
	elif cam_mode == 4:
		set_top_camera(camera, Vector3.ZERO, 5.0)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 40.0
		camera.position = orbit_target + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * orbit_dist
		camera.look_at(orbit_target, Vector3.UP)


## The battlescape review camera: orthographic, 30 deg down, yaw as in the native viewer
## (yaw 45 deg = camera in the SE; quarter turns give NE, NW, SW). size = view height in metres.
static func set_review_camera(cam: Camera3D, yaw: float, target: Vector3, size: float) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 0.05
	cam.far = 100.0
	var dist := 20.0
	cam.position = target + Vector3(sin(yaw) * cos(REVIEW_PITCH), sin(REVIEW_PITCH), cos(yaw) * cos(REVIEW_PITCH)) * dist
	cam.look_at(target, Vector3.UP)


## Straight down, north (-Z) at the top of the image.
static func set_top_camera(cam: Camera3D, target: Vector3, size: float) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 0.05
	cam.far = 100.0
	cam.position = target + Vector3(0, 20, 0)
	cam.look_at(target, Vector3(0, 0, -1))
