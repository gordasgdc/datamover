import Foundation
import AVFoundation
import QuickLookThumbnailing
import AppKit

/// [M4, 2026-09-06] Metadate video pentru raportul DIT — port CONCEPTUAL
/// din `CGConvertor/MediaInspector.swift`, dar motor de extragere DIFERIT
/// și deliberat: CGConvertor folosește `ffprobe` (are deja `ffmpeg`
/// bundle-uit pentru transcodare). DataMover NU are `ffmpeg` — decizie de
/// arhitectură existentă, ca aplicația să rămână lightweight (offload-ul
/// nu are nevoie de un motor de transcodare). Aici, `AVFoundation`
/// (framework de sistem, ZERO dependință nouă) acoperă tot ce s-a cerut:
/// rezoluție, fps, codec video/audio, durată, canale audio, și — cel mai
/// fragil de extras — timecode embedat (track QuickTime dedicat).
///
/// Extragerea rulează DOAR la generarea raportului (eșantionul plafonat,
/// max. 500 fișiere — vezi `pdfSampleRows`), NICIODATĂ în timpul copierii
/// — motorul de transfer (`FanOutCopier`) rămâne complet neatins, fără
/// nicio latență nouă pe calea critică de I/O.
struct MediaMetadata: Equatable {
    var durationSeconds: Double?
    var videoCodec: String?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var audioCodec: String?
    var audioChannels: Int?
    var audioSampleRate: Double?
    /// Best-effort — `nil` dacă fișierul n-are un track de timecode
    /// QuickTime dedicat (majoritatea clipurilor de consum nu au).
    var timecode: String?
    /// Best-effort — din metadatele QuickTime comune (make/model) sau
    /// specifice camerei, dacă sunt prezente.
    var cameraModel: String?
    /// Best-effort — cheia "reel"/"clip name" din metadatele QuickTime,
    /// dacă e prezentă (ProRes/RED/ARRI o scriu frecvent).
    var reelName: String?

    var resolutionText: String? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return "\(w)×\(h)"
    }

    var isEmpty: Bool {
        durationSeconds == nil && width == nil && videoCodec == nil && audioCodec == nil
    }
}

enum MediaInspector {
    static func probe(path: String) -> MediaMetadata? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        var meta = MediaMetadata()

        let duration = asset.duration.seconds
        if duration.isFinite, duration > 0 { meta.durationSeconds = duration }

        if let track = asset.tracks(withMediaType: .video).first {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            let w = Int(abs(transformed.width).rounded())
            let h = Int(abs(transformed.height).rounded())
            if w > 0 && h > 0 { meta.width = w; meta.height = h }
            if track.nominalFrameRate > 0 { meta.frameRate = Double(track.nominalFrameRate) }
            if let desc = track.formatDescriptions.first {
                meta.videoCodec = codecName(for: desc as! CMFormatDescription)
            }
        }

        if let track = asset.tracks(withMediaType: .audio).first, let desc = track.formatDescriptions.first {
            let fd = desc as! CMFormatDescription
            meta.audioCodec = codecName(for: fd)
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                meta.audioChannels = Int(asbd.mChannelsPerFrame)
                meta.audioSampleRate = asbd.mSampleRate
            }
        }

        meta.timecode = readStartTimecode(asset: asset)

        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                let keyString = (item.key as? String) ?? item.identifier?.rawValue ?? ""
                let lower = keyString.lowercased()
                if meta.cameraModel == nil, lower.contains("model") || item.commonKey == .commonKeyMake {
                    meta.cameraModel = item.stringValue
                }
                if meta.reelName == nil, lower.contains("reel") {
                    meta.reelName = item.stringValue
                }
            }
        }

        return meta.isEmpty ? nil : meta
    }

    /// Mapare FourCC -> nume lizibil, pentru codecurile intalnite frecvent
    /// pe platou; orice altceva ramane afisat ca FourCC brut (mai util
    /// decat "necunoscut" pentru un DIT care recunoaste codul).
    private static func codecName(for desc: CMFormatDescription) -> String {
        let type = CMFormatDescriptionGetMediaSubType(desc)
        switch type {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes422HQ: return "ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422LT: return "ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy: return "ProRes 422 Proxy"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatAppleLossless: return "ALAC"
        default:
            let be = type.bigEndian
            let bytes: [UInt8] = [UInt8((be >> 24) & 0xFF), UInt8((be >> 16) & 0xFF), UInt8((be >> 8) & 0xFF), UInt8(be & 0xFF)]
            if let s = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
            return "necunoscut"
        }
    }

    /// Citeste primul esantion al track-ului de timecode QuickTime (format
    /// "tc32", per specificatia QuickTime File Format): un intreg pe 32
    /// biti, bitul cel mai semnificativ = flag "negativ", urmatorii 7 biti
    /// rezervati, restul de 24 biti = numarul de cadre de la origine.
    /// `CMTimeCodeFormatDescriptionGetFrameQuanta` da cadrele/secunda
    /// folosite pentru a converti in HH:MM:SS:FF — NU se presupune un fps
    /// extern, se citeste direct din descrierea formatului track-ului.
    private static func readStartTimecode(asset: AVURLAsset) -> String? {
        guard let track = asset.tracks(withMediaType: .timecode).first,
              let formatDesc = track.formatDescriptions.first else { return nil }
        let desc = formatDesc as! CMFormatDescription
        let quanta = CMTimeCodeFormatDescriptionGetFrameQuanta(desc)
        guard quanta > 0 else { return nil }

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        // [FIX REAL, verificat cu un clip .mov generat de ffmpeg cu
        // -timecode]: primul "esantion" al unui track tmcd e adesea un
        // marker gol de tip "edit boundary" (numSamples=0, dataBuffer=nil)
        // — nu conține timecode-ul real. Continuăm până la primul eșantion
        // cu date efective, plafonat (un track de timecode are tipic 1-2
        // eșantioane în total, nu mii — plafonul e doar o siguranță).
        var dataBuffer: CMBlockBuffer?
        for _ in 0..<5 {
            guard reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() else { break }
            if let buffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                dataBuffer = buffer
                break
            }
        }
        guard let dataBuffer else { return nil }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                                  totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let ptr = dataPointer, totalLength >= 4 else { return nil }
        let raw = ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { bytes in
            UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }
        let frameNumber = Int(raw & 0x00FF_FFFF)
        let fps = Int(quanta)
        guard fps > 0 else { return nil }
        let totalSeconds = frameNumber / fps
        let frame = frameNumber % fps
        return String(format: "%02d:%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60, frame)
    }

    /// Thumbnail real (QLThumbnailGenerator) — folosit ATÂT de raportul
    /// HTML (`ProductionMeta.swift`, deja existent) CÂT ȘI de raportul PDF
    /// nou (M4). Extras aici ca sursă unică, ca să nu diveargă cele două.
    static func thumbnailImage(path: String, size: CGSize = CGSize(width: 320, height: 180)) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path),
                                                     size: size, scale: 2,
                                                     representationTypes: .thumbnail)
        let semaphore = DispatchSemaphore(value: 0)
        var image: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            defer { semaphore.signal() }
            guard let representation else { return }
            image = NSImage(cgImage: representation.cgImage, size: size)
        }
        _ = semaphore.wait(timeout: .now() + 3)
        return image
    }
}
