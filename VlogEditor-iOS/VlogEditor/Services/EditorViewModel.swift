import SwiftUI
import AVFoundation
import PhotosUI

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [Clip] = [] { didSet { scheduleRebuild() } }
    @Published var music: MusicTrack? { didSet { scheduleRebuild() } }
    @Published var aspect: AspectOption = .vertical { didSet { scheduleRebuild() } }
    @Published var selectedID: Clip.ID?
    @Published var player = AVPlayer()

    @Published var isBusy = false
    @Published var busyMessage = ""
    @Published var exportProgress: Float = 0
    @Published var message: String?

    private var rebuildTask: Task<Void, Never>?

    var selectedIndex: Int? { clips.firstIndex { $0.id == selectedID } }
    var totalDuration: Double { clips.reduce(0) { $0 + $1.length } }

    // MARK: - Importar

    func importVideos(_ items: [PhotosPickerItem]) async {
        setBusy("Importando…")
        defer { isBusy = false }
        for item in items {
            do {
                guard let picked = try await item.loadTransferable(type: PickedVideo.self) else { continue }
                let asset = AVURLAsset(url: picked.url)
                let duration = try await asset.load(.duration).seconds
                var clip = Clip(url: picked.url, duration: duration, end: duration)
                clip.thumbnail = await thumbnail(for: asset)
                clips.append(clip)
                selectedID = selectedID ?? clip.id
            } catch {
                message = "No se pudo importar un video: \(error.localizedDescription)"
            }
        }
    }

    func importMusic(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: dest)
            music = MusicTrack(url: dest, name: url.deletingPathExtension().lastPathComponent)
        } catch {
            message = "No se pudo importar la música: \(error.localizedDescription)"
        }
    }

    private func thumbnail(for asset: AVURLAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let cg = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Edición de clips

    func setStart(_ value: Double, for id: Clip.ID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].start = min(max(0, value), clips[i].end - 0.2)
    }

    func setEnd(_ value: Double, for id: Clip.ID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].end = max(min(clips[i].duration, value), clips[i].start + 0.2)
    }

    func setVolume(_ value: Float, for id: Clip.ID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].volume = value
    }

    func delete(_ id: Clip.ID) {
        clips.removeAll { $0.id == id }
        if selectedID == id { selectedID = clips.first?.id }
    }

    func move(_ id: Clip.ID, by offset: Int) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard clips.indices.contains(j) else { return }
        clips.swapAt(i, j)
    }

    /// Divide el clip seleccionado en el punto indicado (segundos del archivo original).
    func split(_ id: Clip.ID, at time: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[i]
        guard time > clip.start + 0.2, time < clip.end - 0.2 else { return }
        var first = clip
        first.end = time
        let second = Clip(url: clip.url, duration: clip.duration, start: time, end: clip.end, volume: clip.volume, thumbnail: clip.thumbnail)
        clips.replaceSubrange(i...i, with: [first, second])
    }

    // MARK: - Cortes automáticos

    /// Quita los silencios de un clip (o de todos si `id` es nil), dividiéndolos en los tramos con voz.
    func autoCut(_ id: Clip.ID? = nil) async {
        setBusy("Detectando silencios…")
        defer { isBusy = false }
        var result: [Clip] = []
        var removed = 0.0
        for clip in clips {
            guard id == nil || clip.id == id else { result.append(clip); continue }
            do {
                let ranges = try await SilenceDetector.activeRanges(url: clip.url, start: clip.start, end: clip.end)
                guard !ranges.isEmpty else { result.append(clip); continue }   // todo silencio: no tocar
                for range in ranges where range.upperBound - range.lowerBound > 0.2 {
                    result.append(Clip(url: clip.url, duration: clip.duration, start: range.lowerBound,
                                       end: range.upperBound, volume: clip.volume, thumbnail: clip.thumbnail))
                }
                removed += clip.length - ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            } catch {
                message = "No se pudo analizar el audio: \(error.localizedDescription)"
                result.append(clip)
            }
        }
        clips = result
        selectedID = clips.first?.id
        message = String(format: "Listo: se quitaron %.1f s de silencio.", max(removed, 0))
    }

    // MARK: - Vista previa

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let clips = clips, music = music, aspect = aspect
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)   // agrupar cambios rápidos (sliders)
            guard !Task.isCancelled else { return }
            guard !clips.isEmpty else { player.replaceCurrentItem(with: nil); return }
            do {
                let result = try await CompositionBuilder.build(clips: clips, music: music, aspect: aspect)
                guard !Task.isCancelled else { return }
                let time = player.currentTime()
                player.replaceCurrentItem(with: result.playerItem())
                await player.seek(to: time)
            } catch {
                message = "Error al preparar la vista previa: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Exportar

    func exportToPhotos() async {
        setBusy("Exportando…")
        exportProgress = 0
        defer { isBusy = false }
        do {
            let result = try await CompositionBuilder.build(clips: clips, music: music, aspect: aspect)
            let url = try await CompositionBuilder.export(result) { [weak self] value in
                Task { @MainActor in self?.exportProgress = value }
            }
            try await CompositionBuilder.saveToPhotos(url)
            message = "¡Vlog guardado en tu galería!"
        } catch {
            message = "No se pudo exportar: \(error.localizedDescription)"
        }
    }

    private func setBusy(_ text: String) {
        busyMessage = text
        isBusy = true
    }
}
