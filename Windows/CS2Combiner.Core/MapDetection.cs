using System.Text.RegularExpressions;

namespace CS2Combiner.Core;

public static partial class MapDetector
{
    private static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ".png", ".tif", ".tiff", ".bmp", ".jpg", ".jpeg"
        };

    private static readonly (MapSlot Slot, string[] Tokens)[] Rules =
    [
        (MapSlot.SnowRemove, ["snowremove", "snowremoval"]),
        (MapSlot.BaseColor, ["basecolor", "basecolour", "albedo", "diffuse"]),
        (MapSlot.Opacity, ["opacity", "transparency", "alpha"]),
        (MapSlot.ColorMask1, ["controlmask1", "control1", "cm1", "colormask1", "colourmask1", "colormaskone", "colourmaskone"]),
        (MapSlot.ColorMask2, ["controlmask2", "control2", "cm2", "colormask2", "colourmask2", "colormasktwo", "colourmasktwo"]),
        (MapSlot.ColorMask3, ["controlmask3", "control3", "cm3", "colormask3", "colourmask3", "colormaskthree", "colourmaskthree"]),
        (MapSlot.Metallic, ["metallic", "metalness"]),
        (MapSlot.Coat, ["clearcoat", "coat"]),
        (MapSlot.Roughness, ["roughness", "rough"]),
        (MapSlot.Emissive, ["emissive", "emission", "emit"]),
        (MapSlot.Normal, ["normalgl", "openglnormal", "opengl", "normal"])
    ];

    public static MapSlot? DetectSlot(string path)
    {
        var name = NormalizedStem(path);
        foreach (var rule in Rules)
        {
            if (rule.Tokens.Any(name.Contains))
            {
                return rule.Slot;
            }
        }

        return null;
    }

    public static bool IsDirectXNormal(string path)
    {
        var name = NormalizedStem(path);
        return name.Contains("directx", StringComparison.Ordinal) ||
               name.Contains("normaldx", StringComparison.Ordinal) ||
               name.Contains("dxnormal", StringComparison.Ordinal);
    }

    public static IReadOnlyList<string> ImagePaths(IEnumerable<string> droppedPaths)
    {
        var results = new List<string>();
        foreach (var path in droppedPaths)
        {
            if (Directory.Exists(path))
            {
                foreach (var candidate in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                {
                    if (IsInsideGeneratedFolder(candidate) || !IsSupportedImage(candidate))
                    {
                        continue;
                    }

                    results.Add(Path.GetFullPath(candidate));
                }
            }
            else if (IsSupportedImage(path))
            {
                results.Add(Path.GetFullPath(path));
            }
        }

        results.Sort(StringComparer.CurrentCultureIgnoreCase);
        return results;
    }

    public static bool IsSupportedImage(string path)
    {
        if (!SupportedExtensions.Contains(Path.GetExtension(path)) || !File.Exists(path))
        {
            return false;
        }

        try
        {
            _ = ImageCodec.Dimensions(path);
            return true;
        }
        catch (CombinerException)
        {
            return false;
        }
    }

    private static bool IsInsideGeneratedFolder(string path) =>
        Path.GetDirectoryName(path)?
            .Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Any(component =>
            {
                var value = component.ToLowerInvariant();
                return value is "export files" or "cs2 export" or "cs2 textures" ||
                       value.EndsWith(" export files", StringComparison.Ordinal) ||
                       value.EndsWith(" cs2 export", StringComparison.Ordinal) ||
                       value.EndsWith(" cs2 textures", StringComparison.Ordinal);
            }) == true;

    private static string NormalizedStem(string path) =>
        string.Concat(Path.GetFileNameWithoutExtension(path)
            .ToLowerInvariant()
            .Where(char.IsLetterOrDigit));
}

public static partial class AssetNaming
{
    private const string SuffixPattern =
        "base[ _-]*colou?r|albedo|diffuse|opacity|transparency|alpha|" +
        "control[ _-]*mask[ _-]*[123]|control[ _-]*[123]|cm[ _-]*[123]|" +
        "snow[ _-]*remove|metallic|metalness|clear[ _-]*coat|coat|" +
        "roughness|rough|normal[ _-]*gl|open[ _-]*gl[ _-]*normal|" +
        "open[ _-]*gl|normal|emissive|emission";

    [GeneratedRegex(@"[ _.-]*(?:" + SuffixPattern + @")[ _.-]*$", RegexOptions.IgnoreCase)]
    private static partial Regex MapSuffixRegex();

