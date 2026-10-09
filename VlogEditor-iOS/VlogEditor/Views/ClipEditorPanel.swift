import SwiftUI

/// Controles del clip seleccionado: recorte, volumen, dividir, cortes automáticos, mover y borrar.
struct ClipEditorPanel: View {
    @ObservedObject var vm: EditorViewModel
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledSlider("Inicio", value: Binding(
                get: { clip.start }, set: { vm.setStart($0, for: clip.id) }
            ), range: 0...clip.duration, text: format(clip.start))

            labeledSlider("Final", value: Binding(
                get: { clip.end }, set: { vm.setEnd($0, for: clip.id) }
            ), range: 0...clip.duration, text: format(clip.end))

            HStack {
                Image(systemName: "speaker.wave.2.fill")
                Slider(value: Binding(
                    get: { Double(clip.volume) }, set: { vm.setVolume(Float($0), for: clip.id) }
                ), in: 0...2)
                Text("\(Int(clip.volume * 100))%").font(.caption).monospacedDigit().frame(width: 44)
            }

            HStack {
                Button { Task { await vm.autoCut(clip.id) } } label: {
                    Label("Cortar silencios", systemImage: "scissors")
                }
                Button {
                    vm.split(clip.id, at: (clip.start + clip.end) / 2)
                } label: {
                    Label("Dividir", systemImage: "square.split.2x1")
                }
                Spacer()
                Button { vm.move(clip.id, by: -1) } label: { Image(systemName: "arrow.left") }
                Button { vm.move(clip.id, by: 1) } label: { Image(systemName: "arrow.right") }
                Button(role: .destructive) { vm.delete(clip.id) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.bordered)
            .font(.footnote)

            if vm.clips.count > 1 {
                Button { Task { await vm.autoCut() } } label: {
                    Label("Cortar silencios en todos los clips", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
            Text(text).font(.caption).monospacedDigit().frame(width: 50)
        }
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
