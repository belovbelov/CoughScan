import SwiftUI

// MARK: - Tokens
//
// Единая дизайн-система CoughScan. Все экраны берут цвета, отступы, радиусы
// и компоненты отсюда — так интерфейс выглядит цельным и легко меняется.

enum DS {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 26
    }
}

extension Color {
    /// Фирменный бирюзовый — спокойный «медицинский» акцент.
    static let brand = Color.accentColor
    static let brandDeep = Color(light: .init(red: 0.03, green: 0.45, blue: 0.47, alpha: 1),
                                 dark: .init(red: 0.20, green: 0.78, blue: 0.74, alpha: 1))
    /// Цвет событий кашля.
    static let cough = Color(light: .init(red: 0.93, green: 0.29, blue: 0.33, alpha: 1),
                             dark: .init(red: 1.00, green: 0.42, blue: 0.45, alpha: 1))
    static let recording = Color(light: .init(red: 0.90, green: 0.20, blue: 0.24, alpha: 1),
                                 dark: .init(red: 1.00, green: 0.30, blue: 0.33, alpha: 1))
    static let metricBlue = Color(light: .init(red: 0.18, green: 0.45, blue: 0.95, alpha: 1),
                                  dark: .init(red: 0.40, green: 0.62, blue: 1.00, alpha: 1))
    static let metricAmber = Color(light: .init(red: 0.88, green: 0.52, blue: 0.05, alpha: 1),
                                   dark: .init(red: 1.00, green: 0.70, blue: 0.25, alpha: 1))
    static let metricViolet = Color(light: .init(red: 0.48, green: 0.32, blue: 0.90, alpha: 1),
                                    dark: .init(red: 0.66, green: 0.55, blue: 1.00, alpha: 1))
    static let success = Color(light: .init(red: 0.12, green: 0.62, blue: 0.36, alpha: 1),
                               dark: .init(red: 0.30, green: 0.82, blue: 0.52, alpha: 1))

    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - Форматирование

func formatTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d ч %02d мин", h, m) }
    if m > 0 { return String(format: "%d мин %02d с", m, s) }
    return "\(s) с"
}

/// Таймер в виде 00:00:00 для живого счётчика сессии.
func formatClock(_ seconds: Int) -> String {
    String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
}

func pluralRu(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

extension Date {
    init?(dateCode: Int) {
        var comps = DateComponents()
        comps.year = dateCode / 10000
        comps.month = (dateCode / 100) % 100
        comps.day = dateCode % 100
        comps.hour = 12
        guard let date = Calendar.current.date(from: comps) else { return nil }
        self = date
    }
}

// MARK: - Карточка

struct CardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: DS.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

extension View {
    func card(padding: CGFloat = DS.Spacing.m) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Стандартный фон экрана с мягким фирменным свечением сверху.
    func screenBackground() -> some View {
        background {
            ZStack(alignment: .top) {
                Color.canvas
                LinearGradient(colors: [Color.brand.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 360)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Заголовок секции

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.Spacing.s)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Иконка в цветной подложке

struct IconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Плитка метрики

struct MetricTile: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            IconBadge(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .card(padding: DS.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Пилюля статуса

struct StatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, 7)
            .background(tint.opacity(0.13), in: .capsule)
            .lineLimit(1)
    }
}

// MARK: - Баннер

struct InlineBanner: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.m)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: DS.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Кнопки

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .brand
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                    .fill(tint.gradient)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(configuration.isPressed ? 0.22 : 0.13),
                        in: .rect(cornerRadius: DS.Radius.medium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(_ tint: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(_ tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}

// MARK: - Пустое состояние внутри карточки

struct EmptyCardState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

extension Locale {
    /// Интерфейс только на русском, поэтому даты всегда форматируем по-русски.
    static let app = Locale(identifier: "ru_RU")
}

extension String {
    /// «среда, 18 ноября» → «Среда, 18 ноября» (в отличие от `capitalized`, не трогает остальные слова).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
