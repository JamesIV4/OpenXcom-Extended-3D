# Reference-led rebuild

The initial batch is rejected. Those exports and renders are drafts awaiting
replacement; a file count is not a count of completed art.

Before modeling each asset:

1. Verify the source against the root renderer. Identify file, MCD identity,
   actual PCK indices, palette, draw routine, layer order, offsets, and whether
   each image is a facing, animation phase, damage state, or neighboring section.
2. Open every available facing and every distinct terrain animation phase.
   Inspect the related orientation records as well. Record visible shapes,
   proportions, materials, colors, joins, fixtures, wear and damage in a dossier.
   Mark unseen sides as interpretation rather than claiming reference coverage.
3. Research each new material or procedural texture against online candidates.
   Save sources and compare at least three actual material trials on the asset,
   beside the sprites, before selecting a result. Shared approved materials may
   be reused when that asset's source and scale match their approved use.
4. Model visible details explicitly. Use continuous authored surfaces and shared
   PBR textures. Bake detail that does not affect the silhouette; retain depth
   for important recesses and preserve mechanical pivots and deformation weights.
5. Inspect four or more Blender views and actual Godot captures. Compare color,
   silhouette, thickness, course counts, seams, fixtures, damage, and close detail.
   Revise discrepancies before marking the asset rebuilt.
6. Validate source links, topology, normals, UVs, materials, texture resolution,
   triangle/surface budgets, LOD import settings, animation and instancing.

Model sources remain editable. The initial renders remain available as before
images. Rebuilt and visually reviewed are separate states.

The renderer uses **eight clockwise unit facings, 0=N**, with exceptions such as
Celatid and Silacoid whose idle selection uses animation phases rather than
direction. Terrain `MCD.Frame[8]` is an animation sequence in a fixed camera
projection. Different MCD records can provide orientation variants, damage states
or sections of a larger structure; they are not automatically four views.

Sources: `src/Battlescape/UnitSprite.cpp`, `Pathfinding.h`, `Camera.cpp`, `Map.cpp`,
`src/Mod/MapDataSet.cpp`, `MCDPatch.cpp`, `src/Engine/SurfaceSet.cpp` and `Palette.h`.
