## Inspection adapter for the unfinished human checkpoint: no fabricated clips or ragdoll.
extends LabUnit

func _ready() -> void:
	model = (load(model_path) as PackedScene).instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D")
	blood = UnitBlood.new()
	add_child(blood)
	blood.setup({"per_unit_parameter": {"blood_color_srgb": "#a51d25"}, "runtime_files": {}}, "res://", fx_root)
	set_physics_process(false)


func play(_clip: String) -> void:
	pass


func pose_at(_clip: String, _time: float) -> void:
	pass
