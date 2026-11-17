import SwiftUI
import UniformTypeIdentifiers

struct GradesScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @State private var query = ""
    @State private var lowest = false
    @State private var selectedSubject: GradeSubject?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                PageTitle(title: "Оценки", subtitle: "История, средний балл и прогноз")
                TextField("Поиск предмета", text: $query).textFieldStyle(.roundedBorder)
                HStack {
                    Text("Учебный период").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let snapshot = store.snapshot {
                        Menu {
                            ForEach(snapshot.gradePeriods, id: \.key) { period in
                                Button("\(period.title) · \(period.yearLabel)") {
                                    Task { await store.loadGrades(period.key) }
                                }
                            }
                        } label: {
                            Label(store.snapshot?.gradePeriods.first(where: { $0.key == store.selectedPeriod })?.title ?? "Выбрать", systemImage: "calendar")
                                .font(.subheadline)
                        }
                    }
                }
                Toggle("Сначала низкий средний", isOn: $lowest).font(.subheadline)
                if let book = store.book, store.snapshot?.studentId == book.studentId {
                    let all = book.subjects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                    let subjects = lowest ?
                        all.sorted { ($0.displayAverage.flatMap(Double.init) ?? 6) < ($1.displayAverage.flatMap(Double.init) ?? 6) } :
                        all.sorted { $0.name < $1.name }
                    SchoolPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.period.title).font(.headline)
                            Text(book.period.yearLabel).foregroundStyle(colors.muted).font(.caption)
                            HStack(spacing: 18) {
                                VStack(alignment: .leading) {
                                    Text("Предметы").font(.caption).foregroundStyle(colors.muted)
                                    Text("\(book.subjects.count)").font(.title.bold())
                                }
                                VStack(alignment: .leading) {
                                    Text("Все оценки").font(.caption).foregroundStyle(colors.muted)
                                    Text("\(book.subjects.flatMap(\.marks).count)").font(.title.bold())
                                }
                                VStack(alignment: .leading) {
                                    Text("Средний балл").font(.caption).foregroundStyle(colors.muted)
                                    Text(Analytics.score(Analytics.average(book.subjects.flatMap(\.marks))) ?? "—").font(.title.bold())
                                }
                            }
                        }
                    }
                    SectionHeading(title: "Предметы · \(subjects.count)", action: nil)
                    if store.preferences.appearance.freeGradesScroll && !subjects.isEmpty {
                        FreeGradesGrid(subjects: subjects) { selectedSubject = $0 }
                    } else {
                        ForEach(subjects) { subject in
                            Button { selectedSubject = subject } label: {
                                SchoolPanel {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 9) {
                                            Text(subject.name).font(.headline).foregroundStyle(colors.ink)
                                            HStack(spacing: 5) {
                                                ForEach(Array(subject.marks.suffix(8))) { mark in
                                                    MarkPill(value: mark.value, size: 29)
                                                }
                                                if subject.marks.isEmpty { Text("Оценок пока нет").foregroundStyle(colors.muted) }
                                            }
                                        }
                                        Spacer(minLength: 5)
                                        VStack(alignment: .trailing) {
                                            Text(subject.displayAverage ?? "—").font(.title3.bold()).foregroundStyle(colors.accent)
                                            Text("Средний").font(.caption2).foregroundStyle(colors.muted)
                                            Image(systemName: "chevron.right").foregroundStyle(colors.muted)
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    SyncFootnote(date: book.syncedAt, demo: store.snapshot?.demo == true)
                } else {
                    SchoolPanel {
                        Text("Загрузите оценки за выбранный период.")
                        Button("Обновить") { Task { await store.loadGrades() } }
                    }
                }
            }.padding(18).padding(.bottom, 20)
        }
        .refreshable { await store.loadGrades() }
        .sheet(item: $selectedSubject) { subject in SubjectDetails(subject: subject) }
    }
}
struct FreeGradesGrid: View {
    let subjects: [GradeSubject]
    let onDetails: (GradeSubject) -> Void
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @State private var currentScale: CGFloat = 1
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(subjects) { subject in
                    Button { onDetails(subject) } label: {
                        HStack(spacing: 5) {
                            Text(subject.name).lineLimit(1).frame(width: 155, alignment: .leading)
                            ForEach(Array(subject.marks.prefix(24))) { mark in MarkPill(value: mark.value, size: 27) }
                            Spacer(minLength: 12)
                            Text(subject.displayAverage ?? "—").bold().frame(width: 42)
                        }
                        .font(.caption)
                        .foregroundStyle(colors.ink)
                        .padding(8)
                        .background(colors.surface)
                    }.buttonStyle(.plain)
                }
            }
            .scaleEffect(currentScale * store.preferences.appearance.gradesScale, anchor: .topLeading)
        }
        .frame(height: CGFloat(subjects.count) * 45 + 12)
        .gesture(MagnificationGesture().onChanged { currentScale = min(1.8, max(0.65, $0)) }
            .onEnded { final in
                store.updatePreferences { $0.appearance.gradesScale = Double(min(1.8, max(0.65, final))) }
                currentScale = 1
            })
        Button("Уместить") { store.updatePreferences { $0.appearance.gradesScale = 1 } }
            .font(.caption)
    }
}
struct SubjectDetails: View {
    let subject: GradeSubject
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var predictedValue = 5
    @State private var predictedDate = Date()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    if let book = store.book {
                        SchoolPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(subject.name).font(.title2.bold())
                                Text(book.period.title).font(.subheadline).foregroundStyle(colors.muted)
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading) {
                                        Text(subject.displayAverage ?? "—").font(.largeTitle.bold())
                                        Text("Средний балл").font(.caption).foregroundStyle(colors.muted)
                                    }
                                    if let weighted = subject.weightedAverage {
                                        VStack(alignment: .leading) {
                                            Text(weighted).font(.largeTitle.bold())
                                            Text("Средневзвешенный").font(.caption).foregroundStyle(colors.muted)
                                        }
                                    }
                                }
                            }
                        }
                        if !subject.results.isEmpty {
                            SectionHeading(title: "Официальные итоги", action: nil)
                            SchoolPanel {
                                ForEach(Array(subject.results.enumerated()), id: \.offset) { _, result in
                                    HStack {
                                        Text(result.label)
                                        Spacer()
                                        Text(result.values.joined(separator: ", ")).font(.headline)
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                        SectionHeading(title: "История оценок", action: nil)
                        if subject.marks.isEmpty {
                            SchoolPanel { Text("За этот период отметок нет").foregroundStyle(colors.muted) }
                        }
                        ForEach(subject.marks.sorted { $0.date > $1.date }) { mark in
                            SchoolPanel {
                                HStack {
                                    MarkPill(value: mark.value)
                                    VStack(alignment: .leading) {
                                        Text(mark.date)
                                        Text(mark.type).font(.caption).foregroundStyle(colors.muted)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        if !subject.attendance.isEmpty {
                            SectionHeading(title: "Посещаемость", action: nil)
                            SchoolPanel {
                                ForEach(subject.attendance) { item in
                                    HStack { Text(item.date); Spacer(); Text(item.label).foregroundStyle(colors.muted) }
                                        .padding(.vertical, 3)
                                }
                            }
                        }
                        if !book.period.isFinal && subject.officialResult(for: book.period) == nil {
                            SectionHeading(title: "Калькулятор прогноза", action: nil)
                            SchoolPanel {
                                Text("Предполагаемые оценки сохраняются только на устройстве на 7 дней и не отправляются в школу.")
                                    .font(.caption).foregroundStyle(colors.muted)
                                HStack {
                                    Picker("Оценка", selection: $predictedValue) {
                                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                                    }.pickerStyle(.menu)
                                    DatePicker("Дата", selection: $predictedDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                }
                                Button("Добавить прогноз") {
                                    store.addPrediction(predictedValue, subject: subject, date: predictedDate)
                                }.buttonStyle(.borderedProminent)
                                let predictions = store.predictions.filter {
                                    $0.studentId == book.studentId && $0.periodKey == book.period.key && $0.subjectId == subject.id
                                }
                                let values = subject.marks + predictions.map {
                                    Mark(id: Int64($0.createdAt.timeIntervalSince1970 * 1000),
                                         subject: subject.name, value: "\($0.value)", date: $0.date)
                                }
                                Text("Прогноз среднего: \(Analytics.score(Analytics.average(values)) ?? "—")").font(.headline)
                                if let count = Analytics.fivesToTarget(values, target: 4.5) {
                                    Text("Пятёрок до среднего 4,50: \(count)").font(.subheadline)
                                }
                                ForEach(predictions) { prediction in
                                    HStack {
                                        MarkPill(value: "\(prediction.value)", size: 29)
                                        Text(prediction.date)
                                        Spacer()
                                        Button(role: .destructive) { store.removePrediction(prediction.id) } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.padding(18)
            }
            .navigationTitle("Предмет").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}
struct ProfileScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @State private var query = ""
    private let destinations: [(String, String, String)] = [
        ("Оформление", "paintpalette", "Тема, палитра, шрифт, плотность, анимации"),
        ("Уведомления", "bell", "Оценки, задания, сводка и приватность"),
        ("Дневник и уроки", "calendar", "Начало дня, звонки, листание, масштаб"),
        ("Конфиденциальность", "lock.shield", "Кэш, экспорт и данные"),
        ("О приложении", "info.circle", "Версия и информация")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: "Профиль", subtitle: "Ваш дневник, ваши привычки")
                Button { store.accountsPresented = true } label: {
                    SchoolPanel {
                        HStack(spacing: 15) {
                            Text(String(store.snapshot?.student?.name.prefix(1) ?? "М"))
                                .font(.title.bold()).foregroundStyle(.white)
                                .frame(width: 55, height: 55)
                                .background(LinearGradient(colors: [colors.accent, colors.secondary],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: 17))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.snapshot?.student?.name ?? "Мой профиль").font(.headline)
                                Text(store.snapshot?.group?.name ?? "Дневник.ру").font(.subheadline)
                                Text(store.snapshot?.demo == true ? "Демо-аккаунт" : "Аккаунт Дневник.ру")
                                    .font(.caption).foregroundStyle(colors.muted)
                            }
                            Spacer()
                            Image(systemName: "person.2.circle").font(.title2)
                        }
                    }.background(colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 21))
                }.buttonStyle(.plain)
                if let s = store.snapshot {
                    if s.students.count > 1 {
                        Menu {
                            ForEach(s.students) { person in
                                Button(person.name) { Task { await store.refresh(student: person.id) } }
                            }
                        } label: { Label("Выбрать ученика", systemImage: "person.crop.circle") }
                    }
                    if s.groups.count > 1 {
                        Menu {
                            ForEach(s.groups) { group in
                                Button(group.name) { Task { await store.refresh(group: group.id) } }
                            }
                        } label: { Label("Выбрать класс", systemImage: "building.2") }
                    }
                }
                TextField("Поиск настроек", text: $query).textFieldStyle(.roundedBorder)
                SectionHeading(title: query.isEmpty ? "Настройки" : "Результаты поиска", action: nil)
                SchoolPanel {
                    ForEach(destinations.filter { query.isEmpty ||
                        $0.0.localizedCaseInsensitiveContains(query) || $0.2.localizedCaseInsensitiveContains(query)
                    }, id: \.0) { item in
                        Button { store.navigate(item.0) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: item.1).frame(width: 26).font(.title3)
                                    .foregroundStyle(colors.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.0).font(.headline).foregroundStyle(colors.ink)
                                    Text(item.2).font(.caption).foregroundStyle(colors.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(colors.muted)
                            }.padding(.vertical, 9)
                        }.buttonStyle(.plain)
                    }
                }
                if store.snapshot?.demo != true {
                    Button("Открыть / восстановить веб-сессию") { store.loginPresented = true }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                Button("Выйти из аккаунта", role: .destructive) {
                    Task { await store.logout(); store.navigate("Главная") }
                }.frame(maxWidth: .infinity).padding(.top, 10)
            }.padding(18).padding(.bottom, 20)
        }
    }
}
struct AccountsScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.account.entries) { account in
                    HStack {
                        Button {
                            Task { await store.switchAccount(account.id); dismiss() }
                        } label: {
                            Label(account.label, systemImage: account.id == store.accountID ? "checkmark.circle.fill" : "person.crop.circle")
                        }
                        Spacer()
                        if store.account.entries.count > 1 {
                            Button(role: .destructive) {
                                Task { await store.removeAccount(account.id) }
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
                Button { Task { await store.addAccount(); dismiss() } } label: {
                    Label("Добавить аккаунт", systemImage: "plus.circle")
                }.disabled(store.account.entries.count >= 5)
            }
            .navigationTitle("Аккаунты").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}
struct SettingsHeader: View {
    let title: String
    @EnvironmentObject private var store: SchoolStore
    var body: some View {
        HStack {
            Button { store.navigate("Профиль") } label: { Image(systemName: "chevron.left") }
            Text(title).font(.title2.bold())
            Spacer()
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }
}
struct AppearanceScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @State private var preview = true
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "Оформление")
            Form {
                Section("Стиль") {
                    Picker("Тема", selection: binding(\.theme)) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }
                    Picker("Палитра", selection: binding(\.appearance.palette)) {
                        Text("Лесная").tag("forest")
                        Text("Лавандовая").tag("lavender")
                        Text("Морская").tag("ocean")
                        Text("Персиковая").tag("peach")
                    }
                    .onChange(of: store.preferences.appearance.palette) { _, value in
                        let colors: (String, String) = switch value {
                        case "lavender": ("#7663C5", "#A18CE0")
                        case "ocean": ("#247A9A", "#397A92")
                        case "peach": ("#AC634B", "#CF8A70")
                        default: ("#267953", "#467B69")
                        }
                        store.updatePreferences {
                            $0.appearance.accent = colors.0
                            $0.appearance.secondary = colors.1
                        }
                    }
                    Toggle("AMOLED — чёрный фон", isOn: binding(\.appearance.amoled))
                    Toggle("Повышенный контраст", isOn: binding(\.appearance.highContrast))
                }
                Section("Чтение") {
                    Picker("Шрифт", selection: binding(\.appearance.font)) {
                        Text("Обычный").tag("sans")
                        Text("С засечками").tag("serif")
                        Text("Моноширинный").tag("mono")
                    }
                    Toggle("Компактные карточки", isOn: binding(\.appearance.compact))
                    VStack(alignment: .leading) {
                        Text("Скругление: \(Int(store.preferences.appearance.rounding))")
                        Slider(value: binding(\.appearance.rounding), in: 0...36, step: 1)
                    }
                }
                Section("Доступность") {
                    Toggle("Матовое стекло", isOn: binding(\.appearance.frostedNavigation))
                    Toggle("Меньше движения", isOn: binding(\.appearance.reduceMotion))
                }
                Section {
                    DisclosureGroup("Живой пример", isExpanded: $preview) {
                        SchoolPanel {
                            Text("Алгебра").font(.headline)
                            HStack {
                                Text("Домашнее задание: решить № 245")
                                Spacer()
                                MarkPill(value: "5")
                            }
                        }
                    }
                }
            }
        }
    }
    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: path] },
                set: { value in store.updatePreferences { $0[keyPath: path] = value } })
    }
}
struct NotificationsSettingsScreen: View {
    @EnvironmentObject private var store: SchoolStore
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "Уведомления")
            Form {
                Section {
                    Toggle("Разрешить уведомления", isOn: setting(\.enabled))
                } footer: {
                    Text("iOS управляет периодичностью фонового обновления. Уведомления о новых оценках требуют успешной проверки данных; частоту нельзя гарантировать.")
                }
                Section("События") {
                    Toggle("Новые оценки", isOn: setting(\.marks))
                    Toggle("Итоги периодов", isOn: setting(\.quarterMarks))
                    Toggle("Домашняя работа", isOn: setting(\.homework))
                    Toggle("Изменения расписания", isOn: setting(\.schedule))
                    Toggle("Напоминание о ДЗ", isOn: setting(\.reminder))
                    Toggle("Вечерняя сводка", isOn: setting(\.summary))
                }
                Section("Приватность и режим") {
                    Toggle("Скрывать содержимое", isOn: setting(\.privateContent))
                    Toggle("Тихие часы", isOn: setting(\.quiet))
                    Toggle("Только по будням", isOn: setting(\.weekdaysOnly))
                    Stepper("Проверять каждые \(store.preferences.notifications.intervalMinutes) мин",
                            value: setting(\.intervalMinutes), in: 15...240, step: 15)
                }
                Section("Время напоминаний") {
                    Stepper("Напоминать: \(clock(store.preferences.notifications.reminderAt))",
                            value: setting(\.reminderAt), in: 0...1439, step: 15)
                    Stepper("Сводка: \(clock(store.preferences.notifications.summaryAt))",
                            value: setting(\.summaryAt), in: 0...1439, step: 15)
                    Stepper("Тихо с \(clock(store.preferences.notifications.quietFrom))",
                            value: setting(\.quietFrom), in: 0...1439, step: 15)
                    Stepper("Тихо до \(clock(store.preferences.notifications.quietTo))",
                            value: setting(\.quietTo), in: 0...1439, step: 15)
                }
            }
        }
    }
    private func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func setting<T>(_ path: WritableKeyPath<NotificationPreferences, T>) -> Binding<T> {
        Binding(get: { store.preferences.notifications[keyPath: path] },
                set: { value in store.updatePreferences { $0.notifications[keyPath: path] = value } })
    }
}
struct DiarySettingsScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var start = ""
    @State private var end = ""
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "Дневник и уроки")
            Form {
                Section("Начало дня") {
                    Picker("Начальный экран", selection: binding(\.startScreen)) {
                        ForEach(["Главная", "Дневник", "Оценки", "Профиль"], id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Открывать завтрашний день", isOn: binding(\.opening.enabled))
                    Picker("Условие перехода", selection: binding(\.opening.mode)) {
                        Text("После уроков").tag("afterLessons")
                        Text("По времени").tag("time")
                    }
                    if store.preferences.opening.mode == "afterLessons" {
                        Stepper("Через \(store.preferences.opening.delayMinutes) мин",
                                value: binding(\.opening.delayMinutes), in: 0...720, step: 15)
                    } else {
                        Stepper("После \(store.preferences.opening.atMinute / 60):\(String(format: "%02d", store.preferences.opening.atMinute % 60))",
                                value: binding(\.opening.atMinute), in: 0...1439, step: 15)
                    }
                }
                Section("Листание и масштаб") {
                    Toggle("Свободная прокрутка дневника", isOn: binding(\.appearance.freeDiaryScroll))
                    Toggle("Масштабирование дневника", isOn: binding(\.appearance.diaryZoom))
                    Toggle("Свободная таблица оценок", isOn: binding(\.appearance.freeGradesScroll))
                    Toggle("Масштабирование оценок", isOn: binding(\.appearance.gradesZoom))
                }
                Section("Звонки") {
                    Toggle("Своё расписание звонков", isOn: binding(\.slotTimesEnabled))
                    ForEach(1...8, id: \.self) { number in
                        let saved = store.preferences.bellTimes[number]
                        HStack {
                            Text("\(number) урок")
                            Spacer()
                            Text(saved.map { "\($0.start)–\($0.end)" } ?? "Время с сайта")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if store.preferences.slotTimesEnabled {
                            HStack {
                                TextField("Начало HH:mm", text: Binding(
                                    get: { store.preferences.bellTimes[number]?.start ?? "" },
                                    set: { value in store.updatePreferences {
                                        let old = $0.bellTimes[number] ?? BellTime(start: "", end: "")
                                        $0.bellTimes[number] = BellTime(start: value, end: old.end)
                                    }}
                                )).keyboardType(.numbersAndPunctuation)
                                TextField("Конец HH:mm", text: Binding(
                                    get: { store.preferences.bellTimes[number]?.end ?? "" },
                                    set: { value in store.updatePreferences {
                                        let old = $0.bellTimes[number] ?? BellTime(start: "", end: "")
                                        $0.bellTimes[number] = BellTime(start: old.start, end: value)
                                    }}
                                )).keyboardType(.numbersAndPunctuation)
                                Button("Сбросить") { store.updatePreferences { $0.bellTimes.removeValue(forKey: number) } }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: path] },
                set: { value in store.updatePreferences { $0[keyPath: path] = value } })
    }
}
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
struct PrivacyScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var exporting = false
    @State private var confirming = false
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "Конфиденциальность")
            Form {
                Section("Локальные данные") {
                    Text("Дневник, настройки и личные заметки сохраняются зашифрованно на устройстве. Пароли и коды вводятся только на сайте.")
                    Button("Очистить кэш") { confirming = true }
                        .confirmationDialog("Очистить локальные загруженные данные?", isPresented: $confirming) {
                            Button("Очистить", role: .destructive) { Task { await store.clearCache() } }
                        }
                    Button("Экспортировать оценки в CSV") { exporting = true }
                }
                Section("Сведения") {
                    Text("Нет рекламных и аналитических SDK. Приложение самостоятельно обращается к страницам Дневник.ру через HTTPS.")
                    Text("Выход завершает локальную сессию и удаляет её ключи. Экспортированные файлы остаются у пользователя.")
                }
            }
        }
        .fileExporter(isPresented: $exporting,
                      document: CSVFile(text: store.exportGradesCSV()),
                      contentType: .commaSeparatedText,
                      defaultFilename: "my-school-grades") { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
    }
}
struct AboutScreen: View {
    @EnvironmentObject private var store: SchoolStore
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "О приложении")
            Form {
                Label("Моя школа · iOS", systemImage: "graduationcap.fill")
                LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Text("Неофициальный клиент Дневник.ру от dnkx. Код основан на проекте DnevnikRu для Android.")
                Link("Исходный проект Android", destination: URL(string: "https://github.com/dan4ikx/DnevnikRu")!)
                Link("iOS-репозиторий", destination: URL(string: "https://github.com/dan4ikx/DnevnikRu_IOS")!)
            }
        }
    }
}
