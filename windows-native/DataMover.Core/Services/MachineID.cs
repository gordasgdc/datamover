using System.Management;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace DataMover.Core.Services;

/// Port al MachineID.swift (DataMover Mac) pentru Windows - ID hardware
/// stabil din Win32_ComputerSystemProduct.UUID (WMI), la fel ca
/// GDCVaultWin/GDCPluginManagerWin. NU produce acelasi hash ca pe Mac
/// pentru aceeasi masina fizica (surse diferite) - fiecare platforma are
/// propriul spatiu de coduri.
[SupportedOSPlatform("windows")]
public static class MachineID
{
    private static string RawPlatformUuid()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT UUID FROM Win32_ComputerSystemProduct");
            foreach (var obj in searcher.Get())
            {
                var uuid = obj["UUID"]?.ToString();
                if (!string.IsNullOrWhiteSpace(uuid) && uuid != "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
                    return uuid;
            }
        }
        catch { /* WMI indisponibil - rulare fara privilegii, VM restrictionata, etc. */ }
        return "win-machine-id-unavailable";
    }

    public static byte[] HashBytes =>
        SHA512.HashData(Encoding.UTF8.GetBytes(RawPlatformUuid()))[..6];

    public static string Display => LicenseCore.Base32Encode(HashBytes);
}
