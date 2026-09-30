# UFO Defense 3D art

The local `reference/` files are the source of truth. `tools/catalog_reference.py`
decodes each terrain MCD identity and each tactical item and unit into a labeled
reference image. Direction and animation frames describe the same model.

```powershell
python art/tools/catalog_reference.py
```

`asset_catalog.json` tracks each identity independently. A generated file is not
an approval: visual review and validated export metrics are separate fields.
Terrain variants retain their exact MCD index, destruction and door relationships.

Model coordinates use two meters per horizontal tile and sqrt(6), about 2.44949
render meters per vertical level. The original 24-voxel/3-logical-meter metadata
stays separate: a 30-degree physical orthographic camera requires this corrected
visual pitch to match the original (16,8,24) source projection. Source pixel shapes
still override conservative collision occupancy when deciding visible proportions.
Blender is Z-up with +Y pointing north; exported glTF is Y-up with -Z north.
The original map's positive Y points south, so that coordinate must be reflected
when mapping it into Blender's right-handed world. East is +X in both systems.
Tile origins are at their centers, with the walking surface at zero height.

See [QUALITY_CONTRACT.md](QUALITY_CONTRACT.md) for the required reference-led
rebuild process. Initial batch exports are rejected drafts, not completed art.

Editable Blender sources belong in `art/source/`. Runtime glTF models and shared
PBR textures belong in the existing Godot project under `assets/`. Review images
and measurements belong in `art/review/`. Small surface details use normal maps;
silhouettes use geometry. Static subparts are consolidated, movable parts retain
pivots, and deforming characters use a joined skinned mesh with bounded weights.

Production targets: ordinary terrain under 4,000 triangles, vegetation under
6,000, articulated units under 24,000; use fewer when the shape allows. Repeated
terrain uses shared materials and spatially partitioned MultiMeshes. Imported
models keep Godot LOD generation, surface deduplication and shadow meshes enabled.
