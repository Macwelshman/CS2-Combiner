# CS2 Combiner for Windows

This directory contains the Windows port of CS2 Combiner. It is intentionally
separate from the native SwiftUI macOS application.

## Projects

- `CS2Combiner.Core` — cross-platform detection, validation and exact RGBA
  texture packing.
- `CS2Combiner.App` — Avalonia desktop interface for Windows and macOS
  development.
- `CS2Combiner.Tests` — parity tests for naming, alpha precedence, packed
  channels, safe defaults, export-only normalisation and LOD2 output.

## Build and test on macOS

```sh
dotnet test Windows/CS2Combiner.Tests/CS2Combiner.Tests.csproj -c Release
dotnet build Windows/CS2Combiner.sln -c Release
```

Run the development interface on macOS:

```sh
dotnet run --project Windows/CS2Combiner.App/CS2Combiner.App.csproj
```

## Publish for UTM and Windows

```sh
./Windows/build_windows.sh
```

The script tests the packing core and creates:

- `dist/windows/CS2-Combiner-0.3.3-windows-arm64.zip`
- `dist/windows/CS2-Combiner-0.3.3-windows-x64.zip`

Use the ARM64 build natively in a Windows 11 ARM UTM virtual machine. Use the
x64 build to verify Windows 11 ARM's x64 compatibility and for conventional
Intel/AMD Windows computers.

The packages are self-contained: the target PC does not need a separate .NET
installation. Extract the ZIP and run `CS2Combiner.exe`.

## UTM checklist

1. Copy the ZIP into the UTM shared directory.
2. Extract it inside Windows rather than running it from the ZIP.
3. Start `CS2Combiner.exe`.
4. Import individual maps and a complete texture folder.
5. Verify automatic slot detection, manual replacement and row-level drops.
6. Export main maps, LOD2 maps and `Export All`.
7. Confirm dimensions, exact filenames and overwrite prompts.
8. Compare exported pixels with the macOS reference output.

## Supported input images

PNG, TIFF, BMP and JPEG are decoded cross-platform. HEIC is not included in the
portable build because support depends on an optional Windows codec; convert
HEIC sources to PNG or TIFF before importing them.

## Behaviour preserved from macOS

- Building, Surface, and Decal profiles use their distinct output sets and
  MaskMap layouts. Decal ControlMask and Emissive outputs are hidden in an
  explicitly enabled experimental section because the guide marks them untested.
- BaseColor is required and main maps must be matching square 512, 1024, 2048
  or 4096 pixel images.
- LOD2 inputs must already be 512 × 512.
- Textures are never resized or modified.
- Embedded BaseColor alpha takes precedence unless `Override BaseColor alpha`
  is enabled.
- Normalisation occurs only in memory while exporting.
- Main output defaults to `CS2 Export` inside the BaseColor source folder, or
  writes directly into a manually selected folder.
- `Export All` is shown only when main and LOD2 inputs coexist.
- Output filenames and channel packing match the native macOS application.

## Updates

The Windows app checks the latest stable GitHub Release when it opens. An
available update can be reviewed, downloaded, verified, and installed from the
app banner. **Check for Updates…** is also available in the main window.

The updater selects the package matching Windows ARM64 or Windows x64, verifies
the published GitHub SHA-256 digest and packaged version, then restarts the app.
It updates only files supplied by the new package and leaves unrelated files in
the app folder untouched.
