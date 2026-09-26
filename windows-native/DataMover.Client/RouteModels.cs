using System.Windows.Media;
using DataMover.Core.Domain;

namespace DataMover.Client;

/// <summary>Un capat al traseului (sursa sau copie). Record: egalitate pe valoare,
/// ca sincronizarea sa inlocuiasca doar ce s-a schimbat (fara palpaire).</summary>
public sealed record EndpointTile(
    string Path, string Name, DeviceKind Kind, string RoleText, string KindLine, string StateLine,
    string Figure, string Caption, string Secondary, double BarValue, bool HasBar, bool Offline, bool CanRemove);

/// <summary>Incident afisat operatorului: severitate (simbol + text, nu doar
/// culoare), cauza, actiunea recomandata.</summary>
public sealed record IncidentItem(string SeverityLabel, Brush Brush, string Title, string Cause, string ActionLine, string Subject);

public static class RouteText
{
    public static string KindLabel(DeviceKind k) => k switch
    {
        DeviceKind.CFexpress => "Card CFexpress",
        DeviceKind.SdCard => "Card SD",
        DeviceKind.MemoryCard => "Card de memorie",
        DeviceKind.Ssd => "SSD extern",
        DeviceKind.Hdd => "HDD / RAID extern",
        DeviceKind.UsbStick => "Stick USB",
        DeviceKind.InternalVolume => "Volum intern",
        DeviceKind.Folder => "Folder ales manual",
        _ => "Dispozitiv extern",
    };
}
