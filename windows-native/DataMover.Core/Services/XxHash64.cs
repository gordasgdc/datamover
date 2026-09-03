namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-03] Port 1:1 al XXHash64.swift (Mac) — xxHash64 (XXH64, seed 0),
/// implementare pura C#, fara nicio dependinta NuGet.
///
/// DE CE: e algoritmul implicit al ofloaderelor profesionale (ShotPut Pro,
/// Silverstack) si singurul checksum non-criptografic acceptat de formatul
/// MHL (vezi MhlWriter.cs). E de cateva ori mai rapid decat MD5 pe acelasi
/// fisier — pe un card de sute de GB, verificarea e etapa care dureaza, nu
/// copierea.
///
/// DE CE NU pachetul `System.IO.Hashing`: ar adauga o dependinta NuGet
/// intr-un proiect care pana acum se construieste doar din BCL — un restore
/// esuat in CI ar bloca release-ul Windows pentru un algoritm de 100 de
/// linii. Implementarea de aici e validata pe aceiasi vectori de test ca
/// varianta Mac (0/1/3/31/32/33/256/1800 octeti, hash-uite in bucati de
/// dimensiuni diferite), deci cele doua platforme produc EXACT acelasi
/// hash pentru acelasi fisier — obligatoriu, altfel un MHL scris pe Mac
/// n-ar putea fi verificat pe Windows.
/// </summary>
public sealed class XxHash64
{
    private const ulong P1 = 0x9E3779B185EBCA87UL;
    private const ulong P2 = 0xC2B2AE3D27D4EB4FUL;
    private const ulong P3 = 0x165667B19E3779F9UL;
    private const ulong P4 = 0x85EBCA77C2B2AE63UL;
    private const ulong P5 = 0x27D4EB2F165667C5UL;

    private readonly ulong _seed;
    private ulong _v1, _v2, _v3, _v4;
    private ulong _total;
    private readonly byte[] _buf = new byte[32];
    private int _bufLen;

    public XxHash64(ulong seed = 0)
    {
        _seed = seed;
        _v1 = seed + P1 + P2;
        _v2 = seed + P2;
        _v3 = seed;
        _v4 = seed - P1;
    }

    private static ulong Rotl(ulong x, int r) => (x << r) | (x >> (64 - r));
    private static ulong Round(ulong acc, ulong input) => Rotl(acc + input * P2, 31) * P1;
    private static ulong MergeRound(ulong acc, ulong val) => (acc ^ Round(0, val)) * P1 + P4;

    private static ulong ReadU64(byte[] data, int offset) =>
        BitConverter.ToUInt64(data, offset); // x64/ARM64 Windows sunt little-endian, ca formatul XXH64
    private static uint ReadU32(byte[] data, int offset) => BitConverter.ToUInt32(data, offset);

    public void Update(byte[] data, int count)
    {
        if (count <= 0) return;
        _total += (ulong)count;
        int idx = 0;

        if (_bufLen > 0)
        {
            if (_bufLen + count < 32)
            {
                Buffer.BlockCopy(data, 0, _buf, _bufLen, count);
                _bufLen += count;
                return;
            }
            int need = 32 - _bufLen;
            Buffer.BlockCopy(data, 0, _buf, _bufLen, need);
            _v1 = Round(_v1, ReadU64(_buf, 0));
            _v2 = Round(_v2, ReadU64(_buf, 8));
            _v3 = Round(_v3, ReadU64(_buf, 16));
            _v4 = Round(_v4, ReadU64(_buf, 24));
            idx = need;
            _bufLen = 0;
        }

        while (idx + 32 <= count)
        {
            _v1 = Round(_v1, ReadU64(data, idx));
            _v2 = Round(_v2, ReadU64(data, idx + 8));
            _v3 = Round(_v3, ReadU64(data, idx + 16));
            _v4 = Round(_v4, ReadU64(data, idx + 24));
            idx += 32;
        }

        if (idx < count)
        {
            int rest = count - idx;
            Buffer.BlockCopy(data, idx, _buf, 0, rest);
            _bufLen = rest;
        }
    }

    public ulong Digest()
    {
        ulong h;
        if (_total >= 32)
        {
            h = Rotl(_v1, 1) + Rotl(_v2, 7) + Rotl(_v3, 12) + Rotl(_v4, 18);
            h = MergeRound(h, _v1);
            h = MergeRound(h, _v2);
            h = MergeRound(h, _v3);
            h = MergeRound(h, _v4);
        }
        else
        {
            h = _seed + P5;
        }
        h += _total;

        int i = 0;
        while (i + 8 <= _bufLen)
        {
            h ^= Round(0, ReadU64(_buf, i));
            h = Rotl(h, 27) * P1 + P4;
            i += 8;
        }
        if (i + 4 <= _bufLen)
        {
            h ^= ReadU32(_buf, i) * P1;
            h = Rotl(h, 23) * P2 + P3;
            i += 4;
        }
        while (i < _bufLen)
        {
            h ^= _buf[i] * P5;
            h = Rotl(h, 11) * P1;
            i++;
        }

        h ^= h >> 33;
        h *= P2;
        h ^= h >> 29;
        h *= P3;
        h ^= h >> 32;
        return h;
    }

    /// Reprezentarea canonica (big-endian, ca numar) — identica cu ce scriu
    /// `xxhsum` si Silverstack in campul `xxhash64be` din MHL.
    public string HexDigest() => Digest().ToString("x16");
}
