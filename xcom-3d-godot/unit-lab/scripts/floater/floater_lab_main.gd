## Floater lab scene (scripts/floater/floater_lab.tscn): the Sectoid lab's world, lighting and cameras
## with a FloaterLabUnit. Keys as in lab_main (1 Idle 2 Walk 3 Attack 4 Hit 5 DeathBaked 6 armed hold,
## K kill, R reset, C camera). Automated review: Godot --path unit-lab res://scripts/floater/floater_lab.tscn
## -- --capture <absolute output folder>
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
	var i := args.find("--capture")
	if i >= 0:
		var out_dir := args[i + 1] if args.size() > i + 1 else ProjectSettings.globalize_path("user://capture_floater")
		var cap := preload("res://scripts/floater/floater_capture.gd").new()
		add_child(cap)
		cap.run(self, out_dir)
		return
	_build_hud()
	_update_camera()


func spawn_unit(facing_yaw := 0.0) -> LabUnit:
	if unit:
		unit.blood.clear()
		unit.queue_free()
	unit = FloaterLabUnit.new()
	unit.name = "Floater"
	unit.fx_root = fx_root
	unit.rotation.y = facing_yaw
	add_child(unit)
	unit.play("Idle")
	return unit
