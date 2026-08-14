using System.Globalization;

namespace CS2Combiner.Core;

public readonly record struct PixelSize(int Width, int Height)
{
    public bool IsSquare => Width == Height;
    public override string ToString() => $"{Width} × {Height}";
}

public enum MapSlot
{
    BaseColor,
    Opacity,
    ColorMask1,
    ColorMask2,
    ColorMask3,
    SnowRemove,
    Metallic,
    Coat,
    Roughness,
    Normal,
    Emissive
}

public static class MapSlotInfo
{
    public static IReadOnlyList<MapSlot> All { get; } = Enum.GetValues<MapSlot>();

    public static string Title(this MapSlot slot) => slot switch
    {
        MapSlot.BaseColor => "BaseColor",
        MapSlot.Opacity => "Opacity",
        MapSlot.ColorMask1 => "ColorMask1",
        MapSlot.ColorMask2 => "ColorMask2",
        MapSlot.ColorMask3 => "ColorMask3",
        MapSlot.SnowRemove => "Snow Remove",
        MapSlot.Metallic => "Metallic",
        MapSlot.Coat => "Coat",
        MapSlot.Roughness => "Roughness",
        MapSlot.Normal => "Normal",
        MapSlot.Emissive => "Emissive",
        _ => slot.ToString()
    };

    public static string ChannelDescription(this MapSlot slot) => slot switch
    {
        MapSlot.BaseColor => "BaseColor RGB + embedded Alpha",
        MapSlot.Opacity => "BaseColor Alpha fallback · default white",
        MapSlot.ColorMask1 => "ControlMask Red · default black",
        MapSlot.ColorMask2 => "ControlMask Green · default black",
        MapSlot.ColorMask3 => "ControlMask Blue · default black",
        MapSlot.SnowRemove => "ControlMask Alpha · default black",
        MapSlot.Metallic => "MaskMap Red · default black",
        MapSlot.Coat => "MaskMap Green · default black",
        MapSlot.Roughness => "MaskMap Alpha · inverted · default rough",
        MapSlot.Normal => "Normal RGB · default neutral",
        MapSlot.Emissive => "Emissive RGB · default black",
        _ => string.Empty
    };
}

public enum Lod2Slot
{
    BaseColor,
    ColorMask1,
    ColorMask2,
    ColorMask3,
    Roughness,
    Normal,
    Emissive
}

public static class Lod2SlotInfo
{
    public static IReadOnlyList<Lod2Slot> All { get; } = Enum.GetValues<Lod2Slot>();

    public static string Title(this Lod2Slot slot) => slot switch
    {
        Lod2Slot.BaseColor => "BaseColor",
        Lod2Slot.ColorMask1 => "ColorMask1",
        Lod2Slot.ColorMask2 => "ColorMask2",
        Lod2Slot.ColorMask3 => "ColorMask3",
        Lod2Slot.Roughness => "Roughness",
        Lod2Slot.Normal => "Normal",
        Lod2Slot.Emissive => "Emissive",
        _ => slot.ToString()
    };
}

public sealed record InputMap(MapSlot Slot, string Path, PixelSize Size);

public sealed record Lod2Set(string Name, Dictionary<Lod2Slot, string> Inputs);

public enum OpacitySourceKind
{
    BaseColorAlpha,
    OpacityMap,
    OpaqueDefault
}

public readonly record struct OpacitySource(
    OpacitySourceKind Kind,
    bool OpacityMapIgnored = false,
    bool OverridesBaseColorAlpha = false)
{
    public static OpacitySource Resolve(
        bool hasBaseColor,
        bool baseColorHasAlpha,
        bool hasOpacityMap,
        bool opacityMapOverridesBaseColorAlpha)
    {
        if (!hasBaseColor)
        {
            return new(OpacitySourceKind.OpaqueDefault);
        }

        if (hasOpacityMap && (opacityMapOverridesBaseColorAlpha || !baseColorHasAlpha))
        {
            return new(
                OpacitySourceKind.OpacityMap,
                OverridesBaseColorAlpha: baseColorHasAlpha && opacityMapOverridesBaseColorAlpha);
        }

        if (baseColorHasAlpha)
        {
            return new(OpacitySourceKind.BaseColorAlpha, OpacityMapIgnored: hasOpacityMap);
        }

        return new(OpacitySourceKind.OpaqueDefault);
    }

    public string Description => (Kind, OpacityMapIgnored, OverridesBaseColorAlpha) switch
    {
        (OpacitySourceKind.BaseColorAlpha, false, _) => "Opacity: BaseColor alpha",
        (OpacitySourceKind.BaseColorAlpha, true, _) => "Opacity: BaseColor alpha · Opacity map ignored",
        (OpacitySourceKind.OpacityMap, _, false) => "Opacity: Opacity map",
        (OpacitySourceKind.OpacityMap, _, true) => "Opacity: Opacity map · overriding BaseColor alpha",
        _ => "Opacity: Opaque default"
    };
}

public sealed record TextureExportPlan(
    IReadOnlyDictionary<MapSlot, InputMap> Inputs,
    PixelSize TargetSize,
    string OutputDirectory,
    string AssetName,
    bool OpacityMapOverridesBaseColorAlpha = false,
    bool NormalizeNormalOnExport = false)
{
    public static IReadOnlyList<string> OutputSuffixes { get; } =
        ["BaseColor", "ControlMask", "MaskMap", "Normal", "Emissive"];

    public IReadOnlyList<string> OutputNames =>
        OutputSuffixes.Select(OutputName).ToArray();

    public IReadOnlyList<string> OutputPaths =>
        OutputNames.Select(name => Path.Combine(OutputDirectory, name)).ToArray();

    public string OutputName(string suffix) => $"{AssetName}_{suffix}.png";
}

public sealed record Lod2TextureExportPlan(
    IReadOnlyDictionary<Lod2Slot, string> Inputs,
    string AssetName,
    string OutputDirectory)
{
    public PixelSize TargetSize { get; } = new(512, 512);

    public IReadOnlyList<string> OutputPaths
    {
        get
        {
            var suffixes = new List<string>();
            if (Inputs.ContainsKey(Lod2Slot.BaseColor)) suffixes.Add("BaseColor");
            if (Inputs.Keys.Any(slot => slot is Lod2Slot.ColorMask1 or Lod2Slot.ColorMask2 or Lod2Slot.ColorMask3))
                suffixes.Add("ControlMask");
            if (Inputs.ContainsKey(Lod2Slot.Roughness)) suffixes.Add("MaskMap");
            suffixes.Add("Normal");
            if (Inputs.ContainsKey(Lod2Slot.Emissive)) suffixes.Add("Emissive");
            return suffixes
                .Select(suffix => Path.Combine(OutputDirectory, $"{AssetName}_LOD2_{suffix}.png"))
                .ToArray();
        }
    }
}

public static class AppSpelling
{
    public static string Normalize(CultureInfo? culture = null)
    {
        culture ??= CultureInfo.CurrentCulture;
        return culture.Name.StartsWith("en-US", StringComparison.OrdinalIgnoreCase)
            ? "Normalize"
            : "Normalise";
    }
}

public static class ExportAvailability
{
    public static bool ShowsExportAll(bool hasBaseColor, bool hasLod2Sets) =>
        hasBaseColor && hasLod2Sets;
}

public sealed class CombinerException(string message) : Exception(message);
