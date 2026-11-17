import SwiftUI
import WebKit
import UniformTypeIdentifiers

@main
struct MySchoolApp: App {
    @UIApplicationDelegateAdaptor(MySchoolAppDelegate.self) private var appDelegate
    @StateObject private var store = SchoolStore()
    var body: some Scene {
        WindowGroup {
            SchoolRoot()
                .environmentObject(store)
                .task { await store.initialize() }
        }
    }
}
extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(raw, radix: 16) ?? 0x267953
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}
struct SchoolColors {
    let dark: Bool
    let accent: Color
    let secondary: Color
    let background: Color
    let surface: Color
    let soft: Color
    let ink: Color
    let muted: Color
    init(_ preferences: Preferences, dark systemDark: Bool) {
        dark = preferences.theme == "dark" || (preferences.theme == "system" && systemDark)
        accent = Color(hex: preferences.appearance.accent)
        secondary = Color(hex: preferences.appearance.secondary)
        background = dark ? (preferences.appearance.amoled ? .black : Color(hex: "#0E1311")) : Color(hex: "#F5F7F3")
        surface = dark ? Color(hex: "#171E1A") : Color(hex: "#FDFEFC")
        soft = dark ? Color(hex: "#29352E") : Color(hex: "#EBEFE8")
        ink = dark ? Color(hex: "#E7EDE8") : Color(hex: "#1B231D")
        muted = dark ? Color(hex: "#A2B1A7") : Color(hex: "#5E6C62")
    }
}
private struct SchoolColorsKey: EnvironmentKey {
    static let defaultValue = SchoolColors(Preferences(), dark: false)
}
extension EnvironmentValues {
    var schoolColors: SchoolColors {
        get { self[SchoolColorsKey.self] }
        set { self[SchoolColorsKey.self] = newValue }
    }
}
struct SchoolPanel<Content: View>: View {
    @Environment(\.schoolColors) private var colors
    @EnvironmentObject private var store: SchoolStore
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(store.preferences.appearance.compact ? 13 : 17)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: store.preferences.appearance.rounding))
    }
}
struct PageTitle: View {
    let title: String
    let subtitle: String
    @Environment(\.schoolColors) private var colors
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SectionHeading: View {
    let title: String
    let action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let action { Button("Все", action: action).font(.subheadline.weight(.semibold)) }
        }
    }
}
struct MarkPill: View {
    let value: String
    var size: CGFloat = 36
    var body: some View {
        let color: Color = switch value {
        case "5": Color(hex: "#1F9965")
        case "4": Color(hex: "#4185D6")
        case "3": Color(hex: "#DB993E")
        case "2", "1": Color(hex: "#D5635B")
        default: Color(hex: "#7E7D95")
        }
        Text(value).font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.31))
            .accessibilityLabel("Оценка \(value)")
    }
}
struct SchoolRoot: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let colors = SchoolColors(store.preferences, dark: colorScheme == .dark)
        ZStack {
            colors.background.ignoresSafeArea()
            if !store.isReady {
                ProgressView("Загружаем приложение")
            } else if !store.authenticated {
                WelcomeScreen()
            } else {
                VStack(spacing: 0) {
                    if !["Профиль", "Оформление", "Уведомления", "Дневник и уроки", "Конфиденциальность", "О приложении"].contains(store.destination) {
                        SchoolHeader()
                    }
                    if store.needsLogin {
                        HStack {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            Text("Веб-сессию нужно восстановить").font(.footnote)
                            Spacer()
                            Button("Открыть") { store.loginPresented = true }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(colors.soft)
                    }
                    if store.isLoading || store.gradesLoading {
                        ProgressView().tint(colors.accent).frame(maxWidth: .infinity)
                    } else { Color.clear.frame(height: 3) }
                    Group {
                        switch store.destination {
                        case "Дневник": DiaryScreen()
                        case "Оценки": GradesScreen()
                        case "Профиль": ProfileScreen()
                        case "Оформление": AppearanceScreen()
                        case "Уведомления": NotificationsSettingsScreen()
                        case "Дневник и уроки": DiarySettingsScreen()
                        case "Конфиденциальность": PrivacyScreen()
                        case "О приложении": AboutScreen()
                        default: HomeScreen()
                        }
                    }
                    .frame(maxWidth: 840)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if ["Главная", "Дневник", "Оценки", "Профиль"].contains(store.destination) {
                        BottomNavigation()
                    }
                }
            }
        }
        .foregroundStyle(colors.ink)
        .tint(colors.accent)
        .environment(\.schoolColors, colors)
        .preferredColorScheme(store.preferences.theme == "system" ? nil : (store.preferences.theme == "dark" ? .dark : .light))
        .sheet(isPresented: $store.loginPresented) { WebsiteLoginScreen() }
        .sheet(isPresented: $store.accountsPresented) { AccountsScreen() }
        .alert("Моя школа", isPresented: Binding(get: { store.error != nil },
                                                  set: { if !$0 { store.error = nil } })) {
            Button("Понятно", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
struct BottomNavigation: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    private let items: [(String, String)] = [
        ("Главная", "house.fill"), ("Дневник", "book.closed.fill"),
        ("Оценки", "chart.bar.fill"), ("Профиль", "person.crop.circle.fill")
    ]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    store.navigate(item.0)
                    if item.0 == "Оценки" { Task { await store.loadGrades() } }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.1).font(.system(size: 21, weight: .semibold))
                        Text(item.0).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(store.destination == item.0 ? colors.accent : colors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(store.destination == item.0 ? colors.soft.opacity(0.8) : .clear,
                                in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(store.preferences.appearance.frostedNavigation ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(colors.surface))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
    }
}
struct SchoolHeader: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    var body: some View {
        HStack(spacing: 10) {
            Button { store.navigate("Профиль") } label: {
                Text(String(store.snapshot?.student?.name.prefix(1) ?? "М"))
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [colors.accent, colors.secondary], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot?.student?.name ?? "Моя школа").font(.headline)
                Text(store.snapshot?.group?.name ?? "Дневник.ру").font(.caption).foregroundStyle(colors.muted)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.body.weight(.semibold))
                    .frame(width: 42, height: 42).background(colors.soft, in: Circle())
            }
            .disabled(store.isLoading)
            Button { store.navigate("Профиль") } label: {
                Image(systemName: "gearshape.fill").frame(width: 42, height: 42)
                    .background(colors.soft, in: Circle())
            }
        }.padding(.horizontal, 18).padding(.vertical, 9)
    }
}
struct WelcomeScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 35)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 49, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 90, height: 90)
                    .background(LinearGradient(colors: [colors.accent, colors.secondary],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 27))
                Text("Моя школа").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Расписание, домашние задания и оценки — в одном месте.")
                    .font(.title3).foregroundStyle(colors.muted)
                SchoolPanel {
                    Label("Все уроки и задания на день", systemImage: "calendar")
                    Divider()
                    Label("Средний балл и история оценок", systemImage: "chart.bar")
                    Divider()
                    Label("Личные заметки и офлайн-доступ", systemImage: "checkmark.seal")
                }
                Button { store.loginPresented = true } label: {
                    Label("Войти через Дневник.ру", systemImage: "globe")
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                }.buttonStyle(.borderedProminent)
                Button { Task { await store.showDemo() } } label: {
                    Text("Попробовать демоверсию").frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.bordered)
                Text("Независимое приложение. Не является официальным продуктом Дневник.ру или Госуслуг. Вход выполняется на страницах сайта.")
                    .font(.footnote).foregroundStyle(colors.muted)
            }.padding(24).frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        }
    }
}
struct HomeScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PageTitle(title: "Сегодня", subtitle: DateTools.title(.now))
                if let s = store.snapshot {
                    let today = DateTools.string(.now)
                    let lessons = s.lessons.filter { $0.date == today && !$0.cancelled }.sorted { $0.number < $1.number }
                    let tasks = store.preferences.homework(for: s).filter { $0.date == today }
                    let done = tasks.filter { store.preferences.completed.contains($0.key(s.studentId)) }.count
                    SchoolPanel {
                        ZStack(alignment: .topLeading) {
                            LinearGradient(colors: [colors.accent.opacity(0.25), colors.secondary.opacity(0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Ваш школьный день", systemImage: "sparkles").font(.caption.bold())
                                Text(lessons.isEmpty ? "Уроков на сегодня нет" : "\(lessons.count) уроков сегодня")
                                    .font(.system(size: 27, weight: .bold, design: .rounded))
                                if let next = upcoming(lessons) {
                                    Text("\(next.starts)–\(next.ends) · \(next.subject)")
                                        .font(.subheadline)
                                }
                                HStack {
                                    Label("\(done)/\(tasks.count) заданий", systemImage: "checkmark.circle")
                                    Spacer()
                                    Button("Дневник") { store.navigate("Дневник") }
                                }.font(.subheadline)
                                ProgressView(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)).tint(colors.accent)
                            }.padding(18)
                        }
                    }
                    SectionHeading(title: "Домашняя работа", action: { store.navigate("Дневник") })
                    let pending = tasks.filter { !store.preferences.completed.contains($0.key(s.studentId)) }
                    if pending.isEmpty {
                        SchoolPanel { Label("На сегодня всё готово", systemImage: "checkmark.circle.fill").foregroundStyle(colors.muted) }
                    } else {
                        SchoolPanel {
                            ForEach(Array(pending.prefix(3))) { item in
                                HomeworkRow(item: item)
                                if item.id != pending.prefix(3).last?.id { Divider().padding(.vertical, 5) }
                            }
                        }
                    }
                    SectionHeading(title: "Свежие оценки", action: { store.navigate("Оценки") })
                    SchoolPanel {
                        if s.marks.isEmpty { Text("Новых оценок пока нет").foregroundStyle(colors.muted) }
                        ForEach(Array(s.marks.sorted { $0.date > $1.date }.prefix(5))) { mark in
                            HStack(spacing: 11) {
                                MarkPill(value: mark.value)
                                VStack(alignment: .leading) {
                                    Text(mark.subject).font(.subheadline.weight(.semibold))
                                    Text(mark.date).font(.caption).foregroundStyle(colors.muted)
                                }
                                Spacer()
                            }.padding(.vertical, 3)
                        }
                    }
                    SyncFootnote(date: s.syncedAt, demo: s.demo)
                } else {
                    SchoolPanel {
                        Text("Пока нет данных")
                        Button("Повторить загрузку") { Task { await store.refresh() } }
                    }
                }
            }.padding(.horizontal, 18).padding(.top, 13).padding(.bottom, 30)
        }.refreshable { await store.refresh() }
    }
    private func upcoming(_ lessons: [Lesson]) -> Lesson? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let now = formatter.string(from: .now)
        return lessons.first { !$0.ends.isEmpty && $0.ends > now }
    }
}
struct SyncFootnote: View {
    let date: Date
    let demo: Bool
    @Environment(\.schoolColors) private var colors
    var body: some View {
        Text(demo ? "Демонстрационные данные" : "Обновлено: \(date.formatted(date: .numeric, time: .shortened)) · Данные сохранены офлайн")
            .font(.footnote).foregroundStyle(colors.muted).frame(maxWidth: .infinity)
    }
}
struct HomeworkRow: View {
    let item: Homework
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button { store.setHomeworkDone(item) } label: {
                Image(systemName: store.preferences.completed.contains(item.key(store.snapshot?.studentId ?? 0)) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }.accessibilityLabel("Отметить выполнение")
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.subject).font(.subheadline.bold())
                    if item.important { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                    if item.local { Text("Моё").font(.caption2).foregroundStyle(colors.muted) }
                }
                Text(item.text).font(.subheadline).textSelection(.enabled)
                ForEach(item.files) { attachment in
                    if let url = URL(string: attachment.url), url.scheme == "https" {
                        Link(destination: url) { Label(attachment.name, systemImage: "paperclip").font(.caption) }
                    }
                }
                ForEach(item.links, id: \.self) { raw in
                    if let url = URL(string: raw), url.scheme == "https" {
                        Link(destination: url) { Label(url.host ?? "Ссылка", systemImage: "link").font(.caption) }
                    }
                }
                if item.local {
                    Button("Удалить своё задание", role: .destructive) { store.deleteHomework(item) }.font(.caption)
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }
}
struct DiaryScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.schoolColors) private var colors
    @State private var search = ""
    @State private var homeworkOnly = false
    @State private var newTask = false
    @State private var noteText = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Дневник", subtitle: "Уроки и домашние задания")
                HStack(spacing: 10) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 35, height: 44) }
                    DatePicker("День", selection: Binding(get: { store.selectedDate }, set: { value in
                        Task { await store.selectDate(value) }
                    }), displayedComponents: [.date])
                        .datePickerStyle(.compact).labelsHidden().frame(maxWidth: .infinity)
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 35, height: 44) }
                    Button("Сегодня") { Task { await store.selectDate(.now) } }.font(.caption.bold())
                }
                SchoolPanel {
                    HStack {
                        ForEach(0..<7, id: \.self) { offset in
                            let date = DateTools.day(DateTools.monday(store.selectedDate), offset: offset)
                            let selected = DateTools.string(date) == DateTools.string(store.selectedDate)
                            Button { Task { await store.selectDate(date) } } label: {
                                VStack(spacing: 6) {
                                    Text(DateTools.title(date, pattern: "EE")).font(.caption2).textCase(.uppercase)
                                    Text(DateTools.title(date, pattern: "d")).font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundStyle(selected ? .white : colors.ink)
                                .background(selected ? colors.accent : .clear, in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                TextField("Найти урок или задание", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("Только с домашним заданием", isOn: $homeworkOnly).font(.subheadline)
                if let s = store.snapshot {
                    let day = DateTools.string(store.selectedDate)
                    let lessons = s.lessons.filter { $0.date == day }.sorted { $0.number < $1.number }
                    let tasks = store.preferences.homework(for: s).filter { $0.date == day }
                    let visible = lessons.filter { lesson in
                        (!homeworkOnly || tasks.contains { $0.lessonId == lesson.id }) &&
                        (search.isEmpty || lesson.subject.localizedCaseInsensitiveContains(search) ||
                         lesson.title.localizedCaseInsensitiveContains(search) ||
                         tasks.contains { $0.lessonId == lesson.id && $0.text.localizedCaseInsensitiveContains(search) })
                    }
                    HStack {
                        Text(DateTools.title(store.selectedDate, pattern: "EEEE, d MMMM"))
                            .font(.title3.bold())
                        Spacer()
                        Button { newTask = true } label: { Label("Добавить", systemImage: "plus") }.font(.subheadline)
                    }
                    if visible.isEmpty {
                        SchoolPanel { Text("Уроков не найдено").foregroundStyle(colors.muted) }
                    }
                    ForEach(visible) { lesson in
                        SchoolPanel {
                            HStack(alignment: .top, spacing: 13) {
                                Text("\(lesson.number)")
                                    .font(.title3.bold()).foregroundStyle(colors.accent)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Text(lesson.subject).font(.headline)
                                        Spacer()
                                        if lesson.cancelled { Text("Отменён").font(.caption).foregroundStyle(.red) }
                                    }
                                    if !lesson.starts.isEmpty || !lesson.ends.isEmpty {
                                        Label("\(lesson.starts)–\(lesson.ends)", systemImage: "clock").font(.caption).foregroundStyle(colors.muted)
                                    }
                                    if !lesson.room.isEmpty {
                                        Label("Кабинет \(lesson.room)", systemImage: "door.left.hand.closed").font(.caption).foregroundStyle(colors.muted)
                                    }
                                    if !lesson.title.isEmpty { Text(lesson.title).font(.subheadline) }
                                    let marks = lesson.marks + s.marks.filter {
                                        $0.date == lesson.date && $0.subject == lesson.subject && ($0.lessonId == nil || $0.lessonId == lesson.id)
                                    }
                                    if !marks.isEmpty {
                                        HStack { ForEach(Array(Dictionary(grouping: marks, by: \.id).values.compactMap { $0.first })) { mark in MarkPill(value: mark.value, size: 30) } }
                                    }
                                    ForEach(tasks.filter { $0.lessonId == lesson.id }) { HomeworkRow(item: $0) }
                                }
                            }
                        }
                    }
                    let extra = tasks.filter { task in task.lessonId == 0 || !lessons.contains(where: { $0.id == task.lessonId }) }
                    if !extra.isEmpty {
                        SectionHeading(title: "Другие задания", action: nil)
                        SchoolPanel { ForEach(extra) { HomeworkRow(item: $0) } }
                    }
                    Text("Личная заметка").font(.headline)
                    TextEditor(text: $noteText).frame(minHeight: 90)
                        .padding(6).background(colors.surface, in: RoundedRectangle(cornerRadius: 17))
                        .onAppear { noteText = store.preferences.notes[day] ?? "" }
                        .onChange(of: day) { _, newValue in noteText = store.preferences.notes[newValue] ?? "" }
                    Button("Сохранить заметку") { store.note(noteText, date: store.selectedDate) }
                        .buttonStyle(.borderedProminent)
                    SyncFootnote(date: s.syncedAt, demo: s.demo)
                }
            }.padding(18).padding(.bottom, 25)
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $newTask) { NewHomeworkScreen(date: store.selectedDate) }
    }
    private func move(_ step: Int) {
        Task { await store.selectDate(DateTools.day(store.selectedDate, offset: step)) }
    }
}
struct NewHomeworkScreen: View {
    let date: Date
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Предмет", text: $subject)
                TextField("Задание", text: $text, axis: .vertical).lineLimit(3...7)
                Text(DateTools.title(date)).foregroundStyle(.secondary)
            }
            .navigationTitle("Своё задание").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let subjectId = store.snapshot?.lessons.first { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }?.subjectId ?? 0
                        store.addHomework(subjectId: subjectId, subject: subject, date: date, text: text)
                        dismiss()
                    }.disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
