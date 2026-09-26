using DataMover.Core.Models;
using DataMover.Core.Services;

/// Aceleași 6 scenarii ca mac-native/Tests/DataMoverMacTests/ReportTests.swift, cu aceleași date,
/// ca HTML-ul Mac și cel Windows să poată fi comparate octet cu octet.
public static class ReportScenarios
{
    static ReportRow Row(int i, string status = "OK", string? file = null, string error = "")
    {
        var h = unchecked((ulong)i * 0x9E3779B97F4A7C15UL).ToString("x16");
        bool bad = status.StartsWith("NEPOTRIVIRE"), err = status.StartsWith("EROARE");
        return new ReportRow
        {
            File = file ?? $"PRIVATE/M4ROOT/CLIP/C{i:0000}.MP4", SizeBytes = 1_000_000 + i * 4099,
            SrcHash = err ? "" : h, DstHash = err ? "" : (bad ? "ffff" + h[4..] : h), Status = status, Error = error,
        };
    }

    static DeliveryReport Base(string lang) => new()
    {
        Lang = lang, AppVersion = "2.16.2 (40)",
        GeneratedAt = DateTimeOffset.FromUnixTimeSeconds(1_790_000_000).ToLocalTime(),
        StartedAt = DateTimeOffset.FromUnixTimeSeconds(1_789_999_000).ToLocalTime(),
        FinishedAt = DateTimeOffset.FromUnixTimeSeconds(1_789_999_754).ToLocalTime(),
        FolderName = "2026-09-26_SOARE_DE_IARNĂ_A001", Destination = "/Volumes/SHUTTLE-01/2026-09-26_SOARE_DE_IARNĂ_A001",
        Project = "Soare de iarnă", Card = "A001", SourceName = "A001", OperatorName = "DIT — Ana Pérez Núñez",
        Camera = "ARRI Alexa 35", Verification = "xxHash64 — checksum în flux", CopyCount = 2,
        MhlFile = "2026-09-26_SOARE_DE_IARNĂ_A001.mhl", CsvFile = "offload_report_2026-09-26_10-00-00.csv", JobId = "1d861b6f",
    };

    static DeliveryReport With(DeliveryReport b, Action<DeliveryReport> f)
    {
        var r = Base(b.Lang);
        foreach (var p in typeof(DeliveryReport).GetProperties().Where(p => p.CanWrite)) p.SetValue(r, p.GetValue(b));
        f(r); return r;
    }

    public static List<(string Name, DeliveryReport Report)> All(string lang)
    {
        var okRows = Enumerable.Range(1, 10).Select(i => Row(i)).ToList();
        var ok = Base(lang); ok.Rows = okRows; ok.OkCount = 10; ok.BytesConfirmed = okRows.Sum(r => r.SizeBytes);
        var warn = With(ok, r => { var rows = okRows.ToList(); rows[3] = Row(4, "OK (reîncercat)"); r.Rows = rows; r.RecoveredCount = 1; });
        var fail = Base(lang);
        fail.Rows = Enumerable.Range(1, 8).Select(i => Row(i)).Concat(new[] {
            Row(9, "NEPOTRIVIRE", error: "Checksum-ul copiei diferă de sursă."),
            Row(10, "EROARE (reîncercat)", error: "Discul nu a confirmat scrierea (flush).") }).ToList();
        fail.OkCount = 8; fail.FailCount = 2; fail.BytesConfirmed = 8_100_000;
        var longR = With(ok, r =>
        {
            r.Destination = "/Volumes/RAID-02 Backup Principal Producție/" + string.Concat(Enumerable.Repeat("Subfolder_foarte_lung_pentru_test_", 5)) + "A001";
            r.Rows = new[] { Row(1, file: "PRIVATE/M4ROOT/CLIP/" + string.Concat(Enumerable.Repeat("Numele_unui_clip_extrem_de_lung_ăîșțâ_ñáéíóú_", 6)) + "C0001.MP4"), Row(2) };
            r.OkCount = 2; r.Notes = "Card cu fișiere Unicode: ăîșțâ ÄÖÜ ñ 日本語 — verificat.";
        });
        var many = With(ok, r => { r.Rows = Enumerable.Range(1, 140).Select(i => Row(i)).ToList(); r.OkCount = 180; r.BytesConfirmed = 185_000_000_000; });
        var cancel = With(ok, r => { r.Cancelled = true; r.OkCount = 4; r.Rows = okRows.Take(4).ToList(); });
        return new() { ("1-reusit", ok), ("2-avertisment", warn), ("3-esec-partial", fail), ("4-cai-lungi", longR), ("5-multipagina", many), ("6-anulat", cancel) };
    }
}
