import Foundation
import CryptoKit

/// Redactare pentru jurnal și pachetul de diagnostic (OBSERVABILITY_STANDARD).
///
/// Două niveluri:
/// - `redactSecrets` — aplicat MEREU, la scriere: email-uri, perechi
///   cheie=valoare sensibile (token, parolă, licență, serial…), șiruri lungi
///   care arată a chei/coduri, calea de acasă a utilizatorului.
/// - `anonymizePaths` — aplicat la EXPORT (implicit): fiecare cale absolută
///   devine `<path#hash>` (extensia se păstrează, e utilă pentru diagnostic).
///   Același hash pentru aceeași cale, deci corelarea în log rămâne posibilă.
enum Redactor {
    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: []) }

    private static let email = rx(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    private static let keyValue = rx(#"(?i)\b(token|access[_-]?token|refresh[_-]?token|api[_-]?key|apikey|secret|password|passwd|pwd|licen[cs]e(?:[_-]?code)?|serial|authorization|bearer|cookie|session[_-]?key)\b(\s*[:=]\s*|\s+)("[^"]*"|'[^']*'|[^\s,;]+)"#)
    /// Șiruri lungi fără spații, de tip cheie/cod (base64/base32/hex, ≥ 24 de
    /// caractere, cu litere ȘI cifre) — codurile de licență GDC intră aici.
    private static let longToken = rx(#"\b(?=[A-Za-z0-9+/=_\-]*[0-9])(?=[A-Za-z0-9+/=_\-]*[A-Za-z])[A-Za-z0-9+/=_\-]{24,}\b"#)
    private static let homePath = rx(#"/Users/[^/\s"']+"#)
    private static let absolutePath = rx(#"(?<![\w])(/(?:Volumes|Users|private|tmp|var|Applications|Library|System)(?:/[^\s"',;:|<>]+)+|~(?:/[^\s"',;:|<>]+)+)"#)

    /// Câmpuri structurate: o cheie sensibilă își pierde valoarea complet,
    /// indiferent ce conține.
    static func isSensitiveKey(_ key: String) -> Bool {
        let k = key.lowercased()
        return ["token", "secret", "password", "passwd", "pwd", "licen", "serial", "authorization", "bearer",
                "cookie", "apikey", "api_key", "email", "machineid", "machine_id"].contains { k.contains($0) }
    }

    static func redactFields(_ fields: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { k, v in (k, isSensitiveKey(k) ? "<redacted>" : redactSecrets(v)) })
    }

    static func redactSecrets(_ s: String) -> String {
        var out = replace(email, in: s, with: "<email>")
        out = replace(keyValue, in: out, with: "$1$2<redacted>")
        out = replace(longToken, in: out, with: "<secret>")
        out = replace(homePath, in: out, with: "~")
        return out
    }

    /// Hash scurt, stabil, al unei căi (nu reversibil fără calea originală).
    static func pathToken(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let short = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension
        return ext.isEmpty || ext.count > 8 ? "<path#\(short)>" : "<path#\(short)>.\(ext.lowercased())"
    }

    static func anonymizePaths(_ s: String) -> String {
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in absolutePath.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            result += pathToken(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func replace(_ r: NSRegularExpression, in s: String, with template: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
