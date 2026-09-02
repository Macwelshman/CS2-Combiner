# CS2 Combiner

CS2 Combiner is a desktop app for macOS and Windows that packs exported
material maps into the main and LOD2 PNG textures used by this Cities: Skylines 2
workflow.

## Download

Download the latest builds from [GitHub Releases](../../releases/latest):

- **macOS:** Apple Silicon, macOS 14 or later
- **Windows ARM64:** Windows 11 ARM, including Apple Silicon UTM virtual
  machines
- **Windows x64:** 64-bit Intel/AMD Windows computers and Windows 11 ARM x64
  emulation

The Windows packages are self-contained and do not require a separate .NET
installation. Extract the ZIP before running `CS2Combiner.exe`.

## User guide

See the [CS2 Combiner user guide](docs/CS2_COMBINER_USER_GUIDE.md).

## Workflow

1. Drop individual images or a whole folder onto the app.
2. Review the automatically detected Main and LOD2 slots.
3. Drop directly on a row or use **Assign…** / **Replace…** to correct a slot.
4. Keep the default `CS2 Export` destination or choose another location.
5. Choose **Export Main**, **Export LOD2**, or **Export All**.

The default destination is:

```text
<BaseColor source folder>/CS2 Export
```

The generated folder is ignored when the source folder is scanned again.
Existing files in the destination are listed for confirmation before they are
replaced.

## Updates

CS2 Combiner checks the latest stable GitHub Release when it opens. If a newer
version is available, an in-app banner offers **Update Now**, **View Release**,
or **Later**. You can also use **Check for Updates…** from the app menu.

The updater selects the macOS release ZIP, verifies its published GitHub
SHA-256 digest, validates the app identity, version, and code signature, and
then replaces and reopens the current app. The app must be in a writable folder;
translocated copies must be moved to Applications first.

## Asset profiles

Choose **Building**, **Surface**, or **Decal** before importing. Building writes
the five-map building set and supports LOD2. Surface writes its three-map tiling
set with the Surface-specific MaskMap channels. Decal writes the three required
BaseColor, MaskMap, and Normal files; optional ControlMask and Emissive files
are hidden under **Experimental maps (untested)** and written only after that
section is deliberately opened and a source slot is supplied.

## Main texture requirements

BaseColor is required and must be a square 512, 1024, 2048, or 4096 pixel image.
Every assigned main map must have exactly the same dimensions. Textures are
never resized, and a mismatch stops the export before any output is written.

The asset name is inferred from the BaseColor filename. For example,
`Brick_Wall_v2_BaseColor.png` produces:

- `Brick_Wall_v2_BaseColor.png`
- `Brick_Wall_v2_ControlMask.png`
- `Brick_Wall_v2_MaskMap.png`
- `Brick_Wall_v2_Normal.png`
- `Brick_Wall_v2_Emissive.png`

### Packing

- **BaseColor:** BaseColor RGB plus embedded alpha when present; otherwise the
  Opacity red channel. **Override BaseColor alpha** makes an assigned Opacity
  map take priority.
- **ControlMask:** ColorMask1, ColorMask2, ColorMask3, and Snow Remove red
  channels packed into RGBA.
- **MaskMap:** Metallic red, Coat red, black, and inverted Roughness red packed
  into RGBA.
- **Normal:** OpenGL Normal RGB, optionally normalised during export.
- **Emissive:** Emissive RGB.

Missing optional maps use safe black, white, rough, or neutral-normal defaults.
Normalisation occurs only in memory during export; assigned source maps are
never modified.

For Decal, MaskMap uses the same Metallic, Coat, unused-black, and inverted
Roughness layout. Missing Normal input produces the required flat OpenGL normal.

## LOD2

LOD2 inputs must already be exactly 512 × 512. Maps are grouped by their shared
asset name. A 512 × 512 flat OpenGL normal (`128, 128, 255`) is always written
when no LOD2 Normal input is assigned; the other combined outputs are written
when their required inputs are supplied. By default, LOD2 output uses the same
`CS2 Export` folder as the main textures.

## Build from source

### macOS

The native macOS app is a SwiftPM executable:

```sh
swift test --disable-sandbox
./script/build_cs2_combiner.sh
```

The standalone local app is built at `dist/CS2 Combiner.app`.

### Windows

The Windows port uses .NET 8 and Avalonia:

```sh
dotnet test Windows/CS2Combiner.Tests/CS2Combiner.Tests.csproj -c Release
./Windows/build_windows.sh
```

The build script creates self-contained ARM64 and x64 packages in
`dist/windows`.

## Distribution note

The macOS build is ad-hoc signed for local distribution. It is not Developer ID
signed or notarised.
