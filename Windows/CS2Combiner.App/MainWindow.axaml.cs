using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using CS2Combiner.Core;

namespace CS2Combiner.App;

public sealed partial class MainWindow : Window
{
    private static readonly FilePickerFileType TextureFiles = new("Texture images")
    {
        Patterns = ["*.png", "*.tif", "*.tiff", "*.bmp", "*.jpg", "*.jpeg"]
    };

    private MainWindowViewModel ViewModel => (MainWindowViewModel)DataContext!;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }

    private async void AddMainMaps_Click(object? sender, RoutedEventArgs e) =>
        ImportSelected(await PickFiles(true));

    private async void AddLod2Maps_Click(object? sender, RoutedEventArgs e) =>
        ImportSelected(await PickFiles(true));

    private async void AddFolder_Click(object? sender, RoutedEventArgs e)
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new()
        {
            Title = "Scan a folder for exported texture maps",
            AllowMultiple = false
        });
        ImportSelected(folders.Select(item => item.Path.LocalPath));
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

    private static void DropArea_DragOver(object? sender, DragEventArgs e)
    {
        e.DragEffects = e.DataTransfer.Contains(DataFormat.File)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private void DropArea_Drop(object? sender, DragEventArgs e) =>
        ImportSelected(e.DataTransfer.TryGetFiles()?.Select(item => item.Path.LocalPath) ?? []);

    private static void MainSlot_DragOver(object? sender, DragEventArgs e) =>
        DropArea_DragOver(sender, e);

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
        DropArea_DragOver(sender, e);

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

    private void ImportSelected(IEnumerable<string> paths)
    {
        TryAction(() => ViewModel.ImportPaths(paths));
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
