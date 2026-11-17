import Foundation

struct Student: Codable, Hashable, Identifiable {
    let id: Int64
    var name: String
}
struct SchoolGroup: Codable, Hashable, Identifiable {
    let id: Int64
    let schoolId: Int64
    let name: String
}
struct HomeworkAttachment: Codable, Hashable, Identifiable {
    let id: Int64
    let name: String
    let url: String
}
struct Lesson: Codable, Hashable, Identifiable {
    let id: Int64
    let subjectId: Int64
    let subject: String
    let date: String
    let number: Int
    var title: String = ""
    var cancelled: Bool = false
    var starts: String = ""
    var ends: String = ""
    var room: String = ""
    var marks: [Mark] = []
}
struct Homework: Codable, Hashable, Identifiable {
    let id: Int64
    let lessonId: Int64
    let subject: String
    var text: String
    let date: String
    var important: Bool = false
    var files: [HomeworkAttachment] = []
    var local: Bool = false
    var links: [String] = []
    func key(_ studentId: Int64) -> String { "\(studentId):\(id)" }
}
struct Mark: Codable, Hashable, Identifiable {
    let id: Int64
    let subject: String
    let value: String
    let date: String
    var type: String = "Mark5"
    var counted: Bool = true
    var subjectId: Int64? = nil
    var lessonId: Int64? = nil
    var numeric: Double? {
        guard type.lowercased() == "mark5", let n = Double(value.replacingOccurrences(of: ",", with: ".")), (1...5).contains(n) else { return nil }
        return n
    }
}
struct GradePeriod: Codable, Hashable, Identifiable {
    let id: String
    let groupId: Int64
    let schoolId: Int64
    let studyYear: Int
    let title: String
    let number: Int
    var isFinal: Bool = false
    var isDefault: Bool = false
    var shortName: String? = nil
    var key: String { "\(groupId):\(id)" }
    var yearLabel: String { "\(studyYear)/\(studyYear + 1)" }
}
struct OfficialGrade: Codable, Hashable {
    let kind: String
    let label: String
    let values: [String]
    let periodNumber: Int?
    let periodId: String?
    init(kind: String, label: String, values: [String], periodNumber: Int? = nil, periodId: String? = nil) {
        self.kind = kind; self.label = label; self.values = values
        self.periodNumber = periodNumber; self.periodId = periodId
    }
}
struct Attendance: Codable, Hashable, Identifiable {
    let id: String
    let date: String
    let code: String
    let label: String
}
struct GradeSubject: Codable, Hashable, Identifiable {
    let id: Int64
    let name: String
    var marks: [Mark] = []
    var average: String? = nil
    var weightedAverage: String? = nil
    var results: [OfficialGrade] = []
    var attendance: [Attendance] = []
    var displayAverage: String? { weightedAverage ?? average ?? Analytics.score(Analytics.average(marks)) }
    func officialResult(for period: GradePeriod) -> OfficialGrade? {
        guard !period.isFinal else { return nil }
        return results.first {
            guard ["Period", "Quarter", "Trimester", "Semester", "HalfYear", "Module"].contains($0.kind) else { return false }
            return ($0.periodId == nil || $0.periodId == period.id) &&
                   ($0.periodNumber == nil || $0.periodNumber == period.number) &&
                   !$0.values.isEmpty
        }
    }
}
struct GradeBook: Codable, Hashable {
    let studentId: Int64
    let period: GradePeriod
    let subjects: [GradeSubject]
    let syncedAt: Date
    var dateStart: String? = nil
    var dateFinish: String? = nil
}
struct Snapshot: Codable, Hashable {
    var students: [Student] = []
    var studentId: Int64 = 0
    var groups: [SchoolGroup] = []
    var groupId: Int64 = 0
    var lessons: [Lesson] = []
    var homework: [Homework] = []
    var marks: [Mark] = []
    var syncedAt: Date = .now
    var from: String = ""
    var to: String = ""
    var demo: Bool = false
    var refreshedDates: Set<String> = []
    var gradePeriods: [GradePeriod] = []
    var student: Student? { students.first { $0.id == studentId } }
    var group: SchoolGroup? { groups.first { $0.id == groupId } }
}
struct OwnHomework: Codable, Hashable, Identifiable {
    let id: Int64
    let studentId: Int64
    let subjectId: Int64
    let subject: String
    let date: String
    var text: String
    func asHomework(lessonId: Int64 = 0) -> Homework {
        Homework(id: id, lessonId: lessonId, subject: subject, text: text, date: date, local: true)
    }
}
struct PredictedMark: Codable, Hashable, Identifiable {
    let id: UUID
    let studentId: Int64
    let groupId: Int64
    let periodKey: String
    let subjectId: Int64
    let subject: String
    let date: String
    let value: Int
    let createdAt: Date
    var active: Bool { Date.now.timeIntervalSince(createdAt) < 7 * 86400 && createdAt <= .now }
}
struct BellTime: Codable, Hashable {
    var start: String
    var end: String
}
struct Appearance: Codable, Hashable {
    var palette = "forest"
    var accent = "#267953"
    var secondary = "#467B69"
    var amoled = false
    var highContrast = false
    var font = "sans"
    var compact = false
    var rounding: Double = 22
    var frostedNavigation = true
    var reduceMotion = false
    var freeDiaryScroll = false
    var diaryZoom = false
    var diaryScale: Double = 1
    var freeGradesScroll = false
    var gradesZoom = false
    var gradesScale: Double = 1
}
struct NotificationPreferences: Codable, Hashable {
    var enabled = false
    var marks = true
    var quarterMarks = true
    var homework = true
    var schedule = true
    var reminder = true
    var summary = true
    var quiet = true
    var quietFrom = 22 * 60
    var quietTo = 7 * 60
    var reminderAt = 18 * 60
    var summaryAt = 20 * 60
    var weekdaysOnly = false
    var privateContent = true
    var intervalMinutes = 60
}
struct DiaryOpening: Codable, Hashable {
    var enabled = false
    var delayMinutes = 60
    var mode = "afterLessons"
    var atMinute = 18 * 60
    var days: Set<Int> = Set(1...7)
}
struct Preferences: Codable, Hashable {
    var theme = "system"
    var appearance = Appearance()
    var notifications = NotificationPreferences()
    var completed: Set<String> = []
    var notes: [String: String] = [:]
    var ownHomework: [OwnHomework] = []
    var predictions: [PredictedMark] = []
    var startScreen = "Главная"
    var opening = DiaryOpening()
    var bellTimes: [Int: BellTime] = [:]
    var slotTimesEnabled = false
    func homework(for snapshot: Snapshot) -> [Homework] {
        snapshot.homework + ownHomework.filter { $0.studentId == snapshot.studentId }.map { own in
            let lesson = snapshot.lessons.first { $0.date == own.date && ($0.subjectId == own.subjectId || $0.subject == own.subject) }
            return own.asHomework(lessonId: lesson?.id ?? 0)
        }
    }
}
enum Analytics {
    static func average(_ marks: [Mark]) -> Double? {
        let values = marks.filter(\.counted).compactMap(\.numeric)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    static func score(_ number: Double?) -> String? { number.map { String(format: "%.2f", $0) } }
    static func fivesToTarget(_ marks: [Mark], target: Double) -> Int? {
        let values = marks.filter(\.counted).compactMap(\.numeric)
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        if average >= target { return 0 }
        guard target > 0 && target < 5 else { return nil }
        return max(0, Int(ceil((target * Double(values.count) - values.reduce(0, +)) / (5 - target))))
    }
}
enum DateTools {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ raw: String) -> Date? {
        guard raw.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: String(raw.prefix(10)))
    }
    static func day(_ date: Date, offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: date) ?? date }
    static func monday(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        return day(date, offset: -(weekday + 5) % 7)
    }
    static func unixUTC(_ date: Date) -> Int64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return Int64(utc.date(from: components)?.timeIntervalSince1970 ?? date.timeIntervalSince1970)
    }
    static func siteDate(_ value: String) -> String {
        if let timestamp = Double(value), let date = Optional(Date(timeIntervalSince1970: timestamp)) {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let c = utc.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        return String(value.prefix(10))
    }
    static func title(_ date: Date, pattern: String = "d MMMM, EEEE") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
enum DemoData {
    static let subjects = ["Алгебра", "Геометрия", "Русский язык", "Литература", "Английский язык", "История", "География", "Физика", "Информатика", "Биология"]
    static let tasks = [
        "§ 12, № 245 и 247. Решить уравнения и проверить корни.",
        "Подготовиться к контрольной работе. Повторить признаки равенства треугольников.",
        "Упражнение 138. Выписать предложения с причастным оборотом.",
        "Прочитать главы 5–7. Подготовить характеристику главного героя.",
        "Student’s Book, p. 42: exercises 3–5. Выучить новые слова.",
        "§ 8, ответить на вопросы после параграфа.", "Заполнить контурную карту.",
        "Лабораторная работа: оформить выводы в тетради.",
        "Написать алгоритм поиска максимума в массиве.", "Нарисовать строение клетки."
    ]
    static func periods() -> [GradePeriod] {
        let components = DateTools.calendar.dateComponents([.year, .month], from: .now)
        let year = (components.year ?? 2026) - ((components.month ?? 9) < 9 ? 1 : 0)
        let month = components.month ?? 9
        let selected = month >= 9 ? (month <= 10 ? 0 : 1) : (month <= 3 ? 2 : 3)
        return (0..<4).map { GradePeriod(id: "demo-\($0)", groupId: 1, schoolId: 1, studyYear: year, title: "\($0 + 1) четверть", number: $0, isDefault: $0 == selected) }
           + [GradePeriod(id: "final", groupId: 1, schoolId: 1, studyYear: year, title: "Итоги за год", number: 99, isFinal: true)]
    }
    static func snapshot(_ date: Date = .now, days: Int = 30) -> Snapshot {
        let monday = DateTools.monday(date)
        var lessons: [Lesson] = []
        var homework: [Homework] = []
        for d in 0..<6 {
            for n in 0..<6 {
                let index = (n + d * 2) % subjects.count
                let id = Int64(d * 10 + n + 1)
                let lessonDate = DateTools.string(DateTools.day(monday, offset: d))
                lessons.append(Lesson(id: id, subjectId: Int64(index + 1), subject: subjects[index], date: lessonDate, number: n + 1,
                                      title: ["Закрепление материала", "Практическая работа", "Новая тема"][(d+n)%3],
                                      starts: String(format: "%02d:%02d", (480+n*50)/60, (480+n*50)%60),
                                      ends: String(format: "%02d:%02d", (520+n*50)/60, (520+n*50)%60)))
                if n != 2 && n != 5 {
                    homework.append(Homework(id: id + 1000, lessonId: id, subject: subjects[index], text: tasks[index], date: lessonDate, important: index == 1))
                }
            }
        }
        let marks: [Mark] = subjects.enumerated().flatMap { i, name in
            (0..<8).map { n in
                Mark(id: Int64(i*100+n+1), subject: name, value: (i+n)%5 == 0 ? "4" : (i+n)%11 == 0 ? "3" : "5",
                     date: DateTools.string(DateTools.day(.now, offset: -n*3)))
            }
        }
        return Snapshot(students: [Student(id: 1, name: "Даниил")], studentId: 1,
                        groups: [SchoolGroup(id: 1, schoolId: 1, name: "9 «А»")], groupId: 1,
                        lessons: lessons, homework: homework, marks: marks,
                        from: DateTools.string(monday), to: DateTools.string(DateTools.day(monday, offset: 6)),
                        demo: true, refreshedDates: Set((0..<7).map { DateTools.string(DateTools.day(monday, offset: $0)) }),
                        gradePeriods: periods())
    }
    static func grades(_ period: GradePeriod) -> GradeBook {
        let subjects: [GradeSubject] = self.subjects.enumerated().map { i, subject in
            let marks = (0..<8).map { n in
                Mark(id: Int64(i * 100 + n + 1), subject: subject, value: (i+n)%5 == 0 ? "4" : "5",
                     date: DateTools.string(DateTools.day(.now, offset: -n*3)))
            }
            let results: [OfficialGrade] = period.isFinal ?
              (0..<4).map { OfficialGrade(kind: "Period", label: "\($0 + 1) четверть", values: [(i+$0)%3 == 0 ? "4" : "5"], periodNumber: $0) }
              + [OfficialGrade(kind: "Year", label: "Годовая", values: [i%4 == 0 ? "4" : "5"]),
                 OfficialGrade(kind: "Final", label: "Итоговая", values: [i%4 == 0 ? "4" : "5"])]
              : (i == 0 ? [OfficialGrade(kind: "Period", label: period.title, values: ["5"], periodNumber: period.number)] : [])
            return GradeSubject(id: Int64(i+1), name: subject, marks: period.isFinal ? [] : marks,
                                average: Analytics.score(Analytics.average(marks)), results: results)
        }
        return GradeBook(studentId: 1, period: period, subjects: subjects, syncedAt: .now)
    }
}