    public static string InferredAssetName(string sourcePath)
    {
        var stem = Path.GetFileNameWithoutExtension(sourcePath);
        var inferred = MapSuffixRegex().Replace(stem, string.Empty).Trim(' ', '_', '.', '-');
        if (inferred.Length > 0)
        {
            return inferred;
        }

        var parent = Directory.GetParent(Path.GetFullPath(sourcePath))?.Name.Trim(' ', '.');
        return string.IsNullOrEmpty(parent) ? "CS2 texture" : parent;
    }

    public static string OutputDirectory(string baseColorPath, string? customRoot)
    {
        if (customRoot is not null)
        {
            return customRoot;
        }

        var sourceDirectory = Path.GetDirectoryName(Path.GetFullPath(baseColorPath))
            ?? throw new CombinerException("The BaseColor source folder could not be resolved.");
        return Path.Combine(sourceDirectory, "CS2 Export");
    }
}

public static partial class Lod2Detector
{
    public static Lod2Slot? DetectSlot(string path)
    {
        var stem = Lod2SuffixRegex().Replace(Path.GetFileNameWithoutExtension(path), string.Empty);
        var name = string.Concat(stem.ToLowerInvariant().Where(char.IsLetterOrDigit));
        if (ContainsAny(name, "colormask1", "colourmask1", "colormaskone", "colourmaskone", "cm1")) return Lod2Slot.ColorMask1;
        if (ContainsAny(name, "colormask2", "colourmask2", "colormasktwo", "colourmasktwo", "cm2")) return Lod2Slot.ColorMask2;
        if (ContainsAny(name, "colormask3", "colourmask3", "colormaskthree", "colourmaskthree", "cm3")) return Lod2Slot.ColorMask3;
        if (ContainsAny(name, "roughness", "rough")) return Lod2Slot.Roughness;
        if (ContainsAny(name, "emissive", "emission", "emit")) return Lod2Slot.Emissive;
        if (name.Contains("normal", StringComparison.Ordinal)) return Lod2Slot.Normal;
        if (ContainsAny(name, "basecolor", "basecolour", "albedo", "diffuse")) return Lod2Slot.BaseColor;
        return null;
    }

    public static bool IsCandidate(string path)
    {
        var slot = DetectSlot(path);
        return slot.HasValue && IsLod2File(path, slot.Value);
    }

    public static bool IsLod2File(string path, Lod2Slot slot) =>
        Regex.IsMatch(
            Path.GetFileNameWithoutExtension(path),
            $"(?i)(?:{Suffix(slot)}[ _.-]*lod[ _-]*2|lod[ _-]*2[ _.-]*{Suffix(slot)})$");

    public static string SetName(string path, Lod2Slot slot)
    {
        var stem = Path.GetFileNameWithoutExtension(path);
        var result = Regex.Replace(
            stem,
            $"(?i)[ _.-]*(?:(?:lod[ _-]*2)[ _.-]*{Suffix(slot)}|{Suffix(slot)}[ _.-]*(?:lod[ _-]*2))$",
            string.Empty).Trim(' ', '_', '.', '-');
        return result.Length == 0 ? AssetNaming.InferredAssetName(path) : result;
    }

    private static bool ContainsAny(string value, params string[] tokens) =>
        tokens.Any(value.Contains);

    private static string Suffix(Lod2Slot slot) => slot switch
    {
        Lod2Slot.BaseColor => "(?:base[ _-]*colou?r|albedo|diffuse)",
        Lod2Slot.ColorMask1 => "(?:colou?r[ _-]*mask[ _-]*(?:1|one)|cm[ _-]*1)",
        Lod2Slot.ColorMask2 => "(?:colou?r[ _-]*mask[ _-]*(?:2|two)|cm[ _-]*2)",
        Lod2Slot.ColorMask3 => "(?:colou?r[ _-]*mask[ _-]*(?:3|three)|cm[ _-]*3)",
        Lod2Slot.Roughness => "(?:roughness|rough)",
        Lod2Slot.Normal => "(?:normal)",
        Lod2Slot.Emissive => "(?:emissive|emission|emit)",
        _ => throw new ArgumentOutOfRangeException(nameof(slot), slot, null)
    };

    [GeneratedRegex(@"(?i)[ _.-]*lod[ _-]*2$")]
    private static partial Regex Lod2SuffixRegex();
}
