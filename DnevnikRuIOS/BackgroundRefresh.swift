import Foundation
import BackgroundTasks
import UserNotifications
import UIKit

final class MySchoolAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshID = "ru.dnkx.myschool.ios.refresh"
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let job = Task {
                let success = await BackgroundSchoolRefresh.shared.run()
                refresh.setTaskCompleted(success: success)
                Self.schedule()
            }
            refresh.expirationHandler = { job.cancel() }
        }
        Self.schedule()
        return true
    }
    func applicationDidEnterBackground(_ application: UIApplication) {
        Self.schedule()
    }
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date.now.addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* Background refresh is advisory and may not be granted by iOS. */ }
    }
}
actor BackgroundSchoolRefresh {
    static let shared = BackgroundSchoolRefresh()
    private let vault = SecureVault.shared
    func run() async -> Bool {
        do {
            let catalog = await vault.catalog()
            let account = catalog.current
            guard let prefs = try await vault.read(Preferences.self, name: "preferences", account: account),
                  prefs.notifications.enabled,
                  let session = await vault.session(for: account),
                  let old = try await vault.read(Snapshot.self, name: "snapshot", account: account),
                  !old.demo else { return true }
            if Task.isCancelled { return false }
            let network = WebsiteClient(cookies: session.cookies)
            let context = try await network.page()
            guard session.principal.isEmpty || context.principal == session.principal else { return false }
            let person = old.studentId
            let group = old.groups.first { $0.id == old.groupId }
            guard context.students.contains(where: { $0.id == person }),
                  let group,
                  context.groups(for: person).contains(where: { $0.id == group.id }) else { return false }
            let periods = context.periods(for: person, school: group.schoolId)
            let defaultPeriod = periods.first { !$0.isFinal && $0.groupId == group.id && $0.isDefault } ??
                                periods.first { !$0.isFinal && $0.groupId == group.id }
            let date = DateTools.monday(.now)
            let diary = try await network.diary(person: person, school: group.schoolId, monday: date)
            if Task.isCancelled { return false }
            var book: GradeBook?
            if let period = defaultPeriod {
                let response = try await network.grades(person: person, school: period.schoolId,
                                                        group: period.groupId, period: period.id)
                book = try SiteParser.gradeBook(response, student: person, period: period, catalog: periods)
            }
            let first = DateTools.string(date)
            let end = DateTools.string(DateTools.day(date, offset: 6))
            var updated = old
            updated.lessons = diary.lessons + old.lessons.filter {
                $0.date >= first && $0.date <= end && !diary.dates.contains($0.date)
            }
            updated.homework = diary.homework + old.homework.filter {
                $0.date >= first && $0.date <= end && !diary.dates.contains($0.date)
            }
            if let book { updated.marks = book.subjects.flatMap(\.marks) }
            updated.from = first
            updated.to = end
            updated.refreshedDates = diary.dates
            updated.gradePeriods = periods
            updated.syncedAt = .now
            if let book { try await vault.save(book, name: "gradebook", account: account) }
            try await vault.save(updated, name: "snapshot", account: account)
            try await vault.setSession(SessionArchive(cookies: await network.cookies(),
                                                       principal: context.principal,
                                                       userAgent: session.userAgent), for: account)
            if !Task.isCancelled {
                await notifyChanges(before: old, after: updated, oldBook: try await vault.read(GradeBook.self, name: "background-previous-book", account: account),
                                    newBook: book, settings: prefs.notifications)
            }
            if let book { try? await vault.save(book, name: "background-previous-book", account: account) }
            return !Task.isCancelled
        } catch {
            return false
        }
    }
    private func notifyChanges(before old: Snapshot, after updated: Snapshot,
                               oldBook: GradeBook?, newBook: GradeBook?,
                               settings: NotificationPreferences) async {
        let now = Date.now
        let calendar = Calendar.current
        if settings.weekdaysOnly && [1, 7].contains(calendar.component(.weekday, from: now)) { return }
        if settings.quiet {
            let parts = calendar.dateComponents([.hour, .minute], from: now)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let from = settings.quietFrom, to = settings.quietTo
            let quiet = from == to || (from < to ? (minute >= from && minute < to) : (minute >= from || minute < to))
            if quiet { return }
        }
        let center = UNUserNotificationCenter.current()
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            center.getNotificationSettings { status in
                continuation.resume(returning: status.authorizationStatus == .authorized ||
                                    status.authorizationStatus == .provisional)
            }
        }
        guard granted else { return }
        var pending: [(String, String)] = []
        if settings.marks && !old.marks.isEmpty {
            let known = Set(old.marks.map(\.id))
            let added = updated.marks.filter { !known.contains($0.id) }
            if !added.isEmpty {
                let subject = added.first?.subject ?? "Школа"
                pending.append(("Новые оценки · \(added.count)", "\(subject) и другие предметы"))
            }
        }
        if settings.homework && !old.homework.isEmpty {
            let existing = Dictionary(uniqueKeysWithValues: old.homework.map { ($0.id, $0.text) })
            let changed = updated.homework.filter { existing[$0.id] != nil && existing[$0.id] != $0.text }
            let fresh = updated.homework.filter { existing[$0.id] == nil }
            if !changed.isEmpty || !fresh.isEmpty {
                pending.append(("Домашние задания", "Новые или изменённые задания: \(changed.count + fresh.count)"))
            }
        }
        if settings.schedule && !old.lessons.isEmpty {
            let existing = Dictionary(uniqueKeysWithValues: old.lessons.map { ($0.id, $0) })
            let changed = updated.lessons.filter {
                guard let prior = existing[$0.id] else { return true }
                return prior.starts != $0.starts || prior.ends != $0.ends ||
                    prior.cancelled != $0.cancelled || prior.room != $0.room || prior.subject != $0.subject
            }
            if !changed.isEmpty { pending.append(("Расписание изменилось", "\(changed.count) изменений в уроках")) }
        }
        if settings.quarterMarks, let oldBook, let newBook,
           oldBook.period.key == newBook.period.key {
            let previous = Set(oldBook.subjects.flatMap { subject in
                subject.results.map { "\(subject.id):\($0.label):\($0.values.joined(separator: ","))" }
            })
            let additions = newBook.subjects.flatMap { subject in
                subject.results.map { "\(subject.id):\($0.label):\($0.values.joined(separator: ","))" }
            }.filter { !previous.contains($0) }
            if !additions.isEmpty { pending.append(("Итоги периода", "Появились новые итоговые оценки")) }
        }
        for (index, message) in pending.enumerated() {
            let notification = UNMutableNotificationContent()
            notification.title = message.0
            notification.body = settings.privateContent ? "Откройте приложение «Моя школа» для подробностей." : message.1
            notification.sound = .default
            let request = UNNotificationRequest(identifier: "school-change-\(Int(now.timeIntervalSince1970))-\(index)",
                                                content: notification, trigger: nil)
            try? await center.add(request)
        }
    }
}
