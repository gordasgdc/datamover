namespace DataMover.Core.Domain;

/// <summary>
/// Clasificarea mediului — aceleasi reguli ca `MediaClassifier` (Mac). Nu se
/// afirma un tip mai precis decat raporteaza sistemul; fallback = dispozitiv
/// extern. Numele volumului e doar indiciu secundar.
/// </summary>
public enum DeviceKind { CFexpress, SdCard, MemoryCard, Ssd, Hdd, UsbStick, InternalVolume, Folder, ExternalDevice }
public enum MediumType { Unknown, SolidState, Rotational }
public enum Confidence { Certain, Likely, Hint, Fallback }

public sealed class MediaFacts
{
    public bool IsVolumeRoot { get; set; } = true;
    /// "USB", "NVMe", "SATA", "SD", "Thunderbolt", "Virtual", "Network"...
    public string? Bus { get; set; }
    public bool? IsInternal { get; set; }
    public bool? IsRemovableMedia { get; set; }
    public bool IsNetwork { get; set; }
    public MediumType Medium { get; set; } = MediumType.Unknown;
    public long? TotalBytes { get; set; }
    public string? Model { get; set; }
    public bool CameraCardStructure { get; set; }
    public string VolumeName { get; set; } = "";
}

public sealed record MediaClass(DeviceKind Kind, Confidence Confidence, string Reason, string? Connection);

public static class MediaClassifier
{
    public const long CardMaxBytes = 4_000_000_000_000;

    public static string? Connection(MediaFacts f) => f.IsNetwork ? "rețea" : f.Bus switch
    {
        "USB" => "USB", "NVMe" or "PCIe" or "Thunderbolt" => f.IsInternal == true ? "intern" : "Thunderbolt / PCIe",
        "SD" => "cititor SD", "SATA" => f.IsInternal == true ? "intern" : "SATA", "Virtual" => "virtual",
        _ => f.IsInternal == true ? "intern" : null,
    };

    private static bool Has(string? s, string w) => s?.Contains(w, StringComparison.OrdinalIgnoreCase) == true;

    public static MediaClass Classify(MediaFacts f)
    {
        var conn = Connection(f);
        MediaClass R(DeviceKind k, Confidence c, string why) => new(k, c, why, conn);
        if (!f.IsVolumeRoot) return R(DeviceKind.Folder, Confidence.Certain, "cale aleasă, nu rădăcina unui volum");
        if (f.IsNetwork) return R(DeviceKind.ExternalDevice, Confidence.Certain, "volum de rețea");
        if (f.Bus == "Virtual") return R(DeviceKind.ExternalDevice, Confidence.Certain, "volum virtual");
        if (f.IsInternal == true) return R(DeviceKind.InternalVolume, Confidence.Certain, "stocare internă");
        if (f.Bus == "SD") return R(DeviceKind.SdCard, Confidence.Certain, "cititor SD");
        bool small = (f.TotalBytes ?? long.MaxValue) <= CardMaxBytes;
        if (f.CameraCardStructure && small && f.IsRemovableMedia == true)
        {
            bool cf = Has(f.Model, "CFexpress"), sd = Has(f.Model, "SD");
            if (cf && !sd) return R(DeviceKind.CFexpress, Confidence.Likely, "structură de cameră; cititorul raportează CFexpress");
            if (sd && !cf) return R(DeviceKind.SdCard, Confidence.Likely, "structură de cameră; cititorul raportează SD");
            return R(DeviceKind.MemoryCard, Confidence.Likely, "structură de cameră pe mediu amovibil");
        }
        if (f.Bus == "USB" && f.IsRemovableMedia == true && small && f.Medium != MediumType.Rotational)
            return R(DeviceKind.UsbStick, Confidence.Likely, "mediu amovibil pe USB");
        if (f.Medium == MediumType.SolidState) return R(DeviceKind.Ssd, Confidence.Likely, "sistemul raportează SSD");
        if (f.Medium == MediumType.Rotational) return R(DeviceKind.Hdd, Confidence.Likely, "sistemul raportează HDD");
        if (Has(f.VolumeName, "RAID") || Has(f.VolumeName, "HDD")) return R(DeviceKind.Hdd, Confidence.Hint, "indiciu din nume");
        if (Has(f.VolumeName, "SSD")) return R(DeviceKind.Ssd, Confidence.Hint, "indiciu din nume");
        return R(DeviceKind.ExternalDevice, Confidence.Fallback, "sistemul nu raportează tipul");
    }
}
