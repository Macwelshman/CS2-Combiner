using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using CS2Combiner.Core;

namespace CS2Combiner.App;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void Raise([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new(propertyName));

    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        Raise(propertyName);
        return true;
    }
}

public sealed class MainSlotViewModel(MainWindowViewModel owner, MapSlot slot) : ObservableObject
{
    public MapSlot Slot { get; } = slot;
    public string Title => Slot.Title();
    public string ChannelDescription => Slot.ChannelDescription();
    public bool IsRequired => Slot == MapSlot.BaseColor;
    public bool IsAssigned => owner.Inputs.ContainsKey(Slot);
    public string StatusGlyph => IsAssigned ? "✓" : string.Empty;
    public bool HasSpecialToggle => Slot is MapSlot.Opacity or MapSlot.Normal;
    public string SpecialToggleLabel =>
        Slot == MapSlot.Opacity ? "Override BaseColor alpha" : AppSpelling.Normalize();
    public bool SpecialToggle
    {
        get => Slot == MapSlot.Opacity
            ? owner.OpacityMapOverridesBaseColorAlpha
            : owner.NormalizeNormalOnExport;
        set
        {
            if (Slot == MapSlot.Opacity)
            {
                owner.OpacityMapOverridesBaseColorAlpha = value;
            }
            else if (Slot == MapSlot.Normal)
            {
                owner.NormalizeNormalOnExport = value;
            }
            Raise();
        }
    }

    public string ActionText => IsAssigned ? "Replace…" : "Assign…";
    public string Description => owner.Inputs.TryGetValue(Slot, out var input)
        ? $"{Path.GetFileName(input.Path)} · {input.Size}"
        : ChannelDescription;

    public void Refresh()
    {
        Raise(nameof(IsAssigned));
        Raise(nameof(StatusGlyph));
        Raise(nameof(ActionText));
        Raise(nameof(Description));
        Raise(nameof(SpecialToggle));
    }
}

public sealed class MainSlotGroupViewModel(
    MainWindowViewModel owner,
    string title,
    IEnumerable<MainSlotViewModel> slots,
    bool showsOpacitySource = false) : ObservableObject
{
    public string Title { get; } = title;
    public ObservableCollection<MainSlotViewModel> Slots { get; } = new(slots);
    public bool ShowsOpacitySource { get; } = showsOpacitySource;
    public string OpacitySourceDescription => owner.OpacitySourceDescription;

    public void Refresh() => Raise(nameof(OpacitySourceDescription));
}

public sealed class Lod2SlotViewModel(Lod2SetViewModel owner, Lod2Slot slot) : ObservableObject
{
    public Lod2Slot Slot { get; } = slot;
    public string Title => Slot.Title();
    public bool IsAssigned => owner.Inputs.ContainsKey(Slot);
    public string StatusGlyph => IsAssigned ? "✓" : string.Empty;
    public string ActionText => IsAssigned ? "Replace…" : "Assign…";
    public string Description => owner.Inputs.TryGetValue(Slot, out var path)
        ? $"{Path.GetFileName(path)} · {ImageCodec.Dimensions(path)}"
        : Slot == Lod2Slot.Normal
            ? "Not added — flat normal exported"
            : "Not added — not exported";

    public void Refresh()
    {
        Raise(nameof(IsAssigned));
        Raise(nameof(StatusGlyph));
        Raise(nameof(ActionText));
        Raise(nameof(Description));
    }
}

public sealed class Lod2SetViewModel(string name, Dictionary<Lod2Slot, string> inputs) : ObservableObject
{
    public string Name { get; } = name;
    public Dictionary<Lod2Slot, string> Inputs { get; } = inputs;
    public ObservableCollection<Lod2SlotViewModel> Slots { get; } = [];

    public void Initialize()
    {
        if (Slots.Count == 0)
        {
            foreach (var slot in Lod2SlotInfo.All)
            {
                Slots.Add(new(this, slot));
            }
        }
    }

    public void Refresh() => Slots.ToList().ForEach(slot => slot.Refresh());
}

public sealed class MainWindowViewModel : ObservableObject
{
    private string _status = "Drop exported maps or a folder to begin.";
    private string _lod2Status = "Drop LOD2 maps or a folder to begin.";
    private bool _isWorking;
    private bool _opacityMapOverridesBaseColorAlpha;
    private bool _normalizeNormalOnExport;
    private bool _baseColorHasAlpha;
    private string? _customOutputRoot;
    private string? _customLod2OutputRoot;
    private bool _useMainOutputForLod2 = true;
    private AssetType _selectedAssetType = AssetType.Building;
    private bool _decalExperimentalMapsEnabled;
    private bool _isDecalExperimentalExpanded;

