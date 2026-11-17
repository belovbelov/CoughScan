import SwiftUI
import UIKit
import Charts

// =================== АНАЛИЗ ===================
enum AnalysisPeriod: Int, CaseIterable, Identifiable {
    case week = 7, month = 30
    var id: Int { rawValue }
    var title: String { self == .week ? "7 дней" : "30 дней" }
}

struct AnalysisScreen: View {
    @State private var period: AnalysisPeriod = .week
    @State private var periodStats: PeriodStatistics?
    @State private var exportError: String?

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.s),
                           GridItem(.flexible(), spacing: DS.Spacing.s)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    Picker("Период", selection: $period) {
                        ForEach(AnalysisPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let s = periodStats, !s.dailyStats.isEmpty {
                        content(for: s)
                    } else {
                        EmptyCardState(systemImage: "chart.bar.xaxis",
                                       title: "Пока нет данных",
                                       message: "Запустите мониторинг — здесь появятся графики и тренды за выбранный период.")
                            .card()
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.xl)
                .animation(.smooth, value: period)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Анализ")
            .toolbar {
                if let s = periodStats, !s.dailyStats.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: exportCSV) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Экспорт в CSV")
                    }
                }
            }
            .onAppear(perform: refreshStats)
            .onChange(of: period) { refreshStats() }
            .onReceive(NotificationCenter.default.publisher(for: CoughStorage.didChange)) { _ in refreshStats() }
            .alert("Не удалось экспортировать", isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    @ViewBuilder
    private func content(for s: PeriodStatistics) -> some View {
        // Итог периода
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Всего за \(period.title.lowercased())")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text("\(s.totalCoughs)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(pluralRu(s.totalCoughs, "кашель", "кашля", "кашлей"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(s.startDate) — \(s.endDate)")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            DailyCoughChart(days: filledDays(from: s))
                .frame(height: 180)
                .padding(.top, DS.Spacing.s)
        }
        .card(padding: DS.Spacing.l)

        // Метрики
        LazyVGrid(columns: columns, spacing: DS.Spacing.s) {
            MetricTile(icon: "calendar.day.timeline.left",
                       value: String(format: "%.1f", s.getCoughsPerDay()),
                       label: "В среднем в день", tint: .cough)
            MetricTile(icon: "clock.fill", value: s.monitoringTimeFormatted,
                       label: "Мониторинг", tint: .metricAmber)
            MetricTile(icon: "waveform.path", value: "\(s.totalRecordings)",
                       label: "Фрагментов", tint: .metricBlue)
            MetricTile(icon: "percent", value: "\(Int(s.avgProbability * 100))%",
                       label: "Уверенность модели", tint: .metricViolet)
        }

        // Распределение по часам
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            SectionHeader(title: "Время суток",
                          subtitle: s.totalCoughs > 0 ? "Чаще всего около \(s.getPeakHour().0)" : "Кашель не зафиксирован")
            HourlyChartView(hourlyCoughs: (0..<24).map { s.hourlyCoughs[$0] ?? 0 }, height: 160)
            DayPartBreakdown(hourly: (0..<24).map { s.hourlyCoughs[$0] ?? 0 })
        }
        .card(padding: DS.Spacing.l)

        // Экспорт
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                IconBadge(systemName: "doc.text.fill", tint: .brand, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Отчёт для врача").font(.headline)
                    Text("CSV с данными пациента, статистикой по дням и часам")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: exportCSV) {
                Label("Экспортировать CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)
            .padding(.top, DS.Spacing.xxs)
        }
        .card(padding: DS.Spacing.l)
    }

    /// Все дни периода, включая дни без данных, — чтобы график не «прыгал».
    private func filledDays(from s: PeriodStatistics) -> [DayPoint] {
        let byCode = Dictionary(s.dailyStats.map { ($0.dateCode, $0) }, uniquingKeysWith: { a, _ in a })
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<period.rawValue).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let code = CoughStorage.dateCode(from: Int64(date.timeIntervalSince1970 * 1000))
            let day = byCode[code]
            return DayPoint(date: date, coughs: day?.totalCoughs ?? 0, hasData: day?.hasData ?? false)
        }
    }

    private func refreshStats() {
        let start = Calendar.current.date(byAdding: .day, value: -(period.rawValue - 1), to: Date()) ?? Date()
        let stats = CoughStorage.shared.getPeriodStats(
            startDateCode: CoughStorage.dateCode(from: Int64(start.timeIntervalSince1970 * 1000)),
            endDateCode: CoughStorage.currentDateCode())
        withAnimation(.smooth) { periodStats = stats }
    }

    private func exportCSV() {
        guard let stats = periodStats else { return }
        let patient = CoughStorage.shared.patientInfo
        let csvString = stats.toCSV(patient: patient)

        let fileName = "Кашель_\(UUID().uuidString).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [path], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               var top = windowScene.keyWindow?.rootViewController ?? windowScene.windows.first?.rootViewController {
                while let presented = top.presentedViewController { top = presented }
                activityVC.popoverPresentationController?.sourceView = top.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                activityVC.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: path) }
                top.present(activityVC, animated: true)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Графики

