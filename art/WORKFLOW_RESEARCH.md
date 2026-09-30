# Workflow research

Consulted before implementing each workflow, 2026-09-29. The installed authoring
version is Blender 5.1.2 and the renderer is Godot 4.7 Standard.

| Need | Source | Applied decision |
| --- | --- | --- |
| Exportable textured materials | [Blender glTF manual](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html) | Principled BSDF, image-backed albedo, tangent-space +Y normals, non-color normal/ORM maps, R occlusion/G roughness/B metalness. Shared external images in glTF files. |
| Manufactured edges | [Bevel modifier](https://docs.blender.org/manual/it/4.5/modeling/modifiers/generate/bevel.html) | Small real silhouette bevels and weighted normals; no coplanar duplicate faces for surface marks. |
| UV mapping and baking | [UV operators](https://docs.blender.org/manual/en/4.5/modeling/meshes/editing/uv.html), [Cycles baking](https://docs.blender.org/UATEST/manual/en/4.5/render/cycles/baking.html) | Physical-scale seamless maps for modular surfaces; preserve authored card UVs. Unique baked maps need UV island margins. Procedural shader nodes alone do not export. |
| Foliage cutouts | [glTF alpha modes](https://docs.blender.org/manual/ja/4.5/addons/import_export/scene_gltf2.html) | Alpha masking using the rounded alpha input; opaque bark, economical leaf cards, no blended stacks. |
| Smooth organic anatomy | [Remesh modifier](https://docs.blender.org/manual/id/4.5/modeling/modifiers/generate/remesh.html), [Decimate](https://docs.blender.org/UATEST/manual/en/4.5/modeling/modifiers/generate/decimate.html) | Union organic construction volumes with OpenVDB, smooth and simplify before weighting; protect recognizable silhouettes. |
| Deformation and animation | [Armature modifier](https://docs.blender.org/manual/en/4.5/modeling/modifiers/deform/armature.html), [glTF animation modes](https://docs.blender.org/manual/ja/4.5/addons/import_export/scene_gltf2.html) | Explicit normalized vertex weights and named bone actions stashed into NLA; retain pivots for rigid mechanical motion. |
| Repeated terrain at scale | [Godot MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) | Instance per asset and spatial chunk, because a MultiMesh has collective rather than per-instance culling. C++ assembles transforms. |
| Godot native extension | [GDExtension C++](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/gdextension_cpp_example.html) | Pin godot-cpp; compile against the installed renderer's dumped extension API and retain reproducible build steps. |

Frogger's authoring pipeline was inspected for its join-after-weighting contract,
separate mechanical pivots, and Godot import optimization settings. Its low-poly
visual style and untextured palette are not the art direction for this project.

## Ground color factors and continuous timber revision

The [Blender 5.1 glTF factors documentation](https://docs.blender.org/manual/en/5.1/addons/import_export/scene_gltf2.html#factors)
was checked before source-specific grass tint trials. A Mix color/multiply node
with factor 1 and constant B exports as baseColorFactor, so meadow/jungle ground
can share real images without color-adjusted bitmap duplicates. The
[Godot StandardMaterial3D documentation](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
confirms image/color multiplication and +Y normal conventions. Roughness remains
high, without expensive transparent grass stacks. Image-derived normals are
explicitly approximate; the original albedo has 1254-square native resolution.

Fence UV review rejected repeating photographed board joints across continuous
rails. The new bounded sample is inside a single board, with separately baked
sawn ends and about 683 longitudinal texels per 2 m rail. Four-angle review is
repeated after this revision, not inherited from the rejected UV layout.

## Periodic grass baking and stone fractures

The [Image Texture nodes](https://docs.blender.org/manual/en/5.1/render/shader_nodes/textures/image.html),
[Map Range smooth interpolation](https://docs.blender.org/manual/en/5.0/render/shader_nodes/utilities/math/map_range.html)
and existing Cycles bake documentation were researched before three boundary
blend trials. Repeat alone cannot repair source edge discontinuities. Our
editable shader blends half-period shifted samples only near boundaries, then
bakes color at the native 1254 resolution and re-bakes approximate normals.
Three widths (6%, 10%, 16%) must be compared for seam suppression versus ghosting.
Runtime keeps two image samples rather than the authoring graph's four taps.

[Blender 5.1 BMesh bisect and hole fill](https://docs.blender.org/api/5.1/bmesh.ops.html)
were checked before replacing rounded rubble cubes with closed fractured stones.
Two controlled corner cuts produce recognizable irregular masonry fragments,
with small bevels and face-weighted normals. This is offline authoring; the
joined runtime mesh does not execute fracture operations or spawn rigid bodies.

## Source projection versus visual meters

`src/Battlescape/Camera.cpp` is authoritative: source tile/level indices project
by (16,8) horizontal vectors and 24 pixels per level. At a 2 m horizontal tile
and physical 30-degree orthographic camera, the horizontal pixel density is
16/(2*cos(45 degrees))=11.313708499 pixels/m. Vertical density is that times
cos(30 degrees)=9.797958971 pixels/m. Thus a 24-pixel visual level is sqrt(6),
2.449489743 m. The original 3 m logical voxel assumption cannot also be physical
render meters without vertical distortion. Workers preserve raw source metadata
and use this corrected visual metric for level-connected geometry. This is a
derivation from the verified renderer and our camera/tile choice, not a claim
about canonical real-world dimensions in the original game.

## Reflective-metal review lighting

[Godot environment/reflected light](https://docs.godotengine.org/cs/stable/tutorials/3d/environment_and_post_processing.html)
and [Sky radiance](https://docs.godotengine.org/en/stable/classes/class_sky.html)
were checked before an optional neutral IBL diagnostic. Metal primarily reflects
its surroundings; a navy-only review background can make valid gray steel appear
black. The native viewer can test constant-gray reflected sky at 0.25, 0.42, 0.60,
with a cached 128 radiance cube and unchanged visible background. Previous default
lighting stays reproducible. This isolates reflectance from choosing a different
albedo to compensate for missing environment light; it is not a final game sky.
