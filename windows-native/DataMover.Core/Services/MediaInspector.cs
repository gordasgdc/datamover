namespace DataMover.Core.Services;

/// <summary>
/// [M4, 2026-09-06] Metadate video pentru raportul DIT — echivalent
/// Windows al `MediaInspector.swift` (Mac), dar motor de extragere
/// DIFERIT: Mac foloseste AVFoundation (framework de sistem). Windows nu
/// are un echivalent la fel de simplu FARA o dependinta noua (Media
/// Foundation via WinRT ar cere țintirea unui SDK Windows specific,
/// netestabil de pe acest Mac) — in loc, un parser MP4/MOV PROPRIU, minimal,
/// zero dependinta, care citeste direct structura de "atoms"/"boxes" ISO-BMFF
/// (acelasi format container pentru .mp4/.mov, indiferent de camera).
/// Acopera: rezolutie, codec video/audio, durata, fps, canale audio.
///
/// NEACOPERIT deliberat pe Windows (spus explicit, nu ascuns): timecode
/// embedat si camera/reel — pe Mac vin "gratuit" din AVFoundation; pe
/// Windows ar cere parsarea suplimentara a track-ului "tmcd" (offset-uri
/// stco/co64 + tabelul de esantioane) — TODO real, de facut daca devine
/// necesar, nu simulat aici.
/// </summary>
public sealed class MediaMetadata
{
    public double? DurationSeconds { get; set; }
    public string? VideoCodec { get; set; }
    public int? Width { get; set; }
    public int? Height { get; set; }
    public double? FrameRate { get; set; }
    public string? AudioCodec { get; set; }
    public int? AudioChannels { get; set; }

    public string? ResolutionText => (Width is > 0 && Height is > 0) ? $"{Width}×{Height}" : null;
    public bool IsEmpty => DurationSeconds == null && Width == null && VideoCodec == null && AudioCodec == null;
}

