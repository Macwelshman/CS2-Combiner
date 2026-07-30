namespace CS2Combiner.Core;

public static class TexturePacking
{
    public static PixelSize ValidateBaseColor(InputMap? input)
    {
        if (input is null)
        {
            throw new CombinerException("Add a BaseColor map before exporting.");
        }

        ValidateMainInputSize(input.Size, input.Slot.Title());
        return input.Size;
    }

    public static void ValidateMainInputSize(PixelSize size, string name)
    {
        if (!size.IsSquare || size.Width is not (1024 or 2048 or 4096))
        {
            throw new CombinerException(
                $"{name} must be square and exactly 1024, 2048, or 4096 pixels. It is {size}.");
        }
    }

    public static void ValidateInputSizes(
        IReadOnlyDictionary<MapSlot, InputMap> inputs,
        PixelSize targetSize)
    {
        if (!inputs.TryGetValue(MapSlot.BaseColor, out var baseColor))
        {
            throw new CombinerException("Add a BaseColor map before exporting.");
        }

        if (targetSize != baseColor.Size)
        {
            throw new CombinerException(
                $"The export size {targetSize} does not match the imported BaseColor size {baseColor.Size}. Textures are never resized.");
        }

        var mismatches = inputs.Values
            .Where(input => input.Size != baseColor.Size)
            .OrderBy(input => input.Slot.Title(), StringComparer.CurrentCulture)
            .Select(input => $"{input.Slot.Title()}: {input.Size}")
            .ToArray();
        if (mismatches.Length > 0)
        {
            throw new CombinerException(
                $"All assigned main maps must match the BaseColor size {baseColor.Size}. Textures are never resized.\n\n" +
                string.Join('\n', mismatches));
        }
    }

    public static IReadOnlyList<string> Export(TextureExportPlan plan)
    {
        ValidateInputSizes(plan.Inputs, plan.TargetSize);
        Directory.CreateDirectory(plan.OutputDirectory);
        var staging = Path.Combine(plan.OutputDirectory, $".cs2-combiner-{Guid.NewGuid():N}");
        Directory.CreateDirectory(staging);

        try
        {
            WriteBaseColor(plan, Path.Combine(staging, plan.OutputName("BaseColor")));
            WriteControlMask(plan, Path.Combine(staging, plan.OutputName("ControlMask")));
            WriteMaskMap(plan, Path.Combine(staging, plan.OutputName("MaskMap")));
            WriteNormal(plan, Path.Combine(staging, plan.OutputName("Normal")));
            WriteEmissive(plan, Path.Combine(staging, plan.OutputName("Emissive")));

            foreach (var name in plan.OutputNames)
            {
                File.Move(Path.Combine(staging, name), Path.Combine(plan.OutputDirectory, name), true);
            }
        }
        finally
        {
            if (Directory.Exists(staging))
            {
                Directory.Delete(staging, true);
            }
        }

        return plan.OutputPaths;
    }

    private static void WriteBaseColor(TextureExportPlan plan, string path)
    {
        if (!plan.Inputs.TryGetValue(MapSlot.BaseColor, out var baseInput))
        {
            throw new CombinerException("Add a BaseColor map before exporting.");
        }

        var usesEmbeddedAlpha = ImageCodec.HasAlphaChannel(baseInput.Path);
        var raster = ImageCodec.Load(baseInput.Path);
        var usesOpacityMap =
            plan.Inputs.ContainsKey(MapSlot.Opacity) &&
            (!usesEmbeddedAlpha || plan.OpacityMapOverridesBaseColorAlpha);
        var opacity = usesOpacityMap
            ? ImageCodec.Load(plan.Inputs[MapSlot.Opacity].Path)
            : null;

        for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
        {
            if (opacity is not null)
            {
                raster.Bytes[pixel * 4 + 3] = opacity.Red(pixel);
            }
            else if (!usesEmbeddedAlpha)
            {
                raster.Bytes[pixel * 4 + 3] = byte.MaxValue;
            }
        }

        ImageCodec.WritePng(raster, path);
    }

    private static void WriteControlMask(TextureExportPlan plan, string path)
    {
        var channels = new[]
        {
            Raster(plan, MapSlot.ColorMask1),
            Raster(plan, MapSlot.ColorMask2),
            Raster(plan, MapSlot.ColorMask3),
            Raster(plan, MapSlot.SnowRemove)
        };
        var output = ImageRaster.Solid(plan.TargetSize, 0, 0, 0, 0);
        for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
        {
            for (var channel = 0; channel < 4; channel++)
            {
                output.Bytes[pixel * 4 + channel] = channels[channel]?.Red(pixel) ?? 0;
            }
        }

        ImageCodec.WritePng(output, path);
    }

    private static void WriteMaskMap(TextureExportPlan plan, string path)
    {
        var metallic = Raster(plan, MapSlot.Metallic);
        var coat = Raster(plan, MapSlot.Coat);
        var roughness = Raster(plan, MapSlot.Roughness);
        var output = ImageRaster.Solid(plan.TargetSize, 0, 0, 0, 0);
        for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
        {
            var index = pixel * 4;
            output.Bytes[index] = metallic?.Red(pixel) ?? 0;
            output.Bytes[index + 1] = coat?.Red(pixel) ?? 0;
            output.Bytes[index + 2] = 0;
            output.Bytes[index + 3] = (byte)(255 - (roughness?.Red(pixel) ?? 255));
        }

        ImageCodec.WritePng(output, path);
    }

    private static void WriteNormal(TextureExportPlan plan, string path)
    {
        var normal = Raster(plan, MapSlot.Normal);
        if (normal is null)
        {
            ImageCodec.WritePng(ImageRaster.Solid(plan.TargetSize, 128, 128, 255), path);
            return;
        }

        if (plan.NormalizeNormalOnExport)
        {
            NormalMapNormalization.Normalize(normal);
        }

        for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
        {
            normal.Bytes[pixel * 4 + 3] = 255;
        }

        ImageCodec.WritePng(normal, path);
    }

    private static void WriteEmissive(TextureExportPlan plan, string path)
    {
        var emissive = Raster(plan, MapSlot.Emissive);
        if (emissive is null)
        {
            ImageCodec.WritePng(ImageRaster.Solid(plan.TargetSize, 0, 0, 0), path);
            return;
        }

        for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
        {
            emissive.Bytes[pixel * 4 + 3] = 255;
        }

        ImageCodec.WritePng(emissive, path);
    }

    private static ImageRaster? Raster(TextureExportPlan plan, MapSlot slot) =>
        plan.Inputs.TryGetValue(slot, out var input) ? ImageCodec.Load(input.Path) : null;
}