    public MainWindowViewModel()
    {
        foreach (var slot in MapSlotInfo.All)
        {
            MainSlots.Add(new(this, slot));
        }

        RebuildMainGroups();
        DecalExperimentalSlots = MainSlots
            .Where(row => AssetProfiles.DecalExperimentalSlots.Contains(row.Slot))
            .ToArray();
    }

    internal Dictionary<MapSlot, InputMap> Inputs { get; } = [];
    public ObservableCollection<MainSlotViewModel> MainSlots { get; } = [];
    public ObservableCollection<MainSlotGroupViewModel> MainGroups { get; } = [];
    public ObservableCollection<Lod2SetViewModel> Lod2Sets { get; } = [];
    public IReadOnlyList<MainSlotViewModel> DecalExperimentalSlots { get; }
    public IReadOnlyList<AssetType> AssetTypes { get; } = AssetProfiles.AllTypes;

    public AssetType SelectedAssetType
    {
        get => _selectedAssetType;
        set
        {
            if (!Set(ref _selectedAssetType, value))
            {
                return;
            }

            RebuildMainGroups();
            Status = ActiveProfile.CanExport
                ? $"{value} profile selected."
                : $"{value} profile selected. Export support is coming next.";
            RefreshDerived();
        }
    }

    public bool IsBuildingSelected
    {
        get => SelectedAssetType == AssetType.Building;
        set { if (value) SelectedAssetType = AssetType.Building; }
    }

    public bool IsSurfaceSelected
    {
        get => SelectedAssetType == AssetType.Surface;
        set { if (value) SelectedAssetType = AssetType.Surface; }
    }

    public bool IsDecalSelected
    {
        get => SelectedAssetType == AssetType.Decal;
        set { if (value) SelectedAssetType = AssetType.Decal; }
    }

    public AssetProfile ActiveProfile => AssetProfiles.For(SelectedAssetType);
    public string ProfileDescription => ActiveProfile.Description;
    public string ProfileAvailability => ActiveProfile.CanExport
        ? string.Empty
        : "Profile prepared — export packing will be added next.";
    public bool ShowsProfileAvailability => !ActiveProfile.CanExport;
    public string MainTextureHeading => ActiveProfile.TextureHeading;
    public string MainTextureSizeDescription => ActiveProfile.SizeDescription;
    public string MainExportButtonTitle => SelectedAssetType switch
    {
        AssetType.Surface => "Export Surface",
        AssetType.Decal => "Export Decal",
        _ => "Export Main"
    };
    public bool SupportsLod2 => ActiveProfile.SupportsLod2;
    public bool IsDecal => SelectedAssetType == AssetType.Decal;
    public bool IsDecalExperimentalExpanded
    {
        get => _isDecalExperimentalExpanded;
        set
        {
            if (Set(ref _isDecalExperimentalExpanded, value) && value)
            {
                _decalExperimentalMapsEnabled = true;
                Raise(nameof(DecalExperimentalMapsEnabled));
            }
        }
    }
    public bool DecalExperimentalMapsEnabled => _decalExperimentalMapsEnabled;
    public int DecalExperimentalOutputCount
    {
        get
        {
            if (!IsDecal || !DecalExperimentalMapsEnabled) return 0;
            var count = Inputs.Keys.Any(AssetProfiles.DecalExperimentalSlots.Take(4).Contains) ? 1 : 0;
            if (Inputs.ContainsKey(MapSlot.Emissive)) count++;
            return count;
        }
    }
    public string DecalExportSummary => DecalExperimentalOutputCount == 0
        ? "3 required textures"
        : $"3 required + {DecalExperimentalOutputCount} experimental texture{(DecalExperimentalOutputCount == 1 ? string.Empty : "s")}";

    public void EnableExperimentalDecalMaps()
    {
        if (!IsDecal) return;
        _decalExperimentalMapsEnabled = true;
        IsDecalExperimentalExpanded = true;
        Raise(nameof(DecalExperimentalMapsEnabled));
    }

    public void ReportExperimentalDecalMapsIgnored() =>
        Status += " Experimental decal maps were ignored.";

    public string Status
    {
        get => _status;
        private set => Set(ref _status, value);
    }

