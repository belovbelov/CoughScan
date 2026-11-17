import SwiftUI

// =================== КАЛЕНДАРЬ ===================
struct CalendarScreen: View {
    @State private var currentMonth = Date()
    @State private var selectedDateCode = CoughStorage.currentDateCode()
    @State private var monthSummary: [Int: Int] = [:]
    @State private var dailyStats: DailyStatistics?
    @State private var slideEdge: Edge = .trailing

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Понедельник
        return cal
    }()

    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    monthCard

                    if let stats = dailyStats {
                        DailyDetailsView(stats: stats)
                            .id(stats.dateCode)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.xl)
                .animation(.smooth, value: selectedDateCode)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Календарь")
            .toolbar {
                if !isCurrentMonth || selectedDateCode != CoughStorage.currentDateCode() {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сегодня", action: goToToday)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedDateCode)
            .onAppear { updateData() }
            .onReceive(NotificationCenter.default.publisher(for: CoughStorage.didChange)) { _ in updateData() }
        }
    }

    // MARK: Month card

    private var monthCard: some View {
        VStack(spacing: DS.Spacing.m) {
            HStack {
                Text(currentMonth.formatted(.dateTime.locale(.app).month(.wide).year()).capitalizedFirst)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: DS.Spacing.xs) {
                    monthButton("chevron.left", label: "Предыдущий месяц") { changeMonth(-1) }
                    monthButton("chevron.right", label: "Следующий месяц") { changeMonth(1) }
                }
            }

            VStack(spacing: DS.Spacing.xs) {
                LazyVGrid(columns: grid, spacing: 6) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                        Text(day)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(index >= 5 ? Color.cough.opacity(0.8) : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: grid, spacing: 6) {
                    ForEach(Array(buildDaysArray().enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .id(monthKey)
                .transition(.asymmetric(insertion: .move(edge: slideEdge).combined(with: .opacity),
                                        removal: .opacity))
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        changeMonth(value.translation.width < 0 ? 1 : -1)
                    }
            )

            HeatLegend()
        }
        .card(padding: DS.Spacing.m)
        .clipped()
    }

    private func monthButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color.brand.opacity(0.12), in: .circle)
        }
        .accessibilityLabel(label)
    }

    private var maxCoughs: Int { max(1, monthSummary.values.max() ?? 0) }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let dateCode = getDateCode(for: day)
        let coughs = monthSummary[day]
        let isSelected = dateCode == selectedDateCode
        let isToday = dateCode == CoughStorage.currentDateCode()
        let isFuture = dateCode > CoughStorage.currentDateCode()
        let intensity = Double(coughs ?? 0) / Double(maxCoughs)

        Button {
            selectedDateCode = dateCode
            dailyStats = CoughStorage.shared.getDailyStats(dateCode: dateCode)
        } label: {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.callout.weight(isToday || isSelected ? .bold : .medium))
                    .monospacedDigit()
                if let coughs, coughs > 0 {
                    Text("\(coughs)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.cough)
                } else if coughs != nil {
                    Circle().fill(isSelected ? Color.white.opacity(0.8) : Color.brand).frame(width: 4, height: 4)
                        .padding(.vertical, 3)
                }
            }
            .foregroundStyle(isSelected ? .white : (isFuture ? Color.secondary.opacity(0.5) : Color.primary))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.brand.gradient)
                          : (coughs ?? 0) > 0 ? AnyShapeStyle(Color.cough.opacity(0.10 + 0.40 * intensity))
                          : AnyShapeStyle(Color.clear))
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .strokeBorder(Color.brand, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel(day: day, coughs: coughs, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(day: Int, coughs: Int?, isToday: Bool) -> String {
        var parts = ["\(day)"]
        if isToday { parts.append("сегодня") }
        if let coughs { parts.append("\(coughs) \(pluralRu(coughs, "кашель", "кашля", "кашлей"))") }
        else { parts.append("нет данных") }
        return parts.joined(separator: ", ")
    }

    // MARK: Data

    private var monthKey: Int {
        let c = calendar.dateComponents([.year, .month], from: currentMonth)
        return (c.year ?? 0) * 100 + (c.month ?? 0)
    }

    private var isCurrentMonth: Bool { calendar.isDate(currentMonth, equalTo: Date(), toGranularity: .month) }

    func updateData() {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        monthSummary = CoughStorage.shared.getMonthSummary(year: comps.year ?? 2024, month: comps.month ?? 1)
        dailyStats = CoughStorage.shared.getDailyStats(dateCode: selectedDateCode)
    }

    func changeMonth(_ offset: Int) {
        slideEdge = offset > 0 ? .trailing : .leading
        withAnimation(.smooth(duration: 0.3)) {
            currentMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth) ?? currentMonth
            updateData()
        }
    }

    private func goToToday() {
        slideEdge = currentMonth > Date() ? .leading : .trailing
        withAnimation(.smooth(duration: 0.3)) {
            currentMonth = Date()
            selectedDateCode = CoughStorage.currentDateCode()
            updateData()
        }
    }

    func buildDaysArray() -> [Int?] {
        let range = calendar.range(of: .day, in: .month, for: currentMonth)
        let daysInMonth = range?.count ?? 30
        var days: [Int?] = Array(repeating: nil, count: getFirstDayOffset())
        for day in 1...daysInMonth { days.append(day) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    func getFirstDayOffset() -> Int {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        guard let firstOfMonth = calendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: 1, hour: 12)) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday + 5) % 7 // Пн=0, Вс=6
    }

    func getDateCode(for day: Int) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        return (comps.year ?? 0) * 10000 + (comps.month ?? 0) * 100 + day
    }
}

