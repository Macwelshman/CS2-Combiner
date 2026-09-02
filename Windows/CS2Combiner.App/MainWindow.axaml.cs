using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using CS2Combiner.Core;
using System.Diagnostics;

namespace CS2Combiner.App;

public sealed partial class MainWindow : Window
{
    private static readonly FilePickerFileType TextureFiles = new("Texture images")
    {
        Patterns = ["*.png", "*.tif", "*.tiff", "*.bmp", "*.jpg", "*.jpeg"]
    };

    private MainWindowViewModel ViewModel => (MainWindowViewModel)DataContext!;
    private readonly AppUpdateManager _updateManager = new();
    private GitHubRelease? _availableRelease;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }

    private async void MainWindow_Opened(object? sender, EventArgs e) =>
        await CheckForUpdates(silent: true);

    private async void CheckForUpdates_Click(object? sender, RoutedEventArgs e) =>
        await CheckForUpdates(silent: false);

    private async Task CheckForUpdates(bool silent)
    {
        try
        {
            _availableRelease = await _updateManager.CheckAsync();
            if (_availableRelease is null)
            {
                UpdateBanner.IsVisible = false;
                if (!silent)
                {
                    await new ConfirmationWindow("CS2 Combiner Updates", "CS2 Combiner is up to date.", false)
                        .ShowDialog<bool>(this);
                }
                return;
            }
            UpdateTitle.Text = $"CS2 Combiner {_availableRelease.TagName.TrimStart('v', 'V')} is available";
            UpdateMessage.Text = "Install it now, or review the release details first.";
            UpdateBanner.IsVisible = true;
        }
        catch (Exception error)
        {
            if (!silent)
            {
                await new ConfirmationWindow("CS2 Combiner Updates", error.Message, false)
                    .ShowDialog<bool>(this);
            }
        }
    }

    private async void UpdateNow_Click(object? sender, RoutedEventArgs e)
    {
        if (_availableRelease is null) return;
        UpdateNowButton.IsEnabled = false;
        UpdateNowButton.Content = "Updating…";
        UpdateMessage.Text = "Downloading and verifying the update…";
        try
        {
            await _updateManager.DownloadAndLaunchInstallerAsync(_availableRelease);
            if (Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop)
            {
                desktop.Shutdown();
            }
        }
        catch (Exception error)
        {
            UpdateNowButton.IsEnabled = true;
            UpdateNowButton.Content = "Update Now";
            UpdateMessage.Text = "The update could not be installed.";
            await new ConfirmationWindow("CS2 Combiner Updates", error.Message, false)
                .ShowDialog<bool>(this);
        }
    }

    private void LaterUpdate_Click(object? sender, RoutedEventArgs e) => UpdateBanner.IsVisible = false;

    private void ViewRelease_Click(object? sender, RoutedEventArgs e)
    {
        if (_availableRelease is not null)
        {
            Process.Start(new ProcessStartInfo(_availableRelease.HtmlUrl) { UseShellExecute = true });
        }
    }

    private async void AddMainMaps_Click(object? sender, RoutedEventArgs e) =>
        await ImportSelected(await PickFiles(true));

    private async void AddLod2Maps_Click(object? sender, RoutedEventArgs e) =>
        await ImportSelected(await PickFiles(true));

    private async void AddFolder_Click(object? sender, RoutedEventArgs e)
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new()
        {
            Title = "Scan a folder for exported texture maps",
            AllowMultiple = false
        });
        await ImportSelected(folders.Select(item => item.Path.LocalPath));
    }

    private async void AssignMainSlot_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Control { DataContext: MainSlotViewModel slot })
        {
            return;
        }
        var paths = await PickFiles(false);
        if (paths.Count == 0)
        {
            return;
        }
        TryAction(() => ViewModel.AssignMain(slot.Slot, paths[0]));
    }

    private void RemoveMainSlot_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Control { DataContext: MainSlotViewModel slot })
        {
            ViewModel.RemoveMain(slot.Slot);
        }
    }

    private async void AssignLod2Slot_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Control { DataContext: Lod2SlotViewModel slot })
        {
            return;
        }

        var set = ViewModel.Lod2Sets.FirstOrDefault(candidate => candidate.Slots.Contains(slot));
        if (set is null)
        {
            return;
        }

        var paths = await PickFiles(false);
        if (paths.Count > 0)
        {
            TryAction(() => ViewModel.AssignLod2(set.Name, slot.Slot, paths[0]));
        }
    }

    private void ClearMain_Click(object? sender, RoutedEventArgs e) => ViewModel.ClearMain();
    private void ClearLod2_Click(object? sender, RoutedEventArgs e) => ViewModel.ClearLod2();
    private void ClearAll_Click(object? sender, RoutedEventArgs e) => ViewModel.ClearAll();
    private void UseDefaultOutput_Click(object? sender, RoutedEventArgs e) => ViewModel.SetMainOutput(null);

    private async void ChooseMainOutput_Click(object? sender, RoutedEventArgs e)
    {
        var path = await PickFolder("Choose main texture export location");
        if (path is not null)
        {
            ViewModel.SetMainOutput(path);
        }
    }

    private async void ChooseLod2Output_Click(object? sender, RoutedEventArgs e)
    {
        var path = await PickFolder("Choose LOD2 texture export location");
        if (path is not null)
        {
            ViewModel.SetLod2Output(path);
        }
    }

    private async void ExportMain_Click(object? sender, RoutedEventArgs e)
    {
        if (!await ConfirmOverwrite(ViewModel.PlannedMainOutputs()))
        {
            return;
        }
        await RunExport(ViewModel.ExportMainAsync);
    }

    private async void ExportLod2_Click(object? sender, RoutedEventArgs e)
    {
        if (!await ConfirmOverwrite(ViewModel.PlannedLod2Outputs()))
        {
            return;
        }
        await RunExport(ViewModel.ExportLod2Async);
    }

    private async void ExportAll_Click(object? sender, RoutedEventArgs e)
    {
        var outputs = ViewModel.PlannedMainOutputs()
            .Concat(ViewModel.PlannedLod2Outputs())
            .ToArray();
        if (!await ConfirmOverwrite(outputs))
        {
            return;
        }
        await RunExport(async () =>
        {
            await ViewModel.ExportMainAsync();
            await ViewModel.ExportLod2Async();
        });
    }

    private static bool SetDragEffects(DragEventArgs e)
    {
        var containsFiles = e.DataTransfer.Contains(DataFormat.File);
        e.DragEffects = containsFiles
            ? DragDropEffects.Copy
            : DragDropEffects.None;
        return containsFiles;
    }

    private void DropArea_DragOver(object? sender, DragEventArgs e) =>
        DropAreaHighlight.IsVisible = SetDragEffects(e);

    private void DropArea_DragLeave(object? sender, RoutedEventArgs e) =>
        DropAreaHighlight.IsVisible = false;

    private async void DropArea_Drop(object? sender, DragEventArgs e)
    {
        DropAreaHighlight.IsVisible = false;
        await ImportSelected(e.DataTransfer.TryGetFiles()?.Select(item => item.Path.LocalPath) ?? []);
    }

    private static void MainSlot_DragOver(object? sender, DragEventArgs e) =>
        SetDragEffects(e);

    private void MainSlot_Drop(object? sender, DragEventArgs e)
    {
        if (sender is not Control { DataContext: MainSlotViewModel slot })
        {
            return;
        }
        var path = e.DataTransfer.TryGetFiles()?.FirstOrDefault()?.Path.LocalPath;
        if (path is not null)
        {
            TryAction(() => ViewModel.AssignMain(slot.Slot, path));
        }
    }

    private static void Lod2Slot_DragOver(object? sender, DragEventArgs e) =>
        SetDragEffects(e);

    private void Lod2Slot_Drop(object? sender, DragEventArgs e)
    {
        if (sender is not Control { DataContext: Lod2SlotViewModel slot })
        {
            return;
        }

        var set = ViewModel.Lod2Sets.FirstOrDefault(candidate => candidate.Slots.Contains(slot));
        var path = e.DataTransfer.TryGetFiles()?.FirstOrDefault()?.Path.LocalPath;
        if (set is not null && path is not null)
        {
            TryAction(() => ViewModel.AssignLod2(set.Name, slot.Slot, path));
        }
    }

    private async Task<IReadOnlyList<string>> PickFiles(bool allowMultiple)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new()
        {
            Title = "Add exported texture maps",
            AllowMultiple = allowMultiple,
            FileTypeFilter = [TextureFiles]
        });
        return files.Select(item => item.Path.LocalPath).ToArray();
    }

    private async Task<string?> PickFolder(string title)
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new()
        {
            Title = title,
            AllowMultiple = false
        });
        return folders.FirstOrDefault()?.Path.LocalPath;
    }

    private async Task ImportSelected(IEnumerable<string> paths)
    {
        var selectedPaths = paths.ToArray();
        var containsFolder = selectedPaths.Any(Directory.Exists);
        var ignoredExperimentalDecalMaps = false;
        if (ViewModel.SelectedAssetType == AssetType.Building && containsFolder)
        {
            var candidates = MapDetector.ImagePaths(selectedPaths);
            var surfaceIndicators = MapDetector.SurfaceOnlyMapPaths(candidates);
            if (surfaceIndicators.Count > 0)
            {
                var switchToSurface = await new ConfirmationWindow(
                    "Surface textures detected",
                    "This folder contains Surface-only maps:\n\n" +
                    string.Join('\n', surfaceIndicators.Select(Path.GetFileName)) +
                    "\n\nSwitch to the Surface profile before importing them?",
                    showsCancel: true,
                    confirmText: "Switch to Surface",
                    cancelText: "Keep Building")
                    .ShowDialog<bool>(this);
                if (switchToSurface)
                {
                    ViewModel.SelectedAssetType = AssetType.Surface;
                }
            }
        }

        if (ViewModel.SelectedAssetType == AssetType.Decal &&
            !ViewModel.DecalExperimentalMapsEnabled)
        {
            var candidates = MapDetector.ImagePaths(selectedPaths);
            var experimental = candidates.Where(path =>
                MapDetector.DetectSlot(path) is { } slot &&
                AssetProfiles.DecalExperimentalSlots.Contains(slot)).ToArray();
            if (experimental.Length > 0)
            {
                if (containsFolder)
                {
                    var showAndImport = await new ConfirmationWindow(
                        "Experimental decal maps detected",
                        "The CS2 guide states that these decal textures are untested and may not work as expected:\n\n" +
                        string.Join('\n', experimental.Select(Path.GetFileName)) +
                        "\n\nShow the experimental section and import them?",
                        showsCancel: true,
                        confirmText: "Show and Import",
                        cancelText: "Ignore Experimental Maps")
                        .ShowDialog<bool>(this);
                    if (showAndImport)
                    {
                        ViewModel.EnableExperimentalDecalMaps();
                    }
                    else
                    {
                        ignoredExperimentalDecalMaps = true;
                    }
                }
                else
                {
                    ViewModel.EnableExperimentalDecalMaps();
                }
            }
        }

        TryAction(() => ViewModel.ImportPaths(selectedPaths));
        if (ignoredExperimentalDecalMaps)
        {
            ViewModel.ReportExperimentalDecalMapsIgnored();
        }
    }

    private async Task<bool> ConfirmOverwrite(IEnumerable<string> planned)
    {
        var existing = planned.Where(File.Exists).Select(Path.GetFileName).ToArray();
        if (existing.Length == 0)
        {
            return true;
        }

        var dialog = new ConfirmationWindow(
            "Replace existing exports",
            "The following files already exist:\n\n" +
            string.Join('\n', existing) +
            "\n\nIf one is an assigned source map, replacing it will update that source file.");
        return await dialog.ShowDialog<bool>(this);
    }

    private async Task RunExport(Func<Task> operation)
    {
        try
        {
            await operation();
        }
        catch (Exception error)
        {
            await new ConfirmationWindow("CS2 Combiner", error.Message, false)
                .ShowDialog<bool>(this);
        }
    }

    private async void TryAction(Action action)
    {
        try
        {
            action();
        }
        catch (Exception error)
        {
            await new ConfirmationWindow("CS2 Combiner", error.Message, false)
                .ShowDialog<bool>(this);
        }
    }
}
