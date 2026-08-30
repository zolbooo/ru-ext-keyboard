import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "keyboard")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.blue)

                VStack(spacing: 10) {
                    Text("Русская+")
                        .font(.largeTitle.bold())
                    Text("Русская клавиатура с буквами ө, ү и символом ₮")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    instruction(1, "Откройте Настройки → Основные → Клавиатура")
                    instruction(2, "Выберите «Клавиатуры» и «Новые клавиатуры»")
                    instruction(3, "Добавьте «Русская+»")
                    instruction(4, "Включите «Полный доступ», чтобы работала вибрация")
                    instruction(5, "Удерживайте о, у или ₽, чтобы ввести ө, ү или ₮")
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("Клавиатура")
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue, in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
