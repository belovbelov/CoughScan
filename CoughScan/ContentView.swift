import SwiftUI

enum AppTab: Hashable {
    case monitoring, analysis, calendar, patient
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .monitoring

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Мониторинг", systemImage: "waveform", value: AppTab.monitoring) {
                MonitoringScreen()
            }

            Tab("Анализ", systemImage: "chart.bar.xaxis", value: AppTab.analysis) {
                AnalysisScreen()
            }

            Tab("Календарь", systemImage: "calendar", value: AppTab.calendar) {
                CalendarScreen()
            }

            Tab("Пациент", systemImage: "person.crop.circle", value: AppTab.patient) {
                PatientScreen()
            }
        }
        .tint(.brand)
        // Интерфейс полностью на русском — даты и дни недели тоже.
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

#Preview("Светлая") {
    ContentView()
        .environmentObject(MonitoringManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Тёмная") {
    ContentView()
        .environmentObject(MonitoringManager.shared)
        .preferredColorScheme(.dark)
}
