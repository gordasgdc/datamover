using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace DataMover.Core.Services;

/// Port 1:1 al LicenseCore.swift (DataMover Mac) / LicenseCore.cs
/// (GDCVaultWin, GDCPluginManagerWin) - validator de seriale format GDC,
/// aceeasi schema binara pe toate platformele, aceeasi cheie publica
/// Ed25519 hardcodata in tot ecosistemul (2026-08-28, cerut de Cristi
/// pentru clientul Windows WPF nou).
[SupportedOSPlatform("windows")]
public static class LicenseCore
{
    public readonly record struct Payload(long ExpiresAt, bool MachineLocked);

    public enum ValidationErrorKind { MalformedCode, BadSignature, WrongProduct, WrongMachine, Expired }

    public sealed class ValidationError(ValidationErrorKind kind, long expiredAt = 0) : Exception
    {
        public ValidationErrorKind Kind { get; } = kind;
        public long ExpiredAt { get; } = expiredAt;
    }

    /// Identica cu LicenseCore.swift/GDCVaultWin - cheia publica a
    /// ecosistemului GDC, nu una specifica DataMover.
    private const string PublicKeyBase64 = "I1h23MNMRbOhc0ObKJrfa3oFHKA9w+SzbNrroAIy8hs=";

    public const int PayloadSize = 22;

    public static Payload Validate(string serial, string expectedProductId)
    {
        var packed = Base32Decode(serial);
        if (packed is null || packed.Length != PayloadSize + 64)
            throw new ValidationError(ValidationErrorKind.MalformedCode);

        var payloadBytes = packed[..PayloadSize];
        var signature = packed[PayloadSize..];

        var publicKeyBytes = Convert.FromBase64String(PublicKeyBase64);
        var publicKey = new Ed25519PublicKeyParameters(publicKeyBytes, 0);
        var verifier = new Ed25519Signer();
        verifier.Init(forSigning: false, publicKey);
        verifier.BlockUpdate(payloadBytes, 0, payloadBytes.Length);
        if (!verifier.VerifySignature(signature))
            throw new ValidationError(ValidationErrorKind.BadSignature);

        var storedProductHash = payloadBytes[..4];
        var expectedProductHash = ProductHash(expectedProductId);
        if (!storedProductHash.AsSpan().SequenceEqual(expectedProductHash))
            throw new ValidationError(ValidationErrorKind.WrongProduct);

        long expiresAt = 0;
        for (var i = 4; i < 12; i++) expiresAt = (expiresAt << 8) | payloadBytes[i];

        var storedMachineHash = payloadBytes[16..22];
        var isMachineLocked = storedMachineHash.Any(b => b != 0);
        if (isMachineLocked && !storedMachineHash.AsSpan().SequenceEqual(MachineID.HashBytes))
            throw new ValidationError(ValidationErrorKind.WrongMachine);

        if (expiresAt != 0 && expiresAt < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            throw new ValidationError(ValidationErrorKind.Expired, expiresAt);

        return new Payload(expiresAt, isMachineLocked);
    }

    public static byte[] ProductHash(string productId) =>
        SHA512.HashData(Encoding.UTF8.GetBytes(productId))[..4];

    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string Base32Encode(ReadOnlySpan<byte> data)
    {
        int bits = 0, value = 0;
        var output = new StringBuilder();
        foreach (var b in data)
        {
            value = (value << 8) | b;
            bits += 8;
            while (bits >= 5)
            {
                output.Append(Base32Alphabet[(value >> (bits - 5)) & 0x1F]);
                bits -= 5;
            }
        }
        if (bits > 0) output.Append(Base32Alphabet[(value << (5 - bits)) & 0x1F]);
        return output.ToString();
    }

    public static byte[]? Base32Decode(string input)
    {
        var cleaned = input.ToUpperInvariant().Replace("-", "").Replace(" ", "").Replace("=", "");
        int bits = 0, value = 0;
        var output = new List<byte>();
        foreach (var ch in cleaned)
        {
            var index = Base32Alphabet.IndexOf(ch);
            if (index < 0) return null;
            value = (value << 5) | index;
            bits += 5;
            if (bits >= 8)
            {
                output.Add((byte)((value >> (bits - 8)) & 0xFF));
                bits -= 8;
            }
        }
        return output.ToArray();
    }
}
