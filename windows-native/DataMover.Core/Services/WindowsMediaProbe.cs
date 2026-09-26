using System.Management;
using DataMover.Core.Domain;

namespace DataMover.Core.Services;

/// <summary>
/// Adaptor Windows: aduna MediaFacts pasiv (DriveInfo + WMI) si clasifica.
/// WMI: Win32_LogicalDisk → partitie → Win32_DiskDrive (Model, Index) →
/// MSFT_PhysicalDisk (BusType, MediaType). Orice esec → fapte partiale,
/// deci fallback „dispozitiv extern”, niciodata o exceptie spre UI.
/// </summary>
public static class WindowsMediaProbe
{
    private static readonly Dictionary<string, MediaClass> Cache = new(StringComparer.OrdinalIgnoreCase);

    public static MediaClass Classify(string path, bool cameraCard = false)
    {
        lock (Cache) if (Cache.TryGetValue(path, out var c)) return c;
        var result = MediaClassifier.Classify(Gather(path, cameraCard));
        lock (Cache) Cache[path] = result;
        return result;
    }

    public static void Forget(string path) { lock (Cache) Cache.Remove(path); }

    public static MediaFacts Gather(string path, bool cameraCard)
    {
        var f = new MediaFacts { CameraCardStructure = cameraCard };
        try
        {
            var full = Path.GetFullPath(path);
            var root = Path.GetPathRoot(full) ?? full;
            f.IsVolumeRoot = string.Equals(full.TrimEnd('\\'), root.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            var di = new DriveInfo(root);
            f.VolumeName = di.IsReady ? di.VolumeLabel : "";
            f.TotalBytes = di.IsReady ? di.TotalSize : null;
            switch (di.DriveType)
            {
                case DriveType.Network: f.IsNetwork = true; return f;
                case DriveType.Removable: f.IsRemovableMedia = true; break;
                case DriveType.Fixed: f.IsRemovableMedia = false; break;
            }
            if (!OperatingSystem.IsWindows()) return f;
            QueryWmi(root.TrimEnd('\\'), f);
            // Discul de sistem (litera Windows) e volumul intern.
            if (string.Equals(root, Path.GetPathRoot(Environment.SystemDirectory), StringComparison.OrdinalIgnoreCase)) f.IsInternal = true;
        }
        catch { /* fapte partiale */ }
        return f;
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static void QueryWmi(string letter, MediaFacts f)
    {
        try
        {
            using var parts = new ManagementObjectSearcher($"ASSOCIATORS OF {{Win32_LogicalDisk.DeviceID='{letter}'}} WHERE AssocClass=Win32_LogicalDiskToPartition");
            foreach (ManagementObject part in parts.Get())
            {
                using var disks = new ManagementObjectSearcher($"ASSOCIATORS OF {{Win32_DiskPartition.DeviceID='{part["DeviceID"]}'}} WHERE AssocClass=Win32_DiskDriveToDiskPartition");
                foreach (ManagementObject disk in disks.Get())
                {
                    f.Model = disk["Model"] as string;
                    var iface = disk["InterfaceType"] as string;
                    if (string.Equals(iface, "USB", StringComparison.OrdinalIgnoreCase)) f.Bus = "USB";
                    var index = Convert.ToInt32(disk["Index"]);
                    using var phys = new ManagementObjectSearcher(@"root\Microsoft\Windows\Storage",
                        $"SELECT BusType, MediaType FROM MSFT_PhysicalDisk WHERE DeviceId='{index}'");
                    foreach (ManagementObject p in phys.Get())
                    {
                        f.Medium = Convert.ToInt32(p["MediaType"]) switch { 3 => MediumType.Rotational, 4 => MediumType.SolidState, _ => MediumType.Unknown };
                        f.Bus = Convert.ToInt32(p["BusType"]) switch
                        {
                            7 => "USB", 12 => "SD", 17 => "NVMe", 11 => "SATA", 15 => "Virtual", 14 => "Virtual", _ => f.Bus,
                        };
                    }
                    return;
                }
            }
        }
        catch { /* WMI indisponibil: raman faptele DriveInfo */ }
    }
}
