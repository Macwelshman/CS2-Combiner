using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using CS2Combiner.Core;

namespace CS2Combiner.App;

internal sealed class AppUpdateManager
{
    private const string LatestReleaseUrl = "https://api.github.com/repos/Macwelshman/CS2-Combiner/releases/latest";
    private static readonly HttpClient Client = CreateClient();

    public string CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0.3.3";

    public async Task<GitHubRelease?> CheckAsync(CancellationToken cancellationToken = default)
    {
        using var response = await Client.GetAsync(LatestReleaseUrl, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(stream, cancellationToken: cancellationToken)
            ?? throw new InvalidDataException("The update server returned an invalid response.");
        if (release.Draft || release.Prerelease || UpdateVersions.Parse(release.TagName) is null)
        {
            throw new InvalidDataException("The latest release has an invalid version.");
        }
        return UpdateVersions.IsNewer(release.TagName, CurrentVersion) ? release : null;
    }

    public async Task DownloadAndLaunchInstallerAsync(GitHubRelease release, CancellationToken cancellationToken = default)
    {
        var architecture = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.Arm64 => "arm64",
            Architecture.X64 => "x64",
            _ => throw new PlatformNotSupportedException("Updates are available only for Windows ARM64 and Windows x64.")
        };
        var asset = UpdateVersions.SelectWindowsAsset(release, architecture)
            ?? throw new InvalidDataException($"The release does not include a Windows {architecture} update.");
        if (asset.Digest is null || !asset.Digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("The update has no published SHA-256 digest and cannot be installed safely.");
        }

        var currentExecutable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The current application path could not be resolved.");
        var installDirectory = Path.GetDirectoryName(currentExecutable)!;
        VerifyWritable(installDirectory);

        var updateRoot = Path.Combine(Path.GetTempPath(), $"CS2CombinerUpdate-{Guid.NewGuid():N}");
        var archive = Path.Combine(updateRoot, asset.Name);
        var staging = Path.Combine(updateRoot, "staging");
        Directory.CreateDirectory(staging);

        using (var response = await Client.GetAsync(asset.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
        {
            response.EnsureSuccessStatusCode();
            await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var destination = File.Create(archive);
            await source.CopyToAsync(destination, cancellationToken);
        }
        await using var archiveStream = File.OpenRead(archive);
        var actualDigest = Convert.ToHexString(await SHA256.HashDataAsync(archiveStream, cancellationToken)).ToLowerInvariant();
        if (!string.Equals(asset.Digest, $"sha256:{actualDigest}", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("The downloaded update did not match its published SHA-256 digest.");
        }

        ZipFile.ExtractToDirectory(archive, staging);
        var stagedExecutable = Path.Combine(staging, "CS2Combiner.exe");
        if (!File.Exists(stagedExecutable))
        {
            throw new InvalidDataException("The downloaded update is not a valid CS2 Combiner package.");
        }
        var packagedVersion = FileVersionInfo.GetVersionInfo(stagedExecutable).ProductVersion;
        if (UpdateVersions.Parse(packagedVersion) != UpdateVersions.Parse(release.TagName))
        {
            throw new InvalidDataException("The downloaded application version does not match the release.");
        }

        var helper = Path.Combine(updateRoot, "CS2Combiner-Updater.exe");
        File.Copy(currentExecutable, helper, true);
        var start = new ProcessStartInfo(helper) { UseShellExecute = false };
        start.ArgumentList.Add("--apply-update");
        start.ArgumentList.Add(Environment.ProcessId.ToString());
        start.ArgumentList.Add(staging);
        start.ArgumentList.Add(installDirectory);
        start.ArgumentList.Add(Path.GetFileName(currentExecutable));
        _ = Process.Start(start) ?? throw new InvalidOperationException("The update installer could not be started.");
    }

    public static bool TryRunInstaller(string[] arguments)
    {
        if (arguments.Length != 5 || arguments[0] != "--apply-update")
        {
            return false;
        }
        ApplyUpdate(
            int.Parse(arguments[1]),
            arguments[2],
            arguments[3],
            arguments[4]);
        return true;
    }

    private static void ApplyUpdate(int processId, string staging, string installDirectory, string executableName)
    {
        try
        {
            try { Process.GetProcessById(processId).WaitForExit(60_000); }
            catch (ArgumentException) { }

            var root = Directory.GetParent(staging)!.FullName;
            var backup = Path.Combine(root, "backup");
            Directory.CreateDirectory(backup);
            var created = new List<string>();
            var backedUp = new List<(string Target, string Backup)>();

            try
            {
                foreach (var source in Directory.EnumerateFiles(staging, "*", SearchOption.AllDirectories))
                {
                    var relative = Path.GetRelativePath(staging, source);
                    var target = Path.Combine(installDirectory, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    if (File.Exists(target))
                    {
                        var saved = Path.Combine(backup, relative);
                        Directory.CreateDirectory(Path.GetDirectoryName(saved)!);
                        File.Copy(target, saved, true);
                        backedUp.Add((target, saved));
                    }
                    else
                    {
                        created.Add(target);
                    }
                    File.Copy(source, target, true);
                }
            }
            catch
            {
                foreach (var target in created.Where(File.Exists)) File.Delete(target);
                foreach (var item in backedUp) File.Copy(item.Backup, item.Target, true);
                throw;
            }

            Process.Start(new ProcessStartInfo(Path.Combine(installDirectory, executableName)) { UseShellExecute = true });
            Directory.Delete(staging, true);
            Directory.Delete(backup, true);
            MoveFileEx(Environment.ProcessPath, null, MoveFileFlags.DelayUntilReboot);
        }
        catch
        {
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(installDirectory, executableName)) { UseShellExecute = true });
            }
            catch { }
        }
    }

    private static void VerifyWritable(string directory)
    {
        var probe = Path.Combine(directory, $".cs2-update-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(probe, "update check");
            File.Delete(probe);
        }
        catch (Exception error)
        {
            throw new UnauthorizedAccessException(
                "CS2 Combiner cannot update this copy in place. Move it to a folder you can write to, then try again.",
                error);
        }
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("CS2-Combiner-Updater");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string? existingFileName, string? newFileName, MoveFileFlags flags);

    [Flags]
    private enum MoveFileFlags : uint
    {
        DelayUntilReboot = 0x4
    }
}
