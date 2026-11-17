import SwiftUI
import AVFoundation
import UIKit

// =================== МОНИТОРИНГ ===================
struct MonitoringScreen: View {
    @ObservedObject private var monitoring = MonitoringManager.shared
    @State private var todayStats = CoughStorage.shared.getTodayStats()
    @State private var showPermissionAlert = false
    @State private var showUploadConsent = false
    @AppStorage("audio_upload_consent") private var uploadConsent = false

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.s),
                           GridItem(.flexible(), spacing: DS.Spacing.s)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    heroCard

                    if let error = monitoring.errorMessage {
                        InlineBanner(systemImage: "exclamationmark.triangle.fill", text: error, tint: .metricAmber)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    statusRow
                    todaySection
                    disclaimer
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.xl)
                .animation(.snappy, value: monitoring.errorMessage)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Мониторинг")
            .sensoryFeedback(.impact(weight: .medium), trigger: monitoring.isMonitoring)
            .onReceive(NotificationCenter.default.publisher(for: CoughStorage.didChange)) { _ in
                withAnimation(.snappy) { todayStats = CoughStorage.shared.getTodayStats() }
            }
            .onAppear { todayStats = CoughStorage.shared.getTodayStats() }
            .sheet(isPresented: $showUploadConsent) {
                UploadConsentSheet {
                    uploadConsent = true
                    showUploadConsent = false
                    requestMicrophone()
                }
            }
            .alert("Нужен доступ к микрофону", isPresented: $showPermissionAlert) {
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Не сейчас", role: .cancel) {}
            } message: {
                Text("Разрешите CoughScan использовать микрофон в Настройках, чтобы распознавать кашель.")
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: DS.Spacing.l) {
            StatusPill(text: monitoring.isMonitoring ? "Идёт запись" : "Готов к записи",
                       systemImage: monitoring.isMonitoring ? "waveform" : "moon.zzz.fill",
                       tint: monitoring.isMonitoring ? .recording : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: monitoring.isMonitoring)
                .contentTransition(.opacity)

            RecordButton(isActive: monitoring.isMonitoring, action: toggleMonitoring)
                .padding(.vertical, DS.Spacing.xl)

            VStack(spacing: DS.Spacing.xxs) {
                Text(formatClock(monitoring.isMonitoring ? monitoring.monitoringTime : 0))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .foregroundStyle(.primary)
                    .opacity(monitoring.isMonitoring ? 1 : 0.3)
                    .accessibilityLabel("Длительность сессии \(formatTime(monitoring.monitoringTime))")
                Text(monitoring.isMonitoring
                     ? "Можно заблокировать экран — запись продолжится"
                     : "Нажмите, чтобы начать отслеживать кашель")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .card(padding: DS.Spacing.l)
        .animation(.smooth, value: monitoring.isMonitoring)
        .animation(.snappy, value: monitoring.monitoringTime)
    }

    // MARK: Status

    private var statusRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                if monitoring.hasInternet {
                    StatusPill(text: "Онлайн", systemImage: "wifi", tint: .success)
                } else {
                    StatusPill(text: "Нет сети", systemImage: "wifi.slash", tint: .metricAmber)
                }

                if monitoring.pendingQueueSize > 0 {
                    StatusPill(text: "В очереди: \(monitoring.pendingQueueSize)",
                               systemImage: "tray.full.fill", tint: .metricAmber)
                } else {
                    StatusPill(text: "Всё отправлено", systemImage: "checkmark.icloud.fill", tint: .success)
                }

                if let last = monitoring.lastResult {
                    StatusPill(text: last.coughDetected ? "Последний: кашель" : "Последний: тихо",
                               systemImage: last.coughDetected ? "lungs.fill" : "checkmark.circle.fill",
                               tint: last.coughDetected ? .cough : .secondary)
                }
            }
            .padding(.horizontal, DS.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -DS.Spacing.m)
        .animation(.snappy, value: monitoring.pendingQueueSize)
        .animation(.snappy, value: monitoring.hasInternet)
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionHeader(title: "Сегодня",
                          subtitle: Date().formatted(.dateTime.locale(.app).weekday(.wide).day().month(.wide)))

            LazyVGrid(columns: columns, spacing: DS.Spacing.s) {
                MetricTile(icon: "lungs.fill", value: "\(todayStats.totalCoughs)",
                           label: pluralRu(todayStats.totalCoughs, "Кашель", "Кашля", "Кашлей"),
                           tint: .cough)
                MetricTile(icon: "speedometer", value: todayStats.totalCoughs > 0 ? todayStats.getCoughsPerHourDisplay() : "—",
                           label: "В час", tint: .metricViolet)
                MetricTile(icon: "waveform.path", value: "\(todayStats.totalRecordings)",
                           label: "Фрагментов", tint: .metricBlue)
                MetricTile(icon: "clock.fill", value: formatTime(todayStats.monitoringSeconds),
                           label: "Мониторинг", tint: .metricAmber)
            }

            if todayStats.totalCoughs > 0 {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    HStack {
                        Text("Активность по часам").font(.headline)
                        Spacer()
                        let peak = todayStats.getPeakHour()
                        Text("пик в \(peak.0)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HourlyChartView(hourlyCoughs: todayStats.hourlyCoughs, height: 120)
                }
                .card()
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var disclaimer: some View {
        Label {
            Text("Звук записывается и отправляется на сервер для распознавания кашля. Результаты не являются медицинским диагнозом.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.xxs)
    }

    // MARK: Actions

    private func toggleMonitoring() {
        if monitoring.isMonitoring {
            monitoring.stop()
        } else if uploadConsent {
            requestMicrophone()
        } else {
            showUploadConsent = true
        }
    }

    private func requestMicrophone() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted { monitoring.start() }
                else { showPermissionAlert = true }
            }
        }
    }
}

