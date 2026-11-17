import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class SchoolStore: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var preferences = Preferences()
    @Published var book: GradeBook?
    @Published var selectedDate = Date()
    @Published var destination = "Главная"
    @Published var selectedPeriod = ""
    @Published var account = AccountCatalog()
    @Published var isLoading = false
    @Published var gradesLoading = false
    @Published var error: String?
    @Published var needsLogin = false
    @Published var loginPresented = false
    @Published var accountsPresented = false
    @Published var markRange = 30
    @Published var isReady = false
    @Published var statusMessage: String?
    private var website: WebsiteClient?
    private let vault = SecureVault.shared
    private var weekCache: [String: Snapshot] = [:]

    var authenticated: Bool { snapshot?.demo == true || website != nil }
    var accountID: String { account.current }
    var predictions: [PredictedMark] {
        preferences.predictions.filter(\.active)
    }
    func initialize() async {
        account = await vault.catalog()
        await openAccount()
        isReady = true
    }
    private func openAccount() async {
        weekCache.removeAll()
        snapshot = try? await vault.read(Snapshot.self, name: "snapshot", account: accountID)
        preferences = (try? await vault.read(Preferences.self, name: "preferences", account: accountID)) ?? Preferences()
        book = try? await vault.read(GradeBook.self, name: "gradebook", account: accountID)
        selectedPeriod = book?.period.key ?? ""
        destination = preferences.startScreen
        if let session = await vault.session(for: accountID) {
            website = WebsiteClient(cookies: session.cookies)
        } else { website = nil }
        if authenticated { await refresh() }
    }
    func updatePreferences(_ transform: (inout Preferences) -> Void) {
        transform(&preferences)
        let value = preferences
        let id = accountID
        Task { try? await vault.save(value, name: "preferences", account: id) }
        NotificationCoordinator.configure(preferences.notifications)
    }
    func showDemo() async {
        await logout()
        let example = DemoData.snapshot(selectedDate, days: markRange)
        snapshot = example
        destination = "Главная"
        book = DemoData.grades(example.gradePeriods.first(where: \.isDefault) ?? example.gradePeriods[0])
        selectedPeriod = book?.period.key ?? ""
        await saveSnapshot()
        await saveBook()
    }
    func acceptCookies(_ cookies: [SessionCookie], userAgent: String = "") async {
        guard !cookies.isEmpty else { error = "Вход ещё не завершён. Авторизуйтесь на сайте."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let candidate = WebsiteClient(cookies: cookies)
            let context = try await candidate.page()
            let previous = await vault.session(for: accountID)
            if let previous, !previous.principal.isEmpty, previous.principal != context.principal {
                snapshot = nil
                book = nil
                updatePreferences { p in
                    p.completed = []; p.notes = [:]; p.ownHomework = []; p.predictions = []
                }
                await vault.remove(name: "snapshot", account: accountID)
                await vault.remove(name: "gradebook", account: accountID)
            }
            let session = SessionArchive(cookies: await candidate.cookies(), principal: context.principal, userAgent: userAgent)
            try await vault.setSession(session, for: accountID)
            website = candidate
            needsLogin = false
            loginPresented = false
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
    func refresh(student: Int64? = nil, group: Int64? = nil) async {
        guard !isLoading else { return }
        guard let snapshot, snapshot.demo == true else {
            await syncFromWebsite(student: student, group: group)
            return
        }
        self.snapshot = DemoData.snapshot(selectedDate, days: markRange)
        await saveSnapshot()
        if destination == "Оценки" { await loadGrades() }
    }
    private func syncFromWebsite(student: Int64? = nil, group: Int64? = nil) async {
        guard let client = website else { needsLogin = true; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let context = try await client.page()
            if let saved = await vault.session(for: accountID), !saved.principal.isEmpty,
               !context.principal.isEmpty, saved.principal != context.principal {
                throw SiteError.invalidSession
            }
            let students = context.students
            guard let person = student.flatMap({ id in students.first { $0.id == id } }) ??
                    students.first(where: { $0.id == snapshot?.studentId }) ?? students.first else {
                throw SiteError.changed("Не найден доступный ученик.")
            }
            let groups = context.groups(for: person.id)
            guard let selected = group.flatMap({ id in groups.first { $0.id == id } }) ??
                    groups.first(where: { $0.id == snapshot?.groupId }) ?? groups.first else {
                throw SiteError.changed("Не найден доступный класс.")
            }
            let periods = context.periods(for: person.id, school: selected.schoolId)
            let monday = DateTools.monday(selectedDate)
            async let incoming = client.diary(person: person.id, school: selected.schoolId, monday: monday)
            let period = periods.first { $0.groupId == selected.id && $0.isDefault && !$0.isFinal } ??
                periods.first { $0.groupId == selected.id && !$0.isFinal }
            var newBook: GradeBook?
            if let period {
                let payload = try await client.grades(person: person.id, school: period.schoolId, group: period.groupId, period: period.id)
                newBook = try SiteParser.gradeBook(payload, student: person.id, period: period, catalog: periods)
            }
            let diary = try await incoming
            let first = DateTools.string(monday)
            let last = DateTools.string(DateTools.day(monday, offset: 6))
            let old = weekCache["\(person.id):\(selected.id):\(first)"] ?? snapshot
            let sameAccount = old?.studentId == person.id && old?.groupId == selected.id
            let savedLessons = sameAccount ? (old?.lessons ?? []).filter { !diary.dates.contains($0.date) && $0.date >= first && $0.date <= last } : []
            let savedHomework = sameAccount ? (old?.homework ?? []).filter { !diary.dates.contains($0.date) && $0.date >= first && $0.date <= last } : []
            let loaded = Snapshot(students: students, studentId: person.id, groups: groups, groupId: selected.id,
                                  lessons: (diary.lessons + savedLessons).sorted { $0.date == $1.date ? $0.number < $1.number : $0.date < $1.date },
                                  homework: diary.homework + savedHomework, marks: newBook?.subjects.flatMap(\.marks) ?? [],
                                  syncedAt: .now, from: first, to: last, refreshedDates: diary.dates, gradePeriods: periods)
            self.snapshot = loaded
            weekCache["\(person.id):\(selected.id):\(first)"] = loaded
            if let newBook { book = newBook; selectedPeriod = newBook.period.key; await saveBook() }
            if let current = await vault.session(for: accountID) {
                try? await vault.setSession(SessionArchive(cookies: await client.cookies(), principal: context.principal, userAgent: current.userAgent), for: accountID)
            }
            needsLogin = false
            await saveSnapshot()
        } catch {
            self.error = error.localizedDescription
            if case SiteError.login = error { needsLogin = true }
        }
    }
    func selectDate(_ value: Date) async {
        selectedDate = value
        guard let snapshot else { return }
        let monday = DateTools.string(DateTools.monday(value))
        if snapshot.from == monday { return }
        if snapshot.demo { await refresh(); return }
        let key = "\(snapshot.studentId):\(snapshot.groupId):\(monday)"
        if let cached = weekCache[key] {
            self.snapshot = cached
            return
        }
        if let cached = try? await vault.read(Snapshot.self, name: "week_\(monday)", account: accountID),
           cached.studentId == snapshot.studentId && cached.groupId == snapshot.groupId {
            self.snapshot = cached
            weekCache[key] = cached
        }
        await loadWeek()
    }
    private func loadWeek() async {
        guard let client = website, let snapshot,
              let group = snapshot.group else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let monday = DateTools.monday(selectedDate)
            let incoming = try await client.diary(person: snapshot.studentId, school: group.schoolId, monday: monday)
            let first = DateTools.string(monday)
            let previous = weekCache["\(snapshot.studentId):\(snapshot.groupId):\(first)"]
            var updated = snapshot
            updated.lessons = incoming.lessons + (previous?.lessons ?? []).filter { !incoming.dates.contains($0.date) }
            updated.homework = incoming.homework + (previous?.homework ?? []).filter { !incoming.dates.contains($0.date) }
            updated.from = first
            updated.to = DateTools.string(DateTools.day(monday, offset: 6))
            updated.refreshedDates = incoming.dates
            updated.syncedAt = .now
            self.snapshot = updated
            weekCache["\(snapshot.studentId):\(snapshot.groupId):\(first)"] = updated
            try? await vault.save(updated, name: "week_\(first)", account: accountID)
        } catch { self.error = error.localizedDescription }
    }
    func loadGrades(_ key: String? = nil) async {
        guard let snapshot else { return }
        let periodKey = key ?? selectedPeriod
        let period = snapshot.gradePeriods.first { $0.key == periodKey } ??
            snapshot.gradePeriods.first(where: { $0.groupId == snapshot.groupId && $0.isDefault }) ??
            snapshot.gradePeriods.first(where: { !$0.isFinal })
        guard let period else { return }
        selectedPeriod = period.key
        if snapshot.demo { book = DemoData.grades(period); await saveBook(); return }
        guard let client = website else { return }
        gradesLoading = true
        defer { gradesLoading = false }
        do {
            let result = try await client.grades(person: snapshot.studentId, school: period.schoolId,
                                                 group: period.groupId, period: period.id, final: period.isFinal)
            book = try SiteParser.gradeBook(result, student: snapshot.studentId, period: period, catalog: snapshot.gradePeriods)
            await saveBook()
        } catch { self.error = error.localizedDescription }
    }
    func navigate(_ name: String) {
        destination = name
        if name == "Оценки", book?.period.key != selectedPeriod {
            Task { await loadGrades() }
        }
    }
    func setHomeworkDone(_ item: Homework) {
        guard let snapshot else { return }
        let key = item.key(snapshot.studentId)
        updatePreferences { p in
            if p.completed.contains(key) { p.completed.remove(key) } else { p.completed.insert(key) }
        }
    }
    func addHomework(subjectId: Int64, subject: String, date: Date, text: String) {
        guard let snapshot else { return }
        updatePreferences { p in
            p.ownHomework.append(OwnHomework(id: Int64(Date.now.timeIntervalSince1970 * 1000),
                                             studentId: snapshot.studentId, subjectId: subjectId,
                                             subject: subject, date: DateTools.string(date), text: text))
        }
    }
    func deleteHomework(_ item: Homework) {
        updatePreferences { $0.ownHomework.removeAll { $0.id == item.id } }
    }
    func note(_ text: String, date: Date) {
        updatePreferences { $0.notes[DateTools.string(date)] = text }
    }
    func addPrediction(_ value: Int, subject: GradeSubject, date: Date) {
        guard let book, !book.period.isFinal, (1...5).contains(value),
              subject.officialResult(for: book.period) == nil else { return }
        let day = DateTools.string(date)
        if let start = book.dateStart, day < start { return }
        if let end = book.dateFinish, day > end { return }
        updatePreferences { p in
            p.predictions.append(PredictedMark(id: UUID(), studentId: book.studentId,
                                               groupId: book.period.groupId, periodKey: book.period.key,
                                               subjectId: subject.id, subject: subject.name,
                                               date: day, value: value, createdAt: .now))
        }
    }
    func removePrediction(_ id: UUID) {
        updatePreferences { $0.predictions.removeAll { $0.id == id } }
    }
    func exportGradesCSV() -> String {
        guard let book else { return "" }
        func escape(_ raw: String) -> String { "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let rows = [["Предмет", "Дата", "Оценка", "Тип", "Период"]] +
            book.subjects.flatMap { subject in subject.marks.map { mark in
                [subject.name, mark.date, mark.value, mark.type, book.period.title]
            }}
        return "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ";") }.joined(separator: "\r\n")
    }
    func clearCache() async {
        guard let snapshot else { return }
        await vault.remove(name: "snapshot", account: accountID)
        await vault.remove(name: "gradebook", account: accountID)
        for week in weekCache.values {
            await vault.remove(name: "week_\(week.from)", account: accountID)
        }
        weekCache = [:]
        self.snapshot = snapshot.demo ? snapshot : nil
        book = nil
    }
    func logout() async {
        website = nil
        weekCache = [:]
        snapshot = nil
        book = nil
        selectedPeriod = ""
        needsLogin = false
        try? await vault.setSession(nil, for: accountID)
        await vault.remove(name: "snapshot", account: accountID)
        await vault.remove(name: "gradebook", account: accountID)
        updatePreferences { p in p.completed = []; p.notes = [:]; p.ownHomework = []; p.predictions = [] }
    }
    func addAccount() async {
        guard account.entries.count < 5 else { error = "Не больше пяти аккаунтов."; return }
        let id = UUID().uuidString
        account.entries.append(AccountEntry(id: id, label: "Аккаунт \(account.entries.count + 1)"))
        account.selected = id
        try? await vault.saveCatalog(account)
        await openAccount()
        loginPresented = true
    }
    func switchAccount(_ id: String) async {
        guard account.entries.contains(where: { $0.id == id }) else { return }
        account.selected = id
        try? await vault.saveCatalog(account)
        await openAccount()
    }
    func removeAccount(_ id: String) async {
        guard account.entries.count > 1 else { return }
        await vault.erase(account: id)
        account.entries.removeAll { $0.id == id }
        if account.selected == id { account.selected = account.entries[0].id }
        try? await vault.saveCatalog(account)
        await openAccount()
    }
    private func saveSnapshot() async {
        if let snapshot { try? await vault.save(snapshot, name: "snapshot", account: accountID) }
    }
    private func saveBook() async {
        if let book { try? await vault.save(book, name: "gradebook", account: accountID) }
    }
}
enum NotificationCoordinator {
    static func configure(_ settings: NotificationPreferences) {
        guard settings.enabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["homework-reminder", "evening-summary"])
        func request(_ id: String, at minute: Int, title: String, body: String) {
            var date = DateComponents()
            date.hour = minute / 60
            date.minute = minute % 60
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = settings.privateContent ? "Откройте «Мою школу», чтобы посмотреть подробности." : body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
        }
        if settings.reminder { request("homework-reminder", at: settings.reminderAt, title: "Домашнее задание", body: "Проверьте задания на завтра.") }
        if settings.summary { request("evening-summary", at: settings.summaryAt, title: "Школьный день", body: "Посмотрите расписание и оценки.") }
    }
}
