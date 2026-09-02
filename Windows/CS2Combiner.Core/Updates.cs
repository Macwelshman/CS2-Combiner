using System.Text.Json.Serialization;

namespace CS2Combiner.Core;

public sealed class ReleaseAsset
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("browser_download_url")]
    public string DownloadUrl { get; init; } = "";

    [JsonPropertyName("digest")]
    public string? Digest { get; init; }
}

public sealed class GitHubRelease
{
    [JsonPropertyName("tag_name")]
    public string TagName { get; init; } = "";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("body")]
    public string Body { get; init; } = "";

    [JsonPropertyName("html_url")]
    public string HtmlUrl { get; init; } = "";

    [JsonPropertyName("draft")]
    public bool Draft { get; init; }

    [JsonPropertyName("prerelease")]
    public bool Prerelease { get; init; }

    [JsonPropertyName("assets")]
    public IReadOnlyList<ReleaseAsset> Assets { get; init; } = [];
}

public static class UpdateVersions
{
    public static Version? Parse(string? value)
    {
        var core = value?.Trim().TrimStart('v', 'V').Split(['-', '+'], 2)[0];
        var parts = core?.Split('.');
        if (parts is null || parts.Length is < 1 or > 4 || parts.Any(part => !int.TryParse(part, out _)))
        {
            return null;
        }
        var numbers = parts.Select(int.Parse).Concat(Enumerable.Repeat(0, 4)).Take(4).ToArray();
        return new Version(numbers[0], numbers[1], numbers[2], numbers[3]);
    }

    public static bool IsNewer(string available, string current)
    {
        var availableVersion = Parse(available);
        var currentVersion = Parse(current);
        return availableVersion is not null && currentVersion is not null && availableVersion > currentVersion;
    }

    public static ReleaseAsset? SelectWindowsAsset(GitHubRelease release, string architecture) =>
        release.Assets.FirstOrDefault(asset =>
            asset.Name.EndsWith($"-windows-{architecture}.zip", StringComparison.OrdinalIgnoreCase));
}