// MARK: - Кнопка записи

struct RecordButton: View {
    let isActive: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { isActive ? .recording : .brand }
    private let size: CGFloat = 164

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive && !reduceMotion {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3, id: \.self) { i in
                                let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .stroke(tint.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(1.08 + phase * 0.3)
                                    .opacity(1 - phase)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Circle()
                    .fill(tint.opacity(0.14))
                    .scaleEffect(1.16)

                Circle()
                    .fill(tint.gradient)
                    .shadow(color: tint.opacity(0.45), radius: 22, y: 10)

                Circle()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
                    .padding(7)

                Image(systemName: isActive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(isActive ? "Остановить мониторинг" : "Запустить мониторинг")
        .accessibilityHint(isActive ? "Запись звука прекратится" : "Начнётся запись звука для распознавания кашля")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Согласие на отправку аудио

struct UploadConsentSheet: View {
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        IconBadge(systemName: "waveform.badge.mic", tint: .brand, size: 56)
                        Text("Отправка аудио")
                            .font(.largeTitle.weight(.bold))
                        Text("Перед первым запуском ознакомьтесь, как обрабатывается звук.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, DS.Spacing.xl)

                    VStack(alignment: .leading, spacing: DS.Spacing.l) {
                        ConsentRow(icon: "mic.fill", tint: .metricBlue,
                                   title: "Запись окружения",
                                   text: "Во время мониторинга записывается окружающий звук, включая возможную речь.")
                        ConsentRow(icon: "network", tint: .metricAmber,
                                   title: "Передача без шифрования",
                                   text: "Аудио отправляется на alexbrosoj-yam-134b.twc1.net по HTTP без шифрования.")
                        ConsentRow(icon: "trash.fill", tint: .brand,
                                   title: "Локальные фрагменты",
                                   text: "После успешного анализа локальные фрагменты удаляются; при ошибке остаются в очереди.")
                        ConsentRow(icon: "server.rack", tint: .cough,
                                   title: "Данные на сервере",
                                   text: "Данные на сервере этой кнопкой не удаляются.")
                    }
                }
                .padding(.horizontal, DS.Spacing.l)
            }

            VStack(spacing: DS.Spacing.xs) {
                Button("Согласен, начать", action: onAccept)
                    .buttonStyle(.primary)
                Button("Отмена") { dismiss() }
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .padding(DS.Spacing.l)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.large + 8)
    }
}

private struct ConsentRow: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            IconBadge(systemName: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
