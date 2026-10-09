import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    @StateObject private var vm = EditorViewModel()
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showMusicImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                preview
                clipStrip
                if let index = vm.selectedIndex {
                    ClipEditorPanel(vm: vm, clip: vm.clips[index])
                }
                musicRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .navigationTitle("Vlog Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Formato", selection: $vm.aspect) {
                        ForEach(AspectOption.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exportar") { Task { await vm.exportToPhotos() } }
                        .disabled(vm.clips.isEmpty || vm.isBusy)
                }
            }
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await vm.importVideos(items)
                pickedItems = []
            }
        }
        .fileImporter(isPresented: $showMusicImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { vm.importMusic(from: url) }
        }
        .overlay { if vm.isBusy { busyOverlay } }
        .alert("Aviso", isPresented: Binding(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.message ?? "")
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if vm.clips.isEmpty {
                Text("Agrega videos para empezar")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VideoPlayer(player: vm.player)
            }
        }
        .aspectRatio(vm.aspect == .vertical ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
        .frame(maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var clipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickedItems, matching: .videos) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                        Text("Video").font(.caption)
                    }
                    .frame(width: 64, height: 64)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(vm.clips) { clip in
                    ClipThumb(clip: clip, selected: clip.id == vm.selectedID)
                        .onTapGesture { vm.selectedID = clip.id }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var musicRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(vm.music?.name ?? "Sin música", systemImage: "music.note")
                    .lineLimit(1)
                Spacer()
                Button(vm.music == nil ? "Agregar música" : "Cambiar") { showMusicImporter = true }
                if vm.music != nil {
                    Button(role: .destructive) { vm.music = nil } label: { Image(systemName: "trash") }
                }
            }
            if vm.music != nil {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(
                        get: { Double(vm.music?.volume ?? 0) },
                        set: { vm.music?.volume = Float($0) }
                    ), in: 0...1)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(vm.busyMessage)
                if vm.busyMessage == "Exportando…" {
                    ProgressView(value: vm.exportProgress).frame(width: 160)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ClipThumb: View {
    let clip: Clip
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = clip.thumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray
                }
            }
            .frame(width: 64, height: 64)
            .clipped()

            Text(String(format: "%.1fs", clip.length))
                .font(.system(size: 10, weight: .bold))
                .padding(2)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
    }
}