    public string Lod2Status
    {
        get => _lod2Status;
        private set => Set(ref _lod2Status, value);
    }

    public bool IsWorking
    {
        get => _isWorking;
        private set
        {
            if (Set(ref _isWorking, value))
            {
                RefreshDerived();
            }
        }
    }

    public bool OpacityMapOverridesBaseColorAlpha
    {
        get => _opacityMapOverridesBaseColorAlpha;
        set
        {
            var resolved = value && Inputs.ContainsKey(MapSlot.Opacity);
            if (Set(ref _opacityMapOverridesBaseColorAlpha, resolved))
            {
                Raise(nameof(OpacitySourceDescription));
            }
        }
    }

    public bool NormalizeNormalOnExport
    {
        get => _normalizeNormalOnExport;
        set => Set(ref _normalizeNormalOnExport, value && Inputs.ContainsKey(MapSlot.Normal));
    }

    public bool UseMainOutputForLod2
    {
        get => _useMainOutputForLod2;
        set
        {
            if (Set(ref _useMainOutputForLod2, value))
            {
                RefreshDerived();
            }
        }
    }

    public bool HasBaseColor => Inputs.ContainsKey(MapSlot.BaseColor);
    public bool HasMainInputs => Inputs.Count > 0;
    public bool HasLod2Sets => Lod2Sets.Count > 0;
    public bool HasNoLod2Sets => !HasLod2Sets;
    public bool CanExportMain => ActiveProfile.CanExport && HasBaseColor && !IsWorking;
    public bool CanExportLod2 =>
        SupportsLod2 && HasLod2Sets && !IsWorking &&
        (UseMainOutputForLod2 ? OutputDirectory is not null : _customLod2OutputRoot is not null);
    public bool ShowsExportAll => SupportsLod2 && ExportAvailability.ShowsExportAll(HasBaseColor, HasLod2Sets);
    public bool UsesCustomOutput => _customOutputRoot is not null;
    public string OutputHeading => _customOutputRoot is null
        ? "Default CS2 output: CS2 Export"
        : "Custom CS2 output";
    public string OutputPath => OutputDirectory ?? "Set by the BaseColor source location";
    public string OpacitySourceDescription => OpacitySource.Resolve(
        HasBaseColor,
        _baseColorHasAlpha,
        Inputs.ContainsKey(MapSlot.Opacity),
        OpacityMapOverridesBaseColorAlpha).Description;

    public string? OutputDirectory =>
        Inputs.TryGetValue(MapSlot.BaseColor, out var baseColor)
            ? AssetNaming.OutputDirectory(baseColor.Path, _customOutputRoot)
            : null;

    public void ImportPaths(IEnumerable<string> roots)
    {
        var importedMain = 0;
        var importedLod2 = 0;
        var rejected = new List<string>();

        foreach (var root in roots)
        {
            var isDirectory = Directory.Exists(root);
            foreach (var path in MapDetector.ImagePaths([root]))
            {
                if (SupportsLod2 && Lod2Detector.IsCandidate(path))
                {
                    if (TryImportLod2(path, rejected))
                    {
                        importedLod2++;
                    }
                    continue;
                }

                var slot = MapDetector.DetectSlot(path);
                if (!slot.HasValue || slot == MapSlot.Normal && MapDetector.IsDirectXNormal(path))
                {
                    continue;
                }
                if (!ActiveProfile.SupportedSlots.Contains(slot.Value))
                {
                    continue;
                }
                if (SelectedAssetType == AssetType.Decal &&
                    AssetProfiles.DecalExperimentalSlots.Contains(slot.Value) &&
                    !DecalExperimentalMapsEnabled)
                {
                    continue;
                }
                if (isDirectory && Inputs.ContainsKey(slot.Value))
                {
                    continue;
                }

                try
                {
                    AssignMain(slot.Value, path);
                    importedMain++;
                }
                catch (CombinerException)
                {
                    rejected.Add(Path.GetFileName(path));
                }
            }
        }

        Status = $"Imported {importedMain} main map{(importedMain == 1 ? string.Empty : "s")}.";
        Lod2Status = $"Imported {importedLod2} LOD2 map{(importedLod2 == 1 ? string.Empty : "s")}.";
        if (rejected.Count > 0)
        {
            Status += $" Skipped incompatible files: {string.Join(", ", rejected)}. {ActiveProfile.SizeDescription}";
        }
        RefreshAll();
    }

