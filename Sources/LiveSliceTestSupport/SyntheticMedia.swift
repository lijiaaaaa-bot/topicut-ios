// Why: guard 05 forbids media files in git, yet the ASR and render tests must exercise real
// AVFoundation/Speech paths. This target synthesizes throwaway media at test time (solid-colour
// video, a sine tone, macOS `say` speech) so those tests stay real without committing binaries.

import AVFoundation
import CoreVideo
import Foundation

public enum SyntheticMediaError: Error, Equatable, Sendable {
    case pixelBufferPoolUnavailable
    case pixelBufferCreationFailed(CVReturn)
    case writerFailed(String)
    case sayFailed(status: Int32, output: String)
    case unsupportedPlatform(String)
}

public enum SyntheticMedia {
    public struct RGB: Sendable, Equatable {
        public let red: Double, green: Double, blue: Double
        public init(red: Double, green: Double, blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }
        public static let deepBlue = RGB(red: 0.05, green: 0.1, blue: 0.6)
    }

    /// Writes an H.264 MP4 of solid-colour frames (no audio). Frames are `fps` per second.
    public static func makeVideo(
        at url: URL, size: CGSize, durationSec: Double, fps: Int32 = 30, color: RGB = .deepBlue
    ) async throws {
        try removeIfPresent(url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw SyntheticMediaError.writerFailed(String(describing: writer.error)) }
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int((durationSec * Double(fps)).rounded())
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let buffer = try makePixelBuffer(adaptor: adaptor, size: size, color: color)
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw SyntheticMediaError.writerFailed(String(describing: writer.error))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SyntheticMediaError.writerFailed(String(describing: writer.error)) }
    }

    private static func makePixelBuffer(
        adaptor: AVAssetWriterInputPixelBufferAdaptor, size: CGSize, color: RGB
    ) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw SyntheticMediaError.pixelBufferPoolUnavailable }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw SyntheticMediaError.pixelBufferCreationFailed(status) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw SyntheticMediaError.pixelBufferCreationFailed(kCVReturnInvalidPixelBufferAttributes)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixel: [UInt8] = [UInt8(color.blue * 255), UInt8(color.green * 255), UInt8(color.red * 255), 255]
        for row in 0..<Int(size.height) {
            let rowPointer = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for col in 0..<Int(size.width) {
                for channel in 0..<4 { rowPointer[col * 4 + channel] = pixel[channel] }
            }
        }
        return buffer
    }

    /// Writes an AAC `.m4a` containing a sine tone.
    public static func makeToneAudio(at url: URL, durationSec: Double, frequency: Double = 440, sampleRate: Double = 44_100) throws {
        try removeIfPresent(url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw SyntheticMediaError.writerFailed("AVAudioFormat unavailable")
        }
        let frames = AVAudioFrameCount(durationSec * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0]
        else { throw SyntheticMediaError.writerFailed("PCM buffer unavailable") }
        for index in 0..<Int(frames) {
            channel[index] = Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.3)
        }
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    /// Muxes a video file and an audio file into one MP4 (composition export). Audio may be shorter.
    public static func mux(video videoURL: URL, audio audioURL: URL, to outputURL: URL) async throws {
        try removeIfPresent(outputURL)
        let composition = AVMutableComposition()
        let video = AVURLAsset(url: videoURL)
        let audio = AVURLAsset(url: audioURL)
        guard let videoTrack = try await video.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audio.loadTracks(withMediaType: .audio).first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw SyntheticMediaError.writerFailed("missing tracks for mux") }
        let videoDuration = try await video.load(.duration)
        let audioDuration = try await audio.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration)), of: audioTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw SyntheticMediaError.writerFailed("export session unavailable")
        }
        try await session.export(to: outputURL, as: .mp4)
    }

    /// macOS only: synthesizes speech with `/usr/bin/say` into an `.m4a`. Tests use this for real ASR input.
    public static func makeSpeechAudio(text: String, voice: String, to url: URL) throws {
        #if os(macOS)
        try removeIfPresent(url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-o", url.path, "--file-format=m4af", text]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw SyntheticMediaError.sayFailed(status: process.terminationStatus, output: output)
        }
        #else
        throw SyntheticMediaError.unsupportedPlatform("say is only available on macOS")
        #endif
    }

    /// Deletes a previous output so writers never fail on "file exists". Absence is not an error.
    static func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// A fresh scratch directory under the system temp folder.
    public static func scratchDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "liveslice-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
