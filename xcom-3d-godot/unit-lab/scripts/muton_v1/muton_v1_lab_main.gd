## Muton opus-v1 (copy of the Sectoid opus-v4 lab file) lab scene (scripts/snakeman/snakeman_lab.tscn): the lab's world, lighting and cameras with a
## MutonV1LabUnit. Keys as in lab_main (1 Idle 2 Walk 3 Attack 4 Hit 5 DeathBaked, K kill, R reset,
## C camera). Automated review: Godot --path unit-lab res://scripts/muton_v1/muton_v1_lab.tscn -- --capture <dir>
extends "res://scripts/lab_main.gd"


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
	var bc := args.find("--blood-check")
	if bc >= 0:
		var cap_b := preload("res://scripts/muton_v1/muton_v1_capture.gd").new()
		add_child(cap_b)
		cap_b.run_blood_check(self, args[bc + 1])
		return
	var i := args.find("--capture")
	if i >= 0:
		var out_dir := args[i + 1] if args.size() > i + 1 else ProjectSettings.globalize_path("user://capture_muton_v1")
		var cap := preload("res://scripts/muton_v1/muton_v1_capture.gd").new()
		add_child(cap)
		cap.run(self, out_dir)
		return
	_build_hud()
	_update_camera()


func spawn_unit(facing_yaw := 0.0) -> LabUnit:
	return spawn_unit_model(facing_yaw, "")


## path "" = the opus-v3 model; another glTF path (e.g. opus-v2) for before / after captures.
func spawn_unit_model(facing_yaw: float, path: String) -> LabUnit:
	if unit:
		unit.blood.clear()
		unit.queue_free()
	unit = MutonV1LabUnit.new()
	if path != "":
		unit.model_path = path
	unit.name = "Muton"
	unit.fx_root = fx_root
	unit.rotation.y = facing_yaw
	add_child(unit)
	unit.play("Idle")
	return unit