public static class MediaInspector
{
    public static MediaMetadata? Probe(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var moov = FindBox(stream, "moov", stream.Length);
            if (moov == null) return null;

            var meta = new MediaMetadata();
            long pos = moov.Value.start;
            long end = moov.Value.start + moov.Value.size;
            while (pos < end)
            {
                var box = ReadBoxHeader(stream, pos);
                if (box == null) break;
                if (box.Value.type == "trak") ParseTrak(stream, box.Value.start, box.Value.size, meta);
                pos = box.Value.start + box.Value.size;
            }
            return meta.IsEmpty ? null : meta;
        }
        catch
        {
            // fisier corupt/trunchiat/nu e MP4-MOV valid - un raport fara
            // metadate pe acel rand ramane la fel de valid.
            return null;
        }
    }

    private readonly record struct Box(string type, long start, long size);

    /// Citeste antetul unei cutii ISO-BMFF la offset-ul `pos`: 4 octeti
    /// mărime (big-endian) + 4 octeti tip (ASCII). `start` întors e
    /// începutul CONȚINUTULUI cutiei (după cei 8 octeți de antet) — sau,
    /// pentru mărime extinsă pe 64 biți (`size == 1`), după cei 16.
    private static Box? ReadBoxHeader(Stream stream, long pos)
    {
        if (pos + 8 > stream.Length) return null;
        stream.Seek(pos, SeekOrigin.Begin);
        Span<byte> header = stackalloc byte[8];
        if (stream.Read(header) != 8) return null;
        long size = ReadUInt32BE(header, 0);
        string type = System.Text.Encoding.ASCII.GetString(header.Slice(4, 4));
        long contentStart = pos + 8;
        if (size == 1)
        {
            Span<byte> ext = stackalloc byte[8];
            if (stream.Read(ext) != 8) return null;
            size = ReadInt64BE(ext, 0);
            contentStart = pos + 16;
        }
        else if (size == 0)
        {
            size = stream.Length - pos; // cutie pana la finalul fisierului
        }
        // `size` de aici e marimea TOTALA a cutiei (antet+continut) - se
        // recalculeaza in Box.size ca marime totala, dar `start` marcheaza
        // inceputul continutului, ca apelantul sa poata itera direct.
        return new Box(type, contentStart, size - (contentStart - pos));
    }

    /// Cauta prima cutie de tip `targetType` la nivelul curent, pornind de
    /// la offset-ul 0 — folosit doar pentru `moov` (nivel de fisier).
    private static Box? FindBox(Stream stream, string targetType, long searchEnd)
    {
        long pos = 0;
        while (pos < searchEnd)
        {
            var box = ReadBoxHeader(stream, pos);
            if (box == null) break;
            if (box.Value.type == targetType) return box;
            pos = box.Value.start + box.Value.size;
        }
        return null;
    }

    private static Box? FindChildBox(Stream stream, string targetType, long parentStart, long parentSize)
    {
        long pos = parentStart;
        long end = parentStart + parentSize;
        while (pos < end)
        {
            var box = ReadBoxHeader(stream, pos);
            if (box == null) break;
            if (box.Value.type == targetType) return box;
            pos = box.Value.start + box.Value.size;
        }
        return null;
    }

    private static void ParseTrak(Stream stream, long trakStart, long trakSize, MediaMetadata meta)
    {
        var mdia = FindChildBox(stream, "mdia", trakStart, trakSize);
        if (mdia == null) return;

        var hdlr = FindChildBox(stream, "hdlr", mdia.Value.start, mdia.Value.size);
        string handlerType = "";
        if (hdlr != null)
        {
            stream.Seek(hdlr.Value.start + 8, SeekOrigin.Begin); // version(1)+flags(3)+pre_defined(4)
            Span<byte> h = stackalloc byte[4];
            stream.Read(h);
            handlerType = System.Text.Encoding.ASCII.GetString(h);
        }
        if (handlerType != "vide" && handlerType != "soun") return;

        double timescale = 0, durationUnits = 0;
        var mdhd = FindChildBox(stream, "mdhd", mdia.Value.start, mdia.Value.size);
        if (mdhd != null)
        {
            stream.Seek(mdhd.Value.start, SeekOrigin.Begin);
            Span<byte> versionByte = stackalloc byte[1];
            stream.Read(versionByte);
            if (versionByte[0] == 1)
            {
                stream.Seek(mdhd.Value.start + 4 + 8 + 8, SeekOrigin.Begin); // version+flags(4) + creation(8) + modification(8)
                Span<byte> buf = stackalloc byte[12];
                stream.Read(buf);
                timescale = ReadUInt32BE(buf, 0);
                durationUnits = ReadInt64BE(buf, 4);
            }
            else
            {
                stream.Seek(mdhd.Value.start + 4 + 4 + 4, SeekOrigin.Begin); // version+flags(4) + creation(4) + modification(4)
                Span<byte> buf = stackalloc byte[8];
                stream.Read(buf);
                timescale = ReadUInt32BE(buf, 0);
                durationUnits = ReadUInt32BE(buf, 4);
            }
        }
        if (timescale > 0 && meta.DurationSeconds == null)
            meta.DurationSeconds = durationUnits / timescale;

        var minf = FindChildBox(stream, "minf", mdia.Value.start, mdia.Value.size);
        if (minf == null) return;
        var stbl = FindChildBox(stream, "stbl", minf.Value.start, minf.Value.size);
        if (stbl == null) return;
        var stsd = FindChildBox(stream, "stsd", stbl.Value.start, stbl.Value.size);

        if (handlerType == "vide")
        {
            if (stsd != null) ParseVideoSampleEntry(stream, stsd.Value, meta);
            var stts = FindChildBox(stream, "stts", stbl.Value.start, stbl.Value.size);
            if (stts != null && timescale > 0)
            {
                stream.Seek(stts.Value.start + 4 + 4, SeekOrigin.Begin); // version+flags(4) + entry_count(4)
                Span<byte> entry = stackalloc byte[8];
                if (stream.Read(entry) == 8)
                {
                    long sampleDelta = ReadUInt32BE(entry, 4);
                    if (sampleDelta > 0) meta.FrameRate = timescale / sampleDelta;
                }
            }
        }
        else // "soun"
        {
            if (stsd != null) ParseAudioSampleEntry(stream, stsd.Value, meta);
        }
    }

    private static void ParseVideoSampleEntry(Stream stream, Box stsd, MediaMetadata meta)
    {
        // stsd: version(1)+flags(3)+entry_count(4), apoi prima
        // VisualSampleEntry: size(4)+format(4)(codec FourCC)+reserved(6)+
        // data_reference_index(2)+... +width(2)@offset 24+height(2)@offset 26
        // (relativ la inceputul VisualSampleEntry).
        stream.Seek(stsd.start + 8, SeekOrigin.Begin);
        Span<byte> entryHeader = stackalloc byte[8];
        if (stream.Read(entryHeader) != 8) return;
        string codec = System.Text.Encoding.ASCII.GetString(entryHeader.Slice(4, 4));
        meta.VideoCodec = FourCCToCodecName(codec);

        // stsd.start + 8 (version/flags/entry_count) + 8 (antetul propriu al
        // intrarii, deja consumat mai sus prin entryHeader) + 8
        // (SampleEntry.reserved[6]+data_reference_index[2]) + 16
        // (VisualSampleEntry.pre_defined(2)+reserved(2)+pre_defined[3x4]) = width.
        stream.Seek(stsd.start + 8 + 8 + 8 + 16, SeekOrigin.Begin);
        Span<byte> dims = stackalloc byte[4];
        if (stream.Read(dims) == 4)
        {
            meta.Width = (int)ReadUInt16BE(dims, 0);
            meta.Height = (int)ReadUInt16BE(dims, 2);
        }
    }

    private static void ParseAudioSampleEntry(Stream stream, Box stsd, MediaMetadata meta)
    {
        stream.Seek(stsd.start + 8, SeekOrigin.Begin);
        Span<byte> entryHeader = stackalloc byte[8];
        if (stream.Read(entryHeader) != 8) return;
        string codec = System.Text.Encoding.ASCII.GetString(entryHeader.Slice(4, 4));
        meta.AudioCodec = FourCCToCodecName(codec);

        // stsd.start + 8 (version/flags/entry_count) + 8 (antetul propriu,
        // deja consumat) + 8 (SampleEntry.reserved+data_reference_index) + 8
        // (AudioSampleEntry.reserved[2x4]) = channelcount.
        stream.Seek(stsd.start + 8 + 8 + 8 + 8, SeekOrigin.Begin);
        Span<byte> ch = stackalloc byte[2];
        if (stream.Read(ch) == 2) meta.AudioChannels = (int)ReadUInt16BE(ch, 0);
    }

    private static string FourCCToCodecName(string fourCC) => fourCC switch
    {
        "avc1" => "H.264",
        "hvc1" or "hev1" => "HEVC",
        "apch" => "ProRes 422 HQ",
        "apcn" => "ProRes 422",
        "apcs" => "ProRes 422 LT",
        "apco" => "ProRes 422 Proxy",
        "ap4h" => "ProRes 4444",
        "mp4a" => "AAC",
        "twos" or "sowt" or "lpcm" or "in24" => "PCM",
        _ => fourCC.Trim(),
    };

    private static uint ReadUInt32BE(ReadOnlySpan<byte> b, int offset) =>
        (uint)((b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3]);
    private static ushort ReadUInt16BE(ReadOnlySpan<byte> b, int offset) =>
        (ushort)((b[offset] << 8) | b[offset + 1]);
    private static long ReadInt64BE(ReadOnlySpan<byte> b, int offset)
    {
        long value = 0;
        for (int i = 0; i < 8; i++) value = (value << 8) | b[offset + i];
        return value;
    }
}
