using System.Globalization;
using CS2Combiner.Core;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace CS2Combiner.Tests;

public sealed class CoreTests
{
    [Fact]
    public void ExportAllRequiresMainAndLod2()
    {
        Assert.False(ExportAvailability.ShowsExportAll(false, true));
        Assert.False(ExportAvailability.ShowsExportAll(true, false));
        Assert.False(ExportAvailability.ShowsExportAll(false, false));
        Assert.True(ExportAvailability.ShowsExportAll(true, true));
    }

    [Fact]
    public void NormalizeLabelFollowsEnglishLocaleVariant()
    {
        Assert.Equal("Normalise", AppSpelling.Normalize(CultureInfo.GetCultureInfo("en-GB")));
        Assert.Equal("Normalize", AppSpelling.Normalize(CultureInfo.GetCultureInfo("en-US")));
    }

    [Theory]
    [InlineData(true, true, false, false, "Opacity: BaseColor alpha")]
    [InlineData(true, true, true, false, "Opacity: BaseColor alpha · Opacity map ignored")]
    [InlineData(true, false, true, false, "Opacity: Opacity map")]
    [InlineData(true, false, false, false, "Opacity: Opaque default")]
    [InlineData(true, true, true, true, "Opacity: Opacity map · overriding BaseColor alpha")]
    public void OpacitySourceDescriptions(
        bool hasBaseColor,
        bool baseColorHasAlpha,
        bool hasOpacityMap,
        bool overrideAlpha,
        string expected)
    {
        Assert.Equal(
            expected,
            OpacitySource.Resolve(
                hasBaseColor,
                baseColorHasAlpha,
                hasOpacityMap,
                overrideAlpha).Description);
    }

    [Fact]
    public void FilenameDetectionMatchesMacContract()
    {
        Assert.Equal(MapSlot.BaseColor, MapDetector.DetectSlot("/tmp/wall_BaseColor.png"));
        Assert.Equal(MapSlot.ColorMask2, MapDetector.DetectSlot("/tmp/wall_CM2.tif"));
        Assert.Equal(MapSlot.ColorMask1, MapDetector.DetectSlot("/tmp/wall_Colour Mask One.png"));
        Assert.Equal(MapSlot.ColorMask2, MapDetector.DetectSlot("/tmp/wall_Color_Mask_Two.png"));
        Assert.Equal(MapSlot.ColorMask3, MapDetector.DetectSlot("/tmp/wall_colour-mask-three.png"));
        Assert.Equal(MapSlot.SnowRemove, MapDetector.DetectSlot("/tmp/wall_Snow_Remove.png"));
        Assert.Equal(MapSlot.Normal, MapDetector.DetectSlot("/tmp/wall_NormalGL.png"));
        Assert.True(MapDetector.IsDirectXNormal("/tmp/wall_NormalDX.png"));
        Assert.Null(MapDetector.DetectSlot("/tmp/notes.png"));
    }

    [Fact]
    public void AssetNameAndDefaultExportFolderMatchMacContract()
    {
        var separator = Path.DirectorySeparatorChar;
        var baseColor = $"{separator}Textures{separator}Brick_Wall_v2_BaseColor.png";
        Assert.Equal("Brick_Wall_v2", AssetNaming.InferredAssetName(baseColor));
        Assert.Equal(
            $"{separator}Textures{separator}CS2 Export",
            AssetNaming.OutputDirectory(baseColor, null));
        Assert.Equal(
            $"{separator}Exports",
            AssetNaming.OutputDirectory(baseColor, $"{separator}Exports"));
    }

    [Fact]
    public void BareMapNameFallsBackToFolder()
    {
        var path = Path.Combine(
            Path.DirectorySeparatorChar.ToString(),
            "Materials",
            "Old_Brick",
            "BaseColor.png");
        Assert.Equal("Old_Brick", AssetNaming.InferredAssetName(path));
    }

    [Theory]
    [InlineData(512)]
    [InlineData(1024)]
    [InlineData(2048)]
    [InlineData(4096)]
    public void MainValidationAcceptsOnlyContractSizes(int dimension)
    {
        var input = new InputMap(
            MapSlot.BaseColor,
            "/tmp/BaseColor.png",
            new(dimension, dimension));
        Assert.Equal(input.Size, TexturePacking.ValidateBaseColor(input));
    }