struct DayPoint: Identifiable {
    let date: Date
    let coughs: Int
    let hasData: Bool
    var id: Date { date }
}

struct DailyCoughChart: View {
    let days: [DayPoint]
    @State private var selected: Date?

    private var selectedPoint: DayPoint? {
        guard let selected else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    private var isLong: Bool { days.count > 10 }

    var body: some View {
        Chart {
            bars
            selectionRule
        }
        .chartXSelection(value: $selected)
        .chartXAxis { xAxis }
        .chartYAxis { ChartStyle.yAxis }
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
        .accessibilityLabel("Кашель по дням")
    }

    @ChartContentBuilder
    private var bars: some ChartContent {
        let highlighted = selectedPoint?.id
        let radius: CGFloat = isLong ? 3 : 6
        ForEach(days) { (day: DayPoint) in
            let dimmed = highlighted != nil && highlighted != day.id
            BarMark(x: .value("День", day.date, unit: .day),
                    y: .value("Кашлей", day.coughs))
                .foregroundStyle(Color.cough.gradient)
                .opacity(dimmed ? 0.35 : 1)
                .cornerRadius(radius)
        }
    }

    @ChartContentBuilder
    private var selectionRule: some ChartContent {
        if let p = selectedPoint {
            RuleMark(x: .value("День", p.date, unit: .day))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .annotation(position: .top, spacing: 4,
                            overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled)) {
                    SelectionCallout(value: p.coughs, date: p.date)
                }
        }
    }

    private var xAxis: some AxisContent {
        let format: Date.FormatStyle = isLong ? .dateTime.locale(.app).day().month(.abbreviated) : .dateTime.locale(.app).weekday(.abbreviated)
        return AxisMarks(values: .stride(by: .day, count: isLong ? 7 : 1)) { _ in
            AxisValueLabel(format: format, centered: true)
                .foregroundStyle(Color.secondary)
        }
    }
}

private struct SelectionCallout: View {
    let value: Int
    let date: Date

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline).monospacedDigit()
            Text(date.formatted(.dateTime.locale(.app).day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfaceRaised, in: .rect(cornerRadius: 10, style: .continuous))
    }
}

enum ChartStyle {
    static var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.4))
            AxisValueLabel()
                .foregroundStyle(Color.secondary)
        }
    }
}

struct HourlyChartView: View {
    let hourlyCoughs: [Int]
    var height: CGFloat = 150

    private struct HourPoint: Identifiable {
        let hour: String
        let count: Int
        let isPeak: Bool
        var id: String { hour }
    }

    private var points: [HourPoint] {
        let peak = hourlyCoughs.max() ?? 0
        return hourlyCoughs.enumerated().map {
            HourPoint(hour: String(format: "%02d", $0.offset), count: $0.element,
                      isPeak: peak > 0 && $0.element == peak)
        }
    }

    var body: some View {
        Chart(points) { (point: HourPoint) in
            BarMark(x: .value("Час", point.hour),
                    y: .value("Кашлей", point.count),
                    width: .ratio(0.7))
                .foregroundStyle(Color.cough.opacity(point.isPeak ? 1 : 0.45).gradient)
                .cornerRadius(3)
        }
        .chartXAxis { xAxis }
        .chartYAxis { ChartStyle.yAxis }
        .frame(height: height)
        .accessibilityLabel("Кашель по часам")
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: ["00", "06", "12", "18"]) { (value: AxisValue) in
            AxisValueLabel(anchor: .topLeading) {
                if let h = value.as(String.self) {
                    Text("\(h):00")
                }
            }
            .foregroundStyle(Color.secondary)
        }
    }
}

/// Доли кашля по частям суток: ночь, утро, день, вечер.
struct DayPartBreakdown: View {
    let hourly: [Int]

    private var parts: [(String, String, Int)] {
        func sum(_ r: Range<Int>) -> Int { r.reduce(0) { $0 + hourly[$1] } }
        return [("Ночь", "moon.stars.fill", sum(0..<6)),
                ("Утро", "sunrise.fill", sum(6..<12)),
                ("День", "sun.max.fill", sum(12..<18)),
                ("Вечер", "sunset.fill", sum(18..<24))]
    }

    var body: some View {
        let total = max(1, hourly.reduce(0, +))
        HStack(spacing: DS.Spacing.xs) {
            ForEach(parts, id: \.0) { part in
                let (name, icon, value) = part
                VStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: icon)
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                    Text("\(Int((Double(value) / Double(total) * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.s)
                .background(Color.surfaceRaised, in: .rect(cornerRadius: DS.Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
