using System.IO;
using System.Text.Json;

namespace DataMover.Core.Services;

/// Profil de transfer salvat - port 1:1 al TransferProfile.swift (Mac).
public sealed class TransferProfile
{
    public string Name { get; set; } = "";
    public List<string> SourcePaths { get; set; } = new();
    public List<string> DestinationPaths { get; set; } = new();
    public VerificationModel VerificationModel { get; set; } = VerificationModel.Md5;
    public string ExclusionsText { get; set; } = "";
    public int ChunkSizeMB { get; set; } = IOSettings.DefaultChunkSizeMB;
    public int RamLimitMB { get; set; } = 1024;
}

public sealed class TransferProfileStore
{
    private static readonly Lazy<TransferProfileStore> _shared = new(() => new TransferProfileStore());
    public static TransferProfileStore Shared => _shared.Value;

    private readonly string _filePath;
    public List<TransferProfile> Profiles { get; private set; } = new();

    private TransferProfileStore()
    {
        var baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DataMover");
        Directory.CreateDirectory(baseDir);
        _filePath = Path.Combine(baseDir, "transfer_profiles.json");
        Load();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var json = File.ReadAllText(_filePath);
            Profiles = JsonSerializer.Deserialize<List<TransferProfile>>(json) ?? new();
        }
        catch { Profiles = new(); }
    }

    private void Save()
    {
        try { File.WriteAllText(_filePath, JsonSerializer.Serialize(Profiles)); }
        catch { /* best-effort */ }
    }

    public void Upsert(TransferProfile profile)
    {
        var idx = Profiles.FindIndex(p => p.Name == profile.Name);
        if (idx >= 0) Profiles[idx] = profile; else Profiles.Add(profile);
        Save();
    }

    public void Delete(TransferProfile profile)
    {
        Profiles.RemoveAll(p => p.Name == profile.Name);
        Save();
    }
}
