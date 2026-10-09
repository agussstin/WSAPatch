import AVFoundation
import Photos

struct EditResult {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix

    func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }
}

enum CompositionBuilder {
    private static let timescale: CMTimeScale = 600

    static func build(clips: [Clip], music: MusicTrack?, aspect: AspectOption) async throws -> EditResult {
        let composition = AVMutableComposition()
        let renderSize = aspect.renderSize

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }

        let audioParams = AVMutableAudioMixInputParameters(track: audioTrack)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero

        for clip in clips where clip.length > 0.05 {
            let asset = AVURLAsset(url: clip.url)
            let range = CMTimeRange(
                start: CMTime(seconds: clip.start, preferredTimescale: timescale),
                duration: CMTime(seconds: clip.length, preferredTimescale: timescale)
            )

            guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            try videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)

            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack.insertTimeRange(range, of: srcAudio, at: cursor)
            }
            audioParams.setVolume(clip.volume, at: cursor)

            // Orientación + ajuste al tamaño final (con barras negras si no coincide la proporción).
            let natural = try await srcVideo.load(.naturalSize)
            let preferred = try await srcVideo.load(.preferredTransform)
            let bounds = CGRect(origin: .zero, size: natural).applying(preferred)
            let size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
            let scale = min(renderSize.width / size.width, renderSize.height / size.height)
            let transform = preferred
                .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(
                    translationX: (renderSize.width - size.width * scale) / 2,
                    y: (renderSize.height - size.height * scale) / 2
                ))

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(transform, at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = cursor + range.duration
        }

        guard !instructions.isEmpty else { throw CocoaError(.fileNoSuchFile) }

        var parameters = [audioParams]
        if let music, let params = try await addMusic(music, to: composition, total: cursor) {
            parameters.append(params)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters

        return EditResult(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// Añade la música en bucle hasta cubrir todo el video, con fade-out al final.
    private static func addMusic(_ music: MusicTrack, to composition: AVMutableComposition, total: CMTime) async throws -> AVMutableAudioMixInputParameters? {
        let asset = AVURLAsset(url: music.url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let musicDuration = try await asset.load(.duration)
        guard musicDuration.seconds > 0.1 else { return nil }

        var position = CMTime.zero
        while position < total {
            let remaining = total - position
            let length = min(musicDuration, remaining)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: position)
            position = position + length
        }

        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolume(music.volume, at: .zero)
        let fade = CMTime(seconds: min(1.5, total.seconds / 2), preferredTimescale: timescale)
        params.setVolumeRamp(fromStartVolume: music.volume, toEndVolume: 0, timeRange: CMTimeRange(start: total - fade, duration: fade))
        return params
    }

    // MARK: - Exportar

    static func export(_ result: EditResult, progress: @escaping (Float) -> Void) async throws -> URL {
        guard let session = AVAssetExportSession(asset: result.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlog-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = result.videoComposition
        session.audioMix = result.audioMix
        session.shouldOptimizeForNetworkUse = true

        let poller = Task {
            while !Task.isCancelled {
                progress(session.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { poller.cancel() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
        progress(1)
        return url
    }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CocoaError(.userCancelled) }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
