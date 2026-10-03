"""Export the human WIP checkpoint for inspection only; never modifies the Blender source.
Run with Blender --background --python this_file.py from any working directory.
"""
from pathlib import Path
import bpy

repo = Path(__file__).resolve().parents[3]
source = repo / "art/team/units_opus55"
bpy.ops.wm.open_mainfile(filepath=str(source / "editable/v01/XCOM_1_male_geometry.blend"))
colors = {"armor": (.46,.43,.56), "cloth": (.21,.19,.28), "armor_soft": (.38,.35,.48), "armor_trim": (.60,.57,.70), "leather_light": (.42,.24,.11), "hair_dark": (.10,.028,.010), "leather": (.30,.15,.07), "rubber": (.10,.10,.20), "boot": (.36,.34,.44), "hair": (.33,.11,.04), "skin": (.70,.47,.36), "eye": (.85,.85,.85), "metal": (.6,.6,.62)}
mats = {}
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type not in {"MESH", "ARMATURE"} or obj.get("variant_hidden", False):
        continue
    if obj.type == "MESH":
        role = obj.get("material_role", "cloth")
        if role not in mats:
            mat = bpy.data.materials.new("Human_WIP_" + role)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = (*colors.get(role, (.33,.11,.04)), 1)
            bsdf.inputs["Roughness"].default_value = .45 if role in {"armor", "metal"} else .7
            bsdf.inputs["Metallic"].default_value = 1 if role == "metal" else 0
            if role == "hair_cards":
                tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
                tex.image = bpy.data.images.load(str(source / "textures/v01/hair_male_cards_basecolor.png"))
                mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
                mat.surface_render_method = "DITHERED"
                mat.use_backface_culling = False
            mats[role] = mat
        obj.data.materials.clear()
        obj.data.materials.append(mats[role])
    obj.hide_set(False)
    obj.select_set(True)
out = repo / "xcom-3d-godot/unit-lab/assets/models/units/HUMAN/HUMAN.wip-v1.glb"
out.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_animations=False, export_apply=True, export_yup=True)
print("HUMAN WIP exported:", out)