// MARK: - Легенда тепловой карты

private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            HStack(spacing: 4) {
                Circle().fill(Color.brand).frame(width: 5, height: 5)
                Text("есть запись")
            }
            Spacer()
            Text("меньше")
            HStack(spacing: 3) {
                ForEach([0.12, 0.25, 0.38, 0.5], id: \.self) { o in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.cough.opacity(o))
                        .frame(width: 12, height: 12)
                }
            }
            Text("больше")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

// MARK: - Детали дня

struct DailyDetailsView: View {
    let stats: DailyStatistics

    private var title: String {
        guard let date = Date(dateCode: stats.dateCode) else { return stats.dateString }
        if Calendar.current.isDateInToday(date) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.locale(.app).weekday(.wide).day().month(.wide)).capitalizedFirst
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            SectionHeader(title: title,
                          subtitle: stats.hasData ? "Мониторинг \(stats.monitoringTimeFormatted)" : nil)

            if stats.hasData {
                HStack(spacing: 0) {
                    statColumn(value: "\(stats.totalCoughs)",
                               label: pluralRu(stats.totalCoughs, "кашель", "кашля", "кашлей"),
                               tint: .cough)
                    Divider().frame(height: 36)
                    statColumn(value: stats.totalCoughs > 0 ? stats.getCoughsPerHourDisplay() : "—",
                               label: "в час", tint: .metricViolet)
                    Divider().frame(height: 36)
                    statColumn(value: "\(stats.totalRecordings)", label: "фрагментов", tint: .metricBlue)
                }
                .padding(.vertical, DS.Spacing.s)
                .background(Color.surfaceRaised, in: .rect(cornerRadius: DS.Radius.medium, style: .continuous))

                if stats.totalCoughs > 0 {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        HStack {
                            Text("По часам").font(.headline)
                            Spacer()
                            let peak = stats.getPeakHour()
                            Label("пик \(peak.0)", systemImage: "flame.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HourlyChartView(hourlyCoughs: stats.hourlyCoughs, height: 140)
                    }

                    Label("Средняя уверенность модели \(Int(stats.avgProbability * 100))%",
                          systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Кашель не зафиксирован", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.success)
                }
            } else {
                EmptyCardState(systemImage: "calendar.badge.clock",
                               title: "Нет данных",
                               message: "В этот день мониторинг не проводился.")
                    .padding(.vertical, -DS.Spacing.s)
            }
        }
        .card(padding: DS.Spacing.l)
    }

    private func statColumn(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