    [Theory]
    [InlineData(256, 256)]
    [InlineData(1024, 512)]
    [InlineData(8192, 8192)]
    public void MainValidationRejectsOtherSizes(int width, int height)
    {
        var input = new InputMap(MapSlot.BaseColor, "/tmp/BaseColor.png", new(width, height));
        var error = Assert.Throws<CombinerException>(() => TexturePacking.ValidateBaseColor(input));
        Assert.Contains("exactly 512, 1024, 2048, or 4096", error.Message);
    }

    [Fact]
    public void ExportValidationRejectsUnsupportedBaseColorSize()
    {
        var size = new PixelSize(256, 256);
        var baseColor = new InputMap(MapSlot.BaseColor, "/tmp/BaseColor.png", size);
        IReadOnlyDictionary<MapSlot, InputMap> inputs =
            new Dictionary<MapSlot, InputMap> { [MapSlot.BaseColor] = baseColor };

        var error = Assert.Throws<CombinerException>(
            () => TexturePacking.ValidateInputSizes(inputs, size));
        Assert.Contains("exactly 512, 1024, 2048, or 4096", error.Message);
    }

    [Fact]
    public void FolderScanSkipsDefaultExportFolder()
    {
        using var temporary = new TemporaryFolder();
        var source = Path.Combine(temporary.Path, "Brick_BaseColor.png");
        var generated = Path.Combine(temporary.Path, "CS2 Export");
        Directory.CreateDirectory(generated);
        var priorOutput = Path.Combine(generated, "Brick_BaseColor.png");
        ImageCodec.WritePng(Solid(new(1, 1), 1, 2, 3), source);
        ImageCodec.WritePng(Solid(new(1, 1), 4, 5, 6), priorOutput);

        Assert.Equal([source], MapDetector.ImagePaths([temporary.Path]));
    }

    [Fact]
    public void PackingRejectsMismatchesBeforeCreatingOutput()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var basePath = Path.Combine(temporary.Path, "Brick_BaseColor.png");
        var opacityPath = Path.Combine(temporary.Path, "Brick_Opacity.png");
        ImageCodec.WritePng(Solid(new(512, 512), 20, 40, 60), basePath);
        ImageCodec.WritePng(Solid(new(256, 256), 170, 0, 0), opacityPath);
        var plan = new TextureExportPlan(
            new Dictionary<MapSlot, InputMap>
            {
                [MapSlot.BaseColor] = new(MapSlot.BaseColor, basePath, new(512, 512)),
                [MapSlot.Opacity] = new(MapSlot.Opacity, opacityPath, new(256, 256))
            },
            new(512, 512),
            output,
            "Brick");

