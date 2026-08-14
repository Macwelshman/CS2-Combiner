namespace CS2Combiner.Core;

public static class Lod2TexturePacking
{
    public static IReadOnlyList<string> Export(Lod2TextureExportPlan plan)
    {
        var mismatches = plan.Inputs
            .Select(pair => (pair.Key, Size: ImageCodec.Dimensions(pair.Value)))
            .Where(pair => pair.Size != plan.TargetSize)
            .OrderBy(pair => pair.Key.Title(), StringComparer.CurrentCulture)
            .Select(pair => $"{pair.Key.Title()}: {pair.Size}")
            .ToArray();
        if (mismatches.Length > 0)
        {
            throw new CombinerException(
                "All assigned LOD2 maps must be exactly 512 × 512. Textures are never resized.\n\n" +
                string.Join('\n', mismatches));
        }

        Directory.CreateDirectory(plan.OutputDirectory);
        var outputs = new List<string>();
        if (plan.Inputs.TryGetValue(Lod2Slot.BaseColor, out var baseColor))
        {
            var output = Output(plan, "BaseColor");
            ImageCodec.WritePng(ImageCodec.Load(baseColor), output);
            outputs.Add(output);
        }

        if (plan.Inputs.Keys.Any(slot => slot is Lod2Slot.ColorMask1 or Lod2Slot.ColorMask2 or Lod2Slot.ColorMask3))
        {
            var channels = new[]
            {
                Raster(plan, Lod2Slot.ColorMask1),
                Raster(plan, Lod2Slot.ColorMask2),
                Raster(plan, Lod2Slot.ColorMask3)
            };
            var outputRaster = ImageRaster.Solid(plan.TargetSize, 0, 0, 0, 0);
            for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
            {
                var index = pixel * 4;
                outputRaster.Bytes[index] = channels[0]?.Red(pixel) ?? 0;
                outputRaster.Bytes[index + 1] = channels[1]?.Red(pixel) ?? 0;
                outputRaster.Bytes[index + 2] = channels[2]?.Red(pixel) ?? 0;
                outputRaster.Bytes[index + 3] = 0;
            }

            var output = Output(plan, "ControlMask");
            ImageCodec.WritePng(outputRaster, output);
            outputs.Add(output);
        }

        if (plan.Inputs.TryGetValue(Lod2Slot.Roughness, out var roughnessPath))
        {
            var roughness = ImageCodec.Load(roughnessPath);
            var outputRaster = ImageRaster.Solid(plan.TargetSize, 0, 0, 0, 0);
            for (var pixel = 0; pixel < plan.TargetSize.Width * plan.TargetSize.Height; pixel++)
            {
                outputRaster.Bytes[pixel * 4 + 3] = (byte)(255 - roughness.Red(pixel));
            }

            var output = Output(plan, "MaskMap");
            ImageCodec.WritePng(outputRaster, output);
            outputs.Add(output);
        }

        var normal = plan.Inputs.TryGetValue(Lod2Slot.Normal, out var normalPath)
            ? ImageCodec.Load(normalPath)
            : ImageRaster.Solid(plan.TargetSize, 128, 128, 255);
        var normalOutput = Output(plan, "Normal");
        ImageCodec.WritePng(normal, normalOutput);
        outputs.Add(normalOutput);

        if (plan.Inputs.TryGetValue(Lod2Slot.Emissive, out var emissivePath))
        {
            var output = Output(plan, "Emissive");
            ImageCodec.WritePng(ImageCodec.Load(emissivePath), output);
            outputs.Add(output);
        }

        return outputs;
    }

    private static ImageRaster? Raster(Lod2TextureExportPlan plan, Lod2Slot slot) =>
        plan.Inputs.TryGetValue(slot, out var path) ? ImageCodec.Load(path) : null;

    private static string Output(Lod2TextureExportPlan plan, string suffix) =>
        Path.Combine(plan.OutputDirectory, $"{plan.AssetName}_LOD2_{suffix}.png");
}
