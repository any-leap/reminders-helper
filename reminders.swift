import EventKit
import Foundation

let store = EKEventStore()

func requestAccess() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders { g, _ in
            granted = g
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .reminder) { g, _ in
            granted = g
            semaphore.signal()
        }
    }
    semaphore.wait()
    return granted
}

func listLists() {
    let calendars = store.calendars(for: .reminder)
    for cal in calendars.sorted(by: { $0.title < $1.title }) {
        print("\(cal.title)")
    }
}

func listReminders(listName: String, showCompleted: Bool = false) {
    let calendars = store.calendars(for: .reminder)
    guard let cal = calendars.first(where: { $0.title == listName }) else {
        print("错误：找不到列表「\(listName)」")
        return
    }
    let predicate = store.predicateForReminders(in: [cal])
    let semaphore = DispatchSemaphore(value: 0)
    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders = reminders else { semaphore.signal(); return }
        let filtered = showCompleted ? reminders : reminders.filter { !$0.isCompleted }
        for r in filtered.sorted(by: { ($0.dueDateComponents?.date ?? Date.distantFuture) < ($1.dueDateComponents?.date ?? Date.distantFuture) }) {
            let status = r.isCompleted ? "✅" : "⬜"
            let due = r.dueDateComponents?.date.map {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f.string(from: $0)
            } ?? ""
            print("\(status) [\(r.calendarItemIdentifier)] \(r.title ?? "") \(due.isEmpty ? "" : "(\(due))")")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func addReminder(listName: String, title: String, dueDate: String?) {
    let calendars = store.calendars(for: .reminder)
    guard let cal = calendars.first(where: { $0.title == listName }) else {
        print("错误：找不到列表「\(listName)」")
        return
    }
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.calendar = cal
    if let dueDate = dueDate {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        if let date = f.date(from: dueDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let alarm = EKAlarm(absoluteDate: date)
            reminder.addAlarm(alarm)
        }
    }
    do {
        try store.save(reminder, commit: true)
        print("已创建：\(title)")
    } catch {
        print("错误：\(error.localizedDescription)")
    }
}

func completeReminder(identifier: String) {
    guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
        print("错误：找不到提醒")
        return
    }
    reminder.isCompleted = true
    reminder.completionDate = Date()
    do {
        try store.save(reminder, commit: true)
        print("已完成：\(reminder.title ?? "")")
    } catch {
        print("错误：\(error.localizedDescription)")
    }
}

func completeByKeyword(listName: String, keyword: String) {
    let calendars = store.calendars(for: .reminder)
    guard let cal = calendars.first(where: { $0.title == listName }) else {
        print("错误：找不到列表「\(listName)」")
        return
    }
    let predicate = store.predicateForReminders(in: [cal])
    let semaphore = DispatchSemaphore(value: 0)
    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders = reminders else { semaphore.signal(); return }
        let matched = reminders.filter { !$0.isCompleted && ($0.title ?? "").contains(keyword) }
        for r in matched {
            r.isCompleted = true
            r.completionDate = Date()
            do {
                try store.save(r, commit: true)
                print("已完成：\(r.title ?? "")")
            } catch {
                print("错误：\(error.localizedDescription)")
            }
        }
        if matched.isEmpty {
            print("未找到包含「\(keyword)」的未完成提醒")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func searchReminders(keyword: String) {
    let calendars = store.calendars(for: .reminder)
    let predicate = store.predicateForReminders(in: calendars)
    let semaphore = DispatchSemaphore(value: 0)
    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders = reminders else { semaphore.signal(); return }
        let matched = reminders.filter { ($0.title ?? "").contains(keyword) }
        for r in matched {
            let status = r.isCompleted ? "✅" : "⬜"
            let listName = r.calendar.title
            print("\(status) [\(listName)] \(r.title ?? "")")
        }
        if matched.isEmpty {
            print("未找到包含「\(keyword)」的提醒")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func deleteReminder(identifier: String) {
    guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
        print("错误：找不到提醒")
        return
    }
    let title = reminder.title ?? ""
    do {
        try store.remove(reminder, commit: true)
        print("已删除：\(title)")
    } catch {
        print("错误：\(error.localizedDescription)")
    }
}

func printUsage() {
    print("""
    reminders - 提醒事项管理工具

    用法:
      reminders lists                          列出所有列表
      reminders list <列表名>                   列出未完成提醒
      reminders list <列表名> --all             列出所有提醒（含已完成）
      reminders add <列表名> <标题> [日期时间]    创建提醒（日期格式: 2026-03-19 10:00）
      reminders done <ID>                      按ID完成提醒
      reminders done-keyword <列表名> <关键词>   按关键词完成提醒
      reminders search <关键词>                 搜索所有列表
      reminders delete <ID>                    删除提醒
    """)
}

// Main
guard requestAccess() else {
    print("错误：无法访问提醒事项，请在系统设置中授权")
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    printUsage()
    exit(0)
}

switch args[1] {
case "lists":
    listLists()
case "list":
    guard args.count >= 3 else { print("用法: reminders list <列表名>"); exit(1) }
    let showAll = args.contains("--all")
    listReminders(listName: args[2], showCompleted: showAll)
case "add":
    guard args.count >= 4 else { print("用法: reminders add <列表名> <标题> [日期时间]"); exit(1) }
    let due = args.count >= 6 ? "\(args[4]) \(args[5])" : (args.count >= 5 ? args[4] : nil)
    addReminder(listName: args[2], title: args[3], dueDate: due)
case "done":
    guard args.count >= 3 else { print("用法: reminders done <ID>"); exit(1) }
    completeReminder(identifier: args[2])
case "done-keyword":
    guard args.count >= 4 else { print("用法: reminders done-keyword <列表名> <关键词>"); exit(1) }
    completeByKeyword(listName: args[2], keyword: args[3])
case "search":
    guard args.count >= 3 else { print("用法: reminders search <关键词>"); exit(1) }
    searchReminders(keyword: args[2])
case "delete":
    guard args.count >= 3 else { print("用法: reminders delete <ID>"); exit(1) }
    deleteReminder(identifier: args[2])
default:
    printUsage()
}