        var error = Assert.Throws<CombinerException>(() => TexturePacking.Export(plan));
        Assert.Contains("Textures are never resized", error.Message);
        Assert.Contains("Opacity: 256 × 256", error.Message);
        Assert.False(Directory.Exists(output));
    }

    [Fact]
    public void ExportsFiveCorrectlyPackedPngs()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var size = new PixelSize(512, 512);
        var values = new Dictionary<MapSlot, (byte Red, byte Green, byte Blue)>
        {
            [MapSlot.BaseColor] = (20, 40, 60),
            [MapSlot.Opacity] = (70, 0, 0),
            [MapSlot.ColorMask1] = (11, 0, 0),
            [MapSlot.ColorMask2] = (22, 0, 0),
            [MapSlot.ColorMask3] = (33, 0, 0),
            [MapSlot.SnowRemove] = (44, 0, 0),
            [MapSlot.Metallic] = (55, 0, 0),
            [MapSlot.Coat] = (66, 0, 0),
            [MapSlot.Roughness] = (77, 0, 0),
            [MapSlot.Normal] = (128, 128, 255),
            [MapSlot.Emissive] = (8, 9, 10)
        };
        var inputs = new Dictionary<MapSlot, InputMap>();
        foreach (var (slot, color) in values)
        {
            var path = Path.Combine(temporary.Path, $"{slot}.png");
            if (slot == MapSlot.BaseColor)
            {
                WriteRgbPng(size, color.Red, color.Green, color.Blue, path);
            }
            else
            {
                ImageCodec.WritePng(Solid(size, color.Red, color.Green, color.Blue), path);
            }
            inputs[slot] = new(slot, path, size);
        }

        var plan = new TextureExportPlan(inputs, size, output, "Brick_Wall_v2");
        Assert.Equal(
            [
                "Brick_Wall_v2_BaseColor.png",
                "Brick_Wall_v2_ControlMask.png",
                "Brick_Wall_v2_MaskMap.png",
                "Brick_Wall_v2_Normal.png",
                "Brick_Wall_v2_Emissive.png"
            ],
            plan.OutputNames);

        Assert.Equal(5, TexturePacking.Export(plan).Count);
        Assert.Equal([20, 40, 60, 70], FirstPixel(Path.Combine(output, "Brick_Wall_v2_BaseColor.png")));
        Assert.Equal([11, 22, 33, 44], FirstPixel(Path.Combine(output, "Brick_Wall_v2_ControlMask.png")));
        Assert.Equal([55, 66, 0, 178], FirstPixel(Path.Combine(output, "Brick_Wall_v2_MaskMap.png")));
        Assert.Equal([128, 128, 255, 255], FirstPixel(Path.Combine(output, "Brick_Wall_v2_Normal.png")));
        Assert.Equal([8, 9, 10, 255], FirstPixel(Path.Combine(output, "Brick_Wall_v2_Emissive.png")));
    }

    [Fact]
    public void EmbeddedAlphaWinsUnlessOverrideIsEnabled()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var size = new PixelSize(512, 512);
        var basePath = Path.Combine(temporary.Path, "Glass_BaseColor.png");
        var opacityPath = Path.Combine(temporary.Path, "Glass_Opacity.png");
        ImageCodec.WritePng(Solid(size, 20, 40, 60, 90), basePath);
        ImageCodec.WritePng(Solid(size, 170, 0, 0), opacityPath);
        var inputs = new Dictionary<MapSlot, InputMap>
        {
            [MapSlot.BaseColor] = new(MapSlot.BaseColor, basePath, size),
            [MapSlot.Opacity] = new(MapSlot.Opacity, opacityPath, size)
        };

        Assert.True(ImageCodec.HasAlphaChannel(basePath));
        TexturePacking.Export(new(inputs, size, output, "Glass"));
        Assert.Equal([20, 40, 60, 90], FirstPixel(Path.Combine(output, "Glass_BaseColor.png")));

        TexturePacking.Export(new(inputs, size, output, "Glass", true));
        Assert.Equal([20, 40, 60, 170], FirstPixel(Path.Combine(output, "Glass_BaseColor.png")));
    }

    [Fact]
    public void SafeDefaultsMatchMacContract()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var size = new PixelSize(512, 512);
        var basePath = Path.Combine(temporary.Path, "BaseColor.png");
        WriteRgbPng(size, 1, 2, 3, basePath);
        var input = new InputMap(MapSlot.BaseColor, basePath, size);

        TexturePacking.Export(new(
            new Dictionary<MapSlot, InputMap> { [MapSlot.BaseColor] = input },
            size,
            output,
            "Old_Brick"));

        Assert.Equal([1, 2, 3, 255], FirstPixel(Path.Combine(output, "Old_Brick_BaseColor.png")));
        Assert.Equal([0, 0, 0, 0], FirstPixel(Path.Combine(output, "Old_Brick_ControlMask.png")));
        Assert.Equal([0, 0, 0, 0], FirstPixel(Path.Combine(output, "Old_Brick_MaskMap.png")));
        Assert.Equal([128, 128, 255, 255], FirstPixel(Path.Combine(output, "Old_Brick_Normal.png")));
        Assert.Equal([0, 0, 0, 255], FirstPixel(Path.Combine(output, "Old_Brick_Emissive.png")));
    }

    [Fact]
    public void NormalizationChangesOnlyExportedNormal()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var size = new PixelSize(512, 512);
        var basePath = Path.Combine(temporary.Path, "Brick_BaseColor.png");
        var normalPath = Path.Combine(temporary.Path, "Brick_NormalGL.png");
        WriteRgbPng(size, 20, 40, 60, basePath);
        ImageCodec.WritePng(Solid(size, 210, 80, 190), normalPath);
        var sourceBefore = File.ReadAllBytes(normalPath);
        var inputs = new Dictionary<MapSlot, InputMap>
        {
            [MapSlot.BaseColor] = new(MapSlot.BaseColor, basePath, size),
            [MapSlot.Normal] = new(MapSlot.Normal, normalPath, size)
        };

        TexturePacking.Export(new(inputs, size, output, "Brick", NormalizeNormalOnExport: true));
        var pixel = FirstPixel(Path.Combine(output, "Brick_Normal.png"));
        var x = pixel[0] / 255.0 * 2.0 - 1.0;
        var y = pixel[1] / 255.0 * 2.0 - 1.0;
        var z = pixel[2] / 255.0 * 2.0 - 1.0;
        Assert.InRange(Math.Sqrt(x * x + y * y + z * z), 0.99, 1.01);
        Assert.Equal(sourceBefore, File.ReadAllBytes(normalPath));
        Assert.DoesNotContain(
            Directory.GetFiles(output),
            path => Path.GetFileName(path).Contains("normaliz", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Lod2PackingUsesExactDimensionsAndAlwaysExportsNormal()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var size = new PixelSize(512, 512);
        var roughness = Path.Combine(temporary.Path, "Brick_Roughness_LOD2.png");
        var mask1 = Path.Combine(temporary.Path, "Brick_ColorMask1_LOD2.png");
        ImageCodec.WritePng(Solid(size, 77, 0, 0), roughness);
        ImageCodec.WritePng(Solid(size, 11, 0, 0), mask1);
        var plan = new Lod2TextureExportPlan(
            new Dictionary<Lod2Slot, string>
            {
                [Lod2Slot.Roughness] = roughness,
                [Lod2Slot.ColorMask1] = mask1
            },
            "Brick",
            output);

        var paths = Lod2TexturePacking.Export(plan);
        Assert.Equal(3, paths.Count);
        Assert.Equal([11, 0, 0, 0], FirstPixel(Path.Combine(output, "Brick_LOD2_ControlMask.png")));
        Assert.Equal([0, 0, 0, 178], FirstPixel(Path.Combine(output, "Brick_LOD2_MaskMap.png")));
        Assert.Equal([128, 128, 255, 255], FirstPixel(Path.Combine(output, "Brick_LOD2_Normal.png")));
    }

    [Fact]
    public void Lod2RejectsNon512InputWithoutOutput()
    {
        using var temporary = new TemporaryFolder();
        var output = Path.Combine(temporary.Path, "Output");
        var source = Path.Combine(temporary.Path, "Brick_BaseColor_LOD2.png");
        ImageCodec.WritePng(Solid(new(1, 1), 20, 40, 60), source);
        var plan = new Lod2TextureExportPlan(
            new Dictionary<Lod2Slot, string> { [Lod2Slot.BaseColor] = source },
            "Brick",
            output);

        var error = Assert.Throws<CombinerException>(() => Lod2TexturePacking.Export(plan));
        Assert.Contains("exactly 512 × 512", error.Message);
        Assert.False(Directory.Exists(output));
    }

    private static ImageRaster Solid(
        PixelSize size,
        byte red,
        byte green,
        byte blue,
        byte alpha = 255) =>
        ImageRaster.Solid(size, red, green, blue, alpha);

    private static byte[] FirstPixel(string path) =>
        ImageCodec.Load(path).Bytes[..4];

    private static void WriteRgbPng(
        PixelSize size,
        byte red,
        byte green,
        byte blue,
        string path)
    {
        var pixels = Enumerable.Repeat(new Rgb24(red, green, blue), size.Width * size.Height).ToArray();
        using var image = Image.LoadPixelData<Rgb24>(pixels, size.Width, size.Height);
        image.SaveAsPng(path, new PngEncoder
        {
            BitDepth = PngBitDepth.Bit8,
            ColorType = PngColorType.Rgb
        });
    }

    private sealed class TemporaryFolder : IDisposable
    {
        public TemporaryFolder()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"CS2CombinerTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            try
            {
                Directory.Delete(Path, true);
            }
            catch (IOException)
            {
                // The OS will eventually clean its temporary directory.
            }
        }
    }
}
