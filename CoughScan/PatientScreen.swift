import SwiftUI

// =================== ПАЦИЕНТ ===================
struct PatientScreen: View {
    @State private var patient: PatientInfo = CoughStorage.shared.patientInfo
    @State private var savedPatient: PatientInfo = CoughStorage.shared.patientInfo
    @State private var saveTick = 0
    @State private var justSaved = false
    @State private var showClearConfirm = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case lastName, firstName, middleName, notes }

    private var hasChanges: Bool {
        patient.lastName != savedPatient.lastName || patient.firstName != savedPatient.firstName
            || patient.middleName != savedPatient.middleName || patient.notes != savedPatient.notes
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    profileHeader
                    formCard
                    saveButton
                    privacyCard
                    dangerZone
                    footer
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Пациент")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focused = nil }
                }
            }
            .sensoryFeedback(.success, trigger: saveTick)
            .confirmationDialog("Удалить все данные?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive, action: clearAll)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это безвозвратно удалит всю статистику, историю, очередь и карточку пациента на этом устройстве.")
            }
        }
    }

    // MARK: Header

    private var initials: String {
        let letters = [patient.lastName, patient.firstName].compactMap { $0.trimmingCharacters(in: .whitespaces).first }
        return letters.isEmpty ? "" : String(letters).uppercased()
    }

    private var profileHeader: some View {
        HStack(spacing: DS.Spacing.m) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.brand, .brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(initials)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 68, height: 68)
            .shadow(color: Color.brand.opacity(0.35), radius: 12, y: 6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.isEmpty ? "Новый пациент" : patient.fullName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(patient.isEmpty ? "Заполните карточку — ФИО попадёт в отчёт для врача"
                                     : "Карточка хранится только на этом устройстве")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: DS.Spacing.l)
        .animation(.snappy, value: initials)
    }

    // MARK: Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("Данные")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, DS.Spacing.xxs)

            VStack(spacing: 0) {
                FormRow(title: "Фамилия", text: $patient.lastName, prompt: "Иванов")
                    .focused($focused, equals: .lastName)
                    .submitLabel(.next)
                    .onSubmit { focused = .firstName }
                    .textContentType(.familyName)
                Divider().padding(.leading, DS.Spacing.m)
                FormRow(title: "Имя", text: $patient.firstName, prompt: "Иван")
                    .focused($focused, equals: .firstName)
                    .submitLabel(.next)
                    .onSubmit { focused = .middleName }
                    .textContentType(.givenName)
                Divider().padding(.leading, DS.Spacing.m)
                FormRow(title: "Отчество", text: $patient.middleName, prompt: "Иванович")
                    .focused($focused, equals: .middleName)
                    .submitLabel(.next)
                    .onSubmit { focused = .notes }
                    .textContentType(.middleName)
                Divider().padding(.leading, DS.Spacing.m)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Примечание")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Диагноз, препараты, особенности…", text: $patient.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused, equals: .notes)
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.s)
            }
            .background(Color.surface, in: .rect(cornerRadius: DS.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: justSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text(justSaved ? "Сохранено" : "Сохранить")
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(.primary(justSaved ? .success : .brand))
        .disabled(!hasChanges && !justSaved)
        .animation(.snappy, value: justSaved)
        .animation(.snappy, value: hasChanges)
    }

    // MARK: Privacy

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Конфиденциальность").font(.headline)
            PrivacyRow(icon: "iphone", tint: .brand,
                       text: "ФИО и примечания хранятся локально и попадают только в CSV, который вы экспортируете сами.")
            PrivacyRow(icon: "waveform", tint: .metricBlue,
                       text: "На сервер отправляются только аудиофрагменты и модель устройства.")
            PrivacyRow(icon: "stethoscope", tint: .metricAmber,
                       text: "CoughScan не ставит диагноз. Обсудите результаты с врачом.")
        }
        .card(padding: DS.Spacing.l)
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Удалить все данные", systemImage: "trash")
            }
            .buttonStyle(.secondary(.cough))

            Text("Удаляет статистику, очередь отправки и карточку пациента на устройстве. Данные на сервере не удаляются.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Spacing.xxs)
        }
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return Text("CoughScan \(version) (\(build))")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.xs)
    }

    // MARK: Actions

    private func save() {
        guard hasChanges else { return }
        focused = nil
        CoughStorage.shared.patientInfo = patient
        savedPatient = patient
        saveTick += 1
        justSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { justSaved = false }
    }

    private func clearAll() {
        MonitoringManager.shared.clearAllData()
        UserDefaults.standard.set(false, forKey: "audio_upload_consent")
        patient = PatientInfo()
        savedPatient = PatientInfo()
    }
}

private struct FormRow: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .accessibilityElement(children: .contain)
    }
}

private struct PrivacyRow: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            IconBadge(systemName: icon, tint: tint, size: 30)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
