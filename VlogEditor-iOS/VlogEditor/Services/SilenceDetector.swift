import AVFoundation

/// Detecta los tramos con voz/sonido de un clip para hacer "cortes automáticos" (quitar silencios).
enum SilenceDetector {
    private static let sampleRate = 16_000.0
    private static let windowSeconds = 0.05

    /// Devuelve los rangos (en segundos del archivo original) que NO son silencio.
    static func activeRanges(
        url: URL,
        start: Double,
        end: Double,
        thresholdDB: Float = -35,
        minSilence: Double = 0.45,
        padding: Double = 0.08
    ) async throws -> [ClosedRange<Double>] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return [start...end]   // sin audio: no se puede detectar nada
        }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

        let windowSize = Int(sampleRate * windowSeconds)
        var loud: [Bool] = []
        var sumSquares = 0.0
        var count = 0

        func flushWindow() {
            let rms = (sumSquares / Double(max(count, 1))).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            loud.append(Float(db) > thresholdDB)
            sumSquares = 0
            count = 0
        }

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            data.withUnsafeBytes { raw in
                for sample in raw.bindMemory(to: Int16.self) {
                    let f = Double(sample) / 32768
                    sumSquares += f * f
                    count += 1
                    if count == windowSize { flushWindow() }
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        if count > 0 { flushWindow() }

        // Agrupar ventanas ruidosas, uniendo las separadas por silencios cortos.
        let maxGap = Int((minSilence / windowSeconds).rounded(.up))
        var runs: [(Int, Int)] = []   // [inicio, fin] inclusivo, en índices de ventana
        var i = 0
        while i < loud.count {
            if loud[i] {
                var last = i
                var j = i + 1
                while j < loud.count && j - last <= maxGap {
                    if loud[j] { last = j }
                    j += 1
                }
                runs.append((i, last))
                i = last + 1
            } else {
                i += 1
            }
        }

        return runs.map { run in
            let from = max(start, start + Double(run.0) * windowSeconds - padding)
            let to = min(end, start + Double(run.1 + 1) * windowSeconds + padding)
            return from...to
        }
    }
}
