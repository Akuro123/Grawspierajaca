import SwiftUI

/// Wspólny styl: paleta zgodna z grafiką gry, duże zaokrąglone elementy, czytelne czcionki.
enum Theme {
    static let ink = Color(red: 0.11, green: 0.08, blue: 0.19)
    static let orange = Color(red: 1.0, green: 0.54, blue: 0.24)
    static let teal = Color(red: 0.18, green: 0.77, blue: 0.71)
    static let indigo = Color(red: 0.24, green: 0.36, blue: 0.84)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let coral = Color(red: 1.0, green: 0.35, blue: 0.37)
    static let skyTop = Color(red: 0.43, green: 0.78, blue: 1.0)
    static let skyBottom = Color(red: 1.0, green: 0.95, blue: 0.77)
}

extension Font {
    static func game(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// Tło ekranów menu: niebo z delikatnymi chmurami.
struct SkyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.skyTop, Theme.skyBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { g in
                sprite("cloud").resizable().scaledToFit().frame(width: 190).opacity(0.85).position(x: g.size.width * 0.8, y: g.size.height * 0.12)
                sprite("cloud").resizable().scaledToFit().frame(width: 130).opacity(0.7).position(x: g.size.width * 0.15, y: g.size.height * 0.3)
            }
        }.ignoresSafeArea()
    }
}

struct GameButtonStyle: ButtonStyle {
    var color: Color = Theme.orange
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.game(compact ? 18 : 24))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: compact ? 52 : 68)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(color)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ink, lineWidth: 3))
                    .shadow(color: Theme.ink.opacity(0.35), radius: 0, y: configuration.isPressed ? 1 : 5)
            )
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, new in new }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.background)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.ink.opacity(0.12), lineWidth: 2)))
    }
}

struct StatTile: View {
    let value: String, label: String, symbol: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3.bold()).foregroundStyle(color)
            Text(value).font(.game(30)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.background))
        .accessibilityElement(children: .combine)
    }
}

/// Pasek informacji w HUD (moneta, poziom itp.) na grze.
struct HUDPill: View {
    let text: String, symbol: String, color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).monospacedDigit()
        }
        .font(.game(20)).foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Theme.ink.opacity(0.65)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
    }
}

func formatDuration(_ sec: Double) -> String {
    let t = Int(sec.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// Obraz z wygenerowanych sprite'ów (pliki luzem w pakiecie aplikacji).
func sprite(_ name: String) -> Image {
    if let ui = UIImage(named: name) { return Image(uiImage: ui) }
    return Image(systemName: "questionmark.square")
}
