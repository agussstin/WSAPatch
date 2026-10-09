import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

/// Un clip de video en la línea de tiempo. `start`/`end` son el recorte dentro del archivo original.
struct Clip: Identifiable {
    let id = UUID()
    let url: URL
    let duration: Double
    var start: Double = 0
    var end: Double
    var volume: Float = 1
    var thumbnail: UIImage?

    var length: Double { max(end - start, 0) }
}

struct MusicTrack {
    let url: URL
    let name: String
    var volume: Float = 0.5
}

enum AspectOption: String, CaseIterable, Identifiable {
    case vertical = "9:16"
    case horizontal = "16:9"

    var id: String { rawValue }

    var renderSize: CGSize {
        switch self {
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .horizontal: return CGSize(width: 1920, height: 1080)
        }
    }
}

/// Permite recibir videos desde PhotosPicker copiándolos a un archivo temporal propio.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}
