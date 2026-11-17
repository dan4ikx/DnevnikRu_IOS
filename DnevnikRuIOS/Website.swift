import Foundation

enum SiteError: LocalizedError {
    case login
    case unavailable(String)
    case changed(String)
    case invalidSession
    var errorDescription: String? {
        switch self {
        case .login: "Войдите в Дневник.ру или восстановите веб-сессию."
        case .invalidSession: "Аккаунт сайта изменился. Подтвердите вход повторно."
        case .unavailable(let message), .changed(let message): message
        }
    }
}
enum JSON {
    static func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    static func array(_ value: Any?) -> [[String: Any]] { (value as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
    static func string(_ value: Any?, fallback: String = "") -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return fallback
    }
    static func id(_ value: Any?) -> Int64 { Int64(string(value)) ?? 0 }
    static func int(_ value: Any?, fallback: Int = 0) -> Int { Int(string(value)) ?? fallback }
    static func bool(_ value: Any?, fallback: Bool = false) -> Bool {
        if let boolean = value as? Bool { return boolean }
        if let string = value as? String { return ["true", "1"].contains(string.lowercased()) }
        return fallback
    }
}
struct SiteContext {
    let principal: String
    let memberships: [[String: Any]]
    var students: [Student] {
        var result: [Student] = []
        for m in memberships where JSON.bool(m["hasAccess"], fallback: true) {
            let id = JSON.id(m["personId"])
            if id != 0 && !result.contains(where: { $0.id == id }) {
                result.append(Student(id: id, name: JSON.string(m["firstName"], fallback: "Ученик")))
            }
        }
        return result
    }
    func groups(for student: Int64) -> [SchoolGroup] {
        var groups: [SchoolGroup] = []
        for m in memberships where JSON.id(m["personId"]) == student {
            for g in JSON.array(m["groups"]) {
                let id = JSON.id(g["groupId"])
                if id != 0 && !groups.contains(where: { $0.id == id }) {
                    groups.append(SchoolGroup(id: id, schoolId: JSON.id(m["schoolId"]),
                                              name: JSON.string(g["groupName"], fallback: "Класс")))
                }
            }
        }
        return groups
    }
    func periods(for student: Int64, school: Int64) -> [GradePeriod] {
        var result: [GradePeriod] = []
        for membership in memberships where JSON.id(membership["personId"]) == student && JSON.id(membership["schoolId"]) == school {
            for h in JSON.array(membership["groupHistory"]) {
                let group = JSON.id(h["id"])
                let year = JSON.int(h["studyYear"])
                guard group != 0, year != 0 else { continue }
                for (index, p) in JSON.array(h["periods"]).enumerated() {
                    let id = JSON.string(p["id"])
                    guard !id.isEmpty else { continue }
                    let number = JSON.int(p["number"], fallback: index)
                    let name = JSON.string(p["name"], fallback: "\(number + 1) учебный период")
                    let period = GradePeriod(id: id, groupId: group, schoolId: school, studyYear: year,
                                             title: name, number: number,
                                             isDefault: JSON.bool(p["isDefault"]),
                                             shortName: JSON.string(p["shortName"]))
                    if !result.contains(where: { $0.key == period.key }) { result.append(period) }
                }
                let final = GradePeriod(id: "final", groupId: group, schoolId: school, studyYear: year,
                                        title: "Итоги за год", number: Int.max, isFinal: true)
                if !result.contains(where: { $0.key == final.key }) { result.append(final) }
            }
        }
        return result.sorted { $0.studyYear == $1.studyYear ? ($0.groupId == $1.groupId ? $0.number < $1.number : $0.groupId < $1.groupId) : $0.studyYear > $1.studyYear }
    }
}
enum SiteParser {
    static func context(_ html: String) throws -> SiteContext {
        let marker = "window.__MARKS__INITIAL__STATE__"
        guard let range = html.range(of: marker), let first = html[range.upperBound...].firstIndex(of: "{") else {
            throw SiteError.changed("Сайт не передал данные профиля. Проверьте вход через веб-сессию.")
        }
        var nesting = 0
        var inside = false
        var escaped = false
        var ending: String.Index?
        for index in html[first...].indices {
            let character = html[index]
            if inside {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inside = false }
            } else {
                if character == "\"" { inside = true }
                else if character == "{" { nesting += 1 }
                else if character == "}" {
                    nesting -= 1
                    if nesting == 0 { ending = html.index(after: index); break }
                }
            }
        }
        guard let ending,
              let payload = String(html[first..<ending]).data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw SiteError.changed("Не удалось прочитать данные страницы Дневник.ру.")
        }
        let context = JSON.object(root["context"])
        let memberships = JSON.array(context["schoolMemberships"])
        guard !memberships.isEmpty else { throw SiteError.changed("К аккаунту не привязаны доступные школьные профили.") }
        return SiteContext(principal: JSON.string(context["userId"]), memberships: memberships)
    }
    static func plain(_ html: String) -> String {
        let breaks = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let stripped = breaks.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func date(_ value: Any?) -> String {
        DateTools.siteDate(JSON.string(value))
    }
    static func lessonMarks(_ array: [[String: Any]], subject: String, subjectId: Int64, lessonId: Int64, date: String) -> [Mark] {
        array.compactMap { m in
            let id = JSON.id(m["id"])
            guard id != 0 else { return nil }
            return Mark(id: id, subject: subject, value: JSON.string(m["value"]), date: date,
                        type: JSON.string(m["type"], fallback: "Unknown"),
                        subjectId: subjectId, lessonId: lessonId)
        }
    }
    static func diary(_ json: [String: Any]) throws -> (lessons: [Lesson], homework: [Homework], dates: Set<String>) {
        guard json["days"] is [Any] else { throw SiteError.changed("Сайт изменил формат расписания.") }
        var lessons: [Lesson] = []
        var homework: [Homework] = []
        var dates = Set<String>()
        for day in JSON.array(json["days"]) {
            let date = self.date(day["date"])
            guard DateTools.date(date) != nil else { throw SiteError.changed("Некорректная дата в расписании.") }
            dates.insert(date)
            for entry in JSON.array(day["lessons"]) where !JSON.bool(entry["isEmpty"]) {
                let id = JSON.id(entry["id"])
                guard id != 0 else { continue }
                let subject = JSON.object(entry["subject"])
                let hours = JSON.object(entry["hours"])
                let sid = JSON.id(subject["id"])
                let name = JSON.string(subject["name"], fallback: "Предмет")
                func time(_ h: String, _ m: String) -> String {
                    let hour = JSON.int(hours[h], fallback: -1)
                    let minute = JSON.int(hours[m], fallback: -1)
                    return (0...23).contains(hour) && (0...59).contains(minute) ? String(format: "%02d:%02d", hour, minute) : ""
                }
                let lesson = Lesson(id: id, subjectId: sid, subject: name, date: date,
                                    number: JSON.int(entry["number"]), title: plain(JSON.string(entry["theme"])),
                                    cancelled: JSON.bool(entry["isCanceled"]),
                                    starts: time("startHour", "startMinute"), ends: time("endHour", "endMinute"),
                                    room: JSON.string(entry["place"]),
                                    marks: lessonMarks(JSON.array(entry["marks"]), subject: name, subjectId: sid, lessonId: id, date: date))
                lessons.append(lesson)
                let work = JSON.object(entry["homework"])
                if !work.isEmpty {
                    let raw = JSON.string(work["text"])
                    let files = JSON.array(work["attachments"]).map { file in
                        HomeworkAttachment(id: JSON.id(file["fileId"]),
                                           name: JSON.string(file["fileName"], fallback: "Вложение") + (JSON.string(file["fileExtension"]).isEmpty ? "" : "." + JSON.string(file["fileExtension"])),
                                           url: JSON.string(file["fileLink"]))
                    }
                    let links = (try? NSRegularExpression(pattern: "https?://[^\\\\s\\\"'<>]+")).map { regex -> [String] in
                        let ns = raw as NSString
                        return regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
                    } ?? []
                    if !plain(raw).isEmpty || !files.isEmpty || !links.isEmpty {
                        homework.append(Homework(id: id, lessonId: id, subject: name, text: plain(raw), date: date,
                                                 important: !JSON.array(entry["importantWorks"]).isEmpty,
                                                 files: files, links: links))
                    }
                }
            }
        }
        let uniqueLessons = Dictionary(grouping: lessons, by: \.id).values.compactMap { $0.first }
        let uniqueHomework = Dictionary(grouping: homework, by: \.id).values.compactMap { $0.first }
        return (uniqueLessons, uniqueHomework, dates)
    }
    static func subjectMarks(_ subject: [String: Any]) -> [Mark] {
        let id = JSON.id(subject["id"])
        let name = JSON.string(subject["name"], fallback: "Предмет")
        return JSON.array(subject["works"]).flatMap { work -> [Mark] in
            guard !JSON.bool(work["isHidden"]),
                  !JSON.bool(JSON.object(work["type"])["isFinalWork"]) else { return [] }
            let counted = JSON.bool(JSON.object(work["type"])["isUsedAtAverageMarkCalculation"])
            return JSON.array(work["marks"]).compactMap { mark in
                let mid = JSON.id(mark["id"])
                guard mid != 0 else { return nil }
                return Mark(id: mid, subject: name, value: JSON.string(mark["value"]), date: date(work["date"]),
                            type: JSON.string(mark["type"], fallback: "Unknown"), counted: counted,
                            subjectId: id, lessonId: JSON.id(work["lessonId"]))
            }
        }
    }
    static func marks(_ json: [String: Any]) throws -> [Mark] {
        guard json["subjects"] is [Any] else { throw SiteError.changed("Изменился формат оценок.") }
        return Array(Dictionary(grouping: JSON.array(json["subjects"]).flatMap(subjectMarks), by: \.id).values.compactMap { $0.first })
    }
    static func gradeBook(_ json: [String: Any], student: Int64, period: GradePeriod, catalog: [GradePeriod]) throws -> GradeBook {
        guard json["subjects"] is [Any] else { throw SiteError.changed("Изменился формат оценок.") }
        let serverPeriod = JSON.string(json["periodId"])
        if !period.isFinal && !serverPeriod.isEmpty && serverPeriod != period.id {
            throw SiteError.changed("Сайт вернул оценки другого учебного периода.")
        }
        let subjects = JSON.array(json["subjects"]).map { item -> GradeSubject in
            let results = JSON.array(item["finalWorks"]).map { work -> OfficialGrade in
                let type = JSON.string(work["type"])
                let number = Int(JSON.string(work["periodNumber"]))
                let pid = JSON.string(work["periodId"])
                let matched = catalog.first { $0.groupId == period.groupId && ($0.id == pid || (pid.isEmpty && $0.number == number)) }
                let label: String
                switch type {
                case "Year": label = "Годовая"
                case "Exam": label = "Экзамен"
                case "Final": label = "Итоговая"
                case "AllRussianTestWork": label = "ВПР"
                default: label = matched?.title ?? JSON.string(work["name"], fallback: period.title)
                }
                let values = (work["marks"] as? [Any] ?? []).compactMap { v -> String? in
                    let raw = v is [String: Any] ? JSON.string(JSON.object(v)["value"]) : JSON.string(v)
                    return raw.isEmpty || raw == "-" || raw == "—" ? nil : raw
                }
                return OfficialGrade(kind: type, label: label, values: values, periodNumber: number, periodId: pid.isEmpty ? nil : pid)
            }
            let attendance = JSON.array(item["lessonLogEntries"]).map { entry -> Attendance in
                let date = self.date(entry["date"])
                let code = JSON.string(entry["value"])
                return Attendance(id: "\(JSON.string(entry["lessonId"])):\(date):\(code)", date: date,
                                  code: code, label: JSON.string(entry["fullName"], fallback: code))
            }
            func avg(_ key: String, _ enabled: Bool) -> String? {
                guard enabled else { return nil }
                let value = item[key]
                let raw = value is [String: Any] ? JSON.string(JSON.object(value)["value"]) : JSON.string(value)
                return raw.isEmpty || raw == "-" ? nil : raw
            }
            return GradeSubject(id: JSON.id(item["id"]), name: JSON.string(item["name"], fallback: "Предмет"),
                                marks: subjectMarks(item), average: avg("average", JSON.bool(json["showAverageMarks"])),
                                weightedAverage: avg("weightedAverage", JSON.bool(json["showAverageWeightedMarks"])),
                                results: results, attendance: attendance)
        }
        return GradeBook(studentId: student, period: period, subjects: subjects, syncedAt: .now,
                         dateStart: date(json["dateStart"]), dateFinish: date(json["dateFinish"]))
    }
}
final class SiteRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = newRequest.url, url.scheme == "https", let host = url.host?.lowercased(),
              host == "dnevnik.ru" || host.hasSuffix(".dnevnik.ru") else {
            completionHandler(nil)
            return
        }
        completionHandler(newRequest)
    }
}
actor WebsiteClient {
    private let session: URLSession
    private let storage: HTTPCookieStorage
    private let guardDelegate = SiteRedirectGuard()
    private let base = URL(string: "https://dnevnik.ru/")!
    init(cookies: [SessionCookie]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "ru.dnkx.myschool.ios.\(UUID().uuidString)")
        configuration.httpCookieStorage = storage
        for cookie in cookies.compactMap(\.asCookie) { storage.setCookie(cookie) }
        session = URLSession(configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
    }
    func cookies() -> [SessionCookie] {
        (storage.cookies ?? []).compactMap(SessionCookie.init)
    }
    private func get(_ path: String, params: [String: String] = [:], expectsJSON: Bool = true) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } +
            (expectsJSON ? [URLQueryItem(name: "timestamp", value: String(Int(Date.now.timeIntervalSince1970 * 1000)))] : [])
        guard let url = components.url else { throw SiteError.unavailable("Неверный адрес запроса.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "GET"
        request.setValue(expectsJSON ? "application/json" : "text/html", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://dnevnik.ru/marks", forHTTPHeaderField: "Referer")
        if expectsJSON { request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.unavailable("Нет ответа сайта.") }
        if http.statusCode == 401 { throw SiteError.login }
        if http.statusCode == 403 { throw SiteError.unavailable("Сайт ограничил доступ. Откройте веб-сессию в профиле.") }
        if http.statusCode == 429 { throw SiteError.unavailable("Сайт ограничил частоту запросов. Повторите позже.") }
        if http.statusCode == 550 { throw SiteError.unavailable("На сайте ведутся технические работы.") }
        guard (200...299).contains(http.statusCode) else { throw SiteError.unavailable("Не удалось загрузить данные сайта (HTTP \(http.statusCode)).") }
        if expectsJSON && (http.mimeType?.lowercased().contains("html") == true ||
                           String(data: data.prefix(100), encoding: .utf8)?.contains("<html") == true) {
            throw SiteError.login
        }
        return data
    }
    func page() async throws -> SiteContext {
        let data = try await get("marks", expectsJSON: false)
        guard let html = String(data: data, encoding: .utf8) else { throw SiteError.changed("Страница сайта не читается.") }
        return try SiteParser.context(html)
    }
    func diary(person: Int64, school: Int64, monday: Date) async throws -> (lessons: [Lesson], homework: [Homework], dates: Set<String>) {
        let end = DateTools.day(monday, offset: 7)
        let data = try await get("api/v2/marks/diary", params: [
            "personId": String(person), "schoolId": String(school),
            "startDate": String(DateTools.unixUTC(monday)),
            "finishDate": String(DateTools.unixUTC(end))
        ])
        return try SiteParser.diary(try decode(data))
    }
    func grades(person: Int64, school: Int64, group: Int64, period: String = "", final: Bool = false) async throws -> [String: Any] {
        let path = final ? "api/v2/marks/final/school/\(school)/person/\(person)" :
                           "api/v2/marks/school/\(school)/person/\(person)"
        var parameters = ["groupId": String(group)]
        if !final { parameters["periodId"] = period }
        let payload = try await get(path, params: parameters)
        return try decode(payload)
    }
    private func decode(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SiteError.changed("Сайт вернул неожиданный формат ответа.")
        }
        return result
    }
}
