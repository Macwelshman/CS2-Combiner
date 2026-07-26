# CS2 Texture Combiner

Native macOS utility for packing exported material maps into the five PNGs used
by this Source 2 workflow.

## Run

Use the **Run CS2 Combiner** project action, or run:

```sh
./script/build_cs2_combiner.sh
```

The standalone local app is built at `dist/CS2 Texture Combiner.app`.

## Workflow

1. Drop individual images or a folder on the app.
2. Check the automatically detected slots. Drop on a row or use **Replace** to
   correct an assignment.
3. Keep the visible default output beside the Base Color source, or choose a
   custom parent location.
4. Choose **Export 5 PNGs**.

Base Color is required, must be square, and must be between 512 and 4096 pixels.
It sets the output dimensions. The app asks before resizing companion maps or
replacing existing exports.

Output folders use `<asset name> CS2 textures`. The asset name is the Base Color
filename with a recognized trailing map suffix removed. For example,
`Brick_Wall_v2_BaseColor.png` writes to `Brick_Wall_v2 CS2 textures`. A bare
`BaseColor.png` falls back to its containing folder name. A custom location
places the same derived folder inside the selected directory.

## Normal-map utility

**Normalize Normals…** is a separate action for the assigned OpenGL Normal map.
It opens a standard Save panel, shows a final source/destination confirmation,
and creates a separate normalized image using the existing 8-bit/16-bit
normalization behavior. It does not replace the Normal slot or trigger CS2
packing.

## Packing

Every output reuses the inferred asset name as its exact shared prefix:

- `<asset>_BaseColor.png`: Base Color RGB, Opacity red in alpha
- `<asset>_ControlMask.png`: CM1, CM2, CM3, Snow Remove red channels in RGBA
- `<asset>_MaskMap.png`: Metallic red, Coat red, black, inverted Roughness red
- `<asset>_Normal.png`: OpenGL Normal RGB
- `<asset>_Emissive.png`: Emissive RGB

For example, `Brick_Wall_v2_BaseColor.png` produces all five files beginning
with the exact prefix `Brick_Wall_v2_`.

Missing optional maps use safe black, white, rough, or neutral-normal defaults.
The first draft writes 8-bit PNG files and uses a local ad-hoc signature; it is
not Developer ID signed or notarised.
