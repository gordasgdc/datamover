using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace DataMover.Core.Services;

/// Port 1:1 al AnalyticsClient.cs (GDCVaultWin) - scriere fire-and-forget
/// catre Supabase (inregistrare dispozitiv). Tabelul accepta DOAR INSERT
/// de la cheia anon, deci nu poate niciodata citi/suprascrie/sterge nimic,
/// iar orice eroare e inghitita silentios.
public static class AnalyticsClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(8) };

    public static void RegisterDevice(string name, string email)
    {
        var body = new Dictionary<string, string>
        {
            ["machine_id"] = MachineID.Display,
            ["name"] = name.Trim(),
            ["email"] = email.Trim(),
            ["product"] = LicenseManager.ProductId,
        };
        _ = PostAsync("devices", body);
    }

    private static async Task PostAsync(string table, Dictionary<string, string> body)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, SupabaseConfig.RestUrl(table));
            request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
            request.Headers.Add("apikey", SupabaseConfig.AnonKey);
            request.Headers.Add("Authorization", $"Bearer {SupabaseConfig.AnonKey}");
            request.Headers.Add("Prefer", "return=minimal");
            await Http.SendAsync(request);
        }
        catch { /* deliberat ignorat */ }
    }
}