    public void AssignMain(MapSlot slot, string path)
    {
        if (slot == MapSlot.Normal && MapDetector.IsDirectXNormal(path))
        {
            throw new CombinerException("DirectX normals are not accepted. Choose an OpenGL normal map.");
        }

        var size = ImageCodec.Dimensions(path);
        TexturePacking.ValidateMainInputSize(size, slot.Title(), SelectedAssetType);
        if (slot == MapSlot.BaseColor)
        {
            _baseColorHasAlpha = ImageCodec.HasAlphaChannel(path);
        }

        var wasOccupied = Inputs.ContainsKey(slot);
        Inputs[slot] = new(slot, path, size);
        Status = $"{(wasOccupied ? "Replaced" : "Assigned")} {slot.Title()}.";
        RefreshAll();
    }

    public void RemoveMain(MapSlot slot)
    {
        Inputs.Remove(slot);
        if (slot == MapSlot.BaseColor)
        {
            _baseColorHasAlpha = false;
        }
        else if (slot == MapSlot.Opacity)
        {
            _opacityMapOverridesBaseColorAlpha = false;
        }
        else if (slot == MapSlot.Normal)
        {
            _normalizeNormalOnExport = false;
        }
        Status = $"Removed {slot.Title()}.";
        RefreshAll();
    }

    public void ClearMain()
    {
        Inputs.Clear();
        _baseColorHasAlpha = false;
        _opacityMapOverridesBaseColorAlpha = false;
        _normalizeNormalOnExport = false;
        _customOutputRoot = null;
        Status = "Cleared all assigned main maps.";
        RefreshAll();
    }

    public void ClearLod2()
    {
        Lod2Sets.Clear();
        Lod2Status = "Cleared LOD2 maps.";
        RefreshDerived();
    }

    public void ClearAll()
    {
        ClearMain();
        ClearLod2();
        Status = "Cleared all assigned maps.";
    }

    public void SetMainOutput(string? path)
    {
        _customOutputRoot = path;
        Status = path is null
            ? "Output reset to CS2 Export in the BaseColor source folder."
            : $"Custom output selected: {path}.";
        RefreshDerived();
    }

    public void SetLod2Output(string path)
    {
        _customLod2OutputRoot = path;
        UseMainOutputForLod2 = false;
        Lod2Status = $"LOD2 output location selected: {path}.";
    }

    public void AssignLod2(string setName, Lod2Slot slot, string path)
    {
        if (ImageCodec.Dimensions(path) != new PixelSize(512, 512))
        {
            throw new CombinerException("LOD2 maps must already be 512 × 512.");
        }

        var set = Lod2Sets.FirstOrDefault(item => item.Name == setName)
            ?? throw new CombinerException($"LOD2 set {setName} could not be found.");
        set.Inputs[slot] = path;
        set.Refresh();
        Lod2Status = $"Assigned {slot.Title()} for {setName}.";
        RefreshDerived();
    }

    public IReadOnlyList<string> PlannedMainOutputs() =>
        BuildMainPlan().OutputPaths;

    public IReadOnlyList<string> PlannedLod2Outputs() =>
        BuildLod2Plans().SelectMany(plan => plan.OutputPaths).ToArray();

    public async Task ExportMainAsync()
    {
        var plan = BuildMainPlan();
        IsWorking = true;
        Status = $"Packing {plan.OutputPaths.Count} {plan.TargetSize.Width} × {plan.TargetSize.Height} PNGs…";
        try
        {
            var outputs = await Task.Run(() => TexturePacking.Export(plan));
            Status = $"Exported {outputs.Count} {plan.Profile.ToString().ToLowerInvariant()} textures to {plan.OutputDirectory}.";
        }
        catch (Exception error)
        {
            Status = error.Message;
            throw;
        }
        finally
        {
            IsWorking = false;
        }
    }

    public async Task ExportLod2Async()
    {
        var plans = BuildLod2Plans();
        IsWorking = true;
        Lod2Status = $"Exporting {plans.Sum(plan => plan.OutputPaths.Count)} combined 512 × 512 LOD2 textures…";
        try
        {
            var outputs = await Task.Run(() =>
                plans.SelectMany(plan => Lod2TexturePacking.Export(plan)).ToArray());
            Lod2Status = $"Exported {outputs.Length} LOD2 texture{(outputs.Length == 1 ? string.Empty : "s")}.";
        }
        catch (Exception error)
        {
            Lod2Status = error.Message;
            throw;
        }
        finally
        {
            IsWorking = false;
        }
    }

    private bool TryImportLod2(string path, ICollection<string> rejected)
    {
        var slot = Lod2Detector.DetectSlot(path);
        if (!slot.HasValue)
        {
            return false;
        }
        if (ImageCodec.Dimensions(path) != new PixelSize(512, 512))
        {
            rejected.Add(Path.GetFileName(path));
            return false;
        }

        var name = Lod2Detector.SetName(path, slot.Value);
        var set = Lod2Sets.FirstOrDefault(item => item.Name == name);
        if (set is null)
        {
            set = new(name, []);
            set.Initialize();
            Lod2Sets.Add(set);
        }
        set.Inputs[slot.Value] = path;
        set.Refresh();
        return true;
    }

    private TextureExportPlan BuildMainPlan()
    {
        if (!ActiveProfile.CanExport)
        {
            throw new CombinerException($"{SelectedAssetType} export is not available yet. Choose Building to export textures.");
        }
        if (!Inputs.TryGetValue(MapSlot.BaseColor, out var baseColor) || OutputDirectory is null)
        {
            throw new CombinerException("Add a BaseColor map before exporting.");
        }

        var size = TexturePacking.ValidateBaseColor(baseColor, SelectedAssetType);
        TexturePacking.ValidateInputSizes(Inputs, size, SelectedAssetType);
        var exportInputs = SelectedAssetType == AssetType.Decal && !DecalExperimentalMapsEnabled
            ? Inputs.Where(pair => !AssetProfiles.DecalExperimentalSlots.Contains(pair.Key))
                .ToDictionary(pair => pair.Key, pair => pair.Value)
            : new Dictionary<MapSlot, InputMap>(Inputs);
        return new(
            exportInputs,
            size,
            OutputDirectory,
            AssetNaming.InferredAssetName(baseColor.Path),
            OpacityMapOverridesBaseColorAlpha,
            NormalizeNormalOnExport,
            SelectedAssetType);
    }

    private IReadOnlyList<Lod2TextureExportPlan> BuildLod2Plans()
    {
        var output = UseMainOutputForLod2 ? OutputDirectory : _customLod2OutputRoot;
        if (output is null)
        {
            throw new CombinerException("Choose an LOD2 output location.");
        }

        return Lod2Sets
            .Select(set => new Lod2TextureExportPlan(
                new Dictionary<Lod2Slot, string>(set.Inputs),
                set.Name,
                output))
            .ToArray();
    }

    private void RefreshAll()
    {
        MainSlots.ToList().ForEach(slot => slot.Refresh());
        MainGroups.ToList().ForEach(group => group.Refresh());
        RefreshDerived();
    }

    private void RebuildMainGroups()
    {
        var rows = MainSlots.ToDictionary(row => row.Slot);
        MainGroups.Clear();
        foreach (var group in ActiveProfile.Groups)
        {
            MainGroups.Add(new(
                this,
                group.Title,
                group.Slots.Select(slot => rows[slot]),
                group.ShowsOpacitySource));
        }
    }

    private void RefreshDerived()
    {
        Raise(nameof(HasBaseColor));
        Raise(nameof(HasMainInputs));
        Raise(nameof(HasLod2Sets));
        Raise(nameof(HasNoLod2Sets));
        Raise(nameof(CanExportMain));
        Raise(nameof(CanExportLod2));
        Raise(nameof(ShowsExportAll));
        Raise(nameof(UsesCustomOutput));
        Raise(nameof(OutputHeading));
        Raise(nameof(OutputPath));
        Raise(nameof(OutputDirectory));
        Raise(nameof(OpacitySourceDescription));
        Raise(nameof(ActiveProfile));
        Raise(nameof(ProfileDescription));
        Raise(nameof(ProfileAvailability));
        Raise(nameof(ShowsProfileAvailability));
        Raise(nameof(MainTextureHeading));
        Raise(nameof(MainTextureSizeDescription));
        Raise(nameof(MainExportButtonTitle));
        Raise(nameof(SupportsLod2));
        Raise(nameof(IsDecal));
        Raise(nameof(IsBuildingSelected));
        Raise(nameof(IsSurfaceSelected));
        Raise(nameof(IsDecalSelected));
        Raise(nameof(IsDecalExperimentalExpanded));
        Raise(nameof(DecalExperimentalMapsEnabled));
        Raise(nameof(DecalExperimentalOutputCount));
        Raise(nameof(DecalExportSummary));
        Raise(nameof(IsWorking));
    }
}
