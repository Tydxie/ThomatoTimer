//
//  StatisticsManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import Observation

struct SessionRecord: Codable {
    let date: Date
    let type: SessionType
    let durationMinutes: Int
    let projectId: UUID? // Optional - sessions can be unassigned
    
    enum SessionType: String, Codable {
        case work
        case shortBreak
        case longBreak
    }
}

@Observable
class StatisticsManager {
    static let shared = StatisticsManager()
    
    private let sessionsKey = "completedSessions"
    private let firstUseKey = "firstUseDate"
    
    // Use iCloud key-value store for sync across devices
    private let iCloud = NSUbiquitousKeyValueStore.default
    
    var sessions: [SessionRecord] = []
    var firstUseDate: Date?
    
    private init() {
        // Listen for iCloud changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidUpdate),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloud
        )
        
        // Trigger initial sync
        iCloud.synchronize()
        loadData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - iCloud Sync
    
    @objc private func iCloudDidUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        print("☁️ Statistics iCloud sync update received, reason: \(changeReason)")
        
        DispatchQueue.main.async {
            self.loadData()
        }
    }
    
    // MARK: - Data Persistence
    
    private func loadData() {
        // Load sessions from iCloud
        if let data = iCloud.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded
            print("📊 Loaded \(sessions.count) sessions from iCloud")
        } else {
            // Fallback: try loading from UserDefaults (migration from old version)
            if let data = UserDefaults.standard.data(forKey: sessionsKey),
               let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
                sessions = decoded
                print("📊 Migrated \(sessions.count) sessions from UserDefaults to iCloud")
                saveData()
                UserDefaults.standard.removeObject(forKey: sessionsKey)
            }
        }
        
        // Load first use date from iCloud
        if let timestamp = iCloud.object(forKey: firstUseKey) as? Double {
            firstUseDate = Date(timeIntervalSince1970: timestamp)
        } else {
            // Fallback: try loading from UserDefaults
            if let date = UserDefaults.standard.object(forKey: firstUseKey) as? Date {
                firstUseDate = date
                iCloud.set(date.timeIntervalSince1970, forKey: firstUseKey)
                iCloud.synchronize()
                UserDefaults.standard.removeObject(forKey: firstUseKey)
            } else {
                // First time using app
                firstUseDate = Date()
                iCloud.set(firstUseDate!.timeIntervalSince1970, forKey: firstUseKey)
                iCloud.synchronize()
            }
        }
    }
    
    private func saveData() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            iCloud.set(encoded, forKey: sessionsKey)
            iCloud.synchronize()
            print("☁️ Saved \(sessions.count) sessions to iCloud")
        }
    }
    
    // MARK: - Logging Sessions
    
    func logSession(type: SessionRecord.SessionType, durationMinutes: Int, projectId: UUID?) {
        let session = SessionRecord(
            date: Date(),
            type: type,
            durationMinutes: durationMinutes,
            projectId: projectId
        )
        sessions.append(session)
        saveData()
        print("📊 Logged session: \(type.rawValue) - \(durationMinutes) min - Project: \(projectId?.uuidString ?? "None")")
    }
    
    func deleteSessionsForProject(projectId: UUID) {
        sessions.removeAll { $0.projectId == projectId }
        saveData()
        print("📊 Deleted all sessions for project: \(projectId)")
    }
    
    // MARK: - Statistics Calculations
    
    func stats(for period: StatsPeriod) -> SessionStats {
        let filteredSessions = sessions.filter { session in
            period.includes(session.date)
        }
        
        let workSessions = filteredSessions.filter { $0.type == .work }
        let totalWorkMinutes = workSessions.reduce(0) { $0 + $1.durationMinutes }
        let totalBreakMinutes = filteredSessions.filter { $0.type == .shortBreak || $0.type == .longBreak }
            .reduce(0) { $0 + $1.durationMinutes }
        
        return SessionStats(
            workSessionsCompleted: workSessions.count,
            totalWorkMinutes: totalWorkMinutes,
            totalBreakMinutes: totalBreakMinutes,
            period: period
        )
    }
    
    // MARK: - Project-Based Statistics
    
    func projectBreakdown(for period: StatsPeriod) -> [UUID: Int] {
        let filteredSessions = sessions.filter { session in
            period.includes(session.date) && session.type == .work
        }
        
        var breakdown: [UUID: Int] = [:]
        
        for session in filteredSessions {
            if let projectId = session.projectId {
                breakdown[projectId, default: 0] += session.durationMinutes
            }
        }
        
        return breakdown
    }
    
    func totalMinutesForProject(_ projectId: UUID, period: StatsPeriod) -> Int {
        sessions
            .filter { $0.projectId == projectId && $0.type == .work && period.includes($0.date) }
            .reduce(0) { $0 + $1.durationMinutes }
    }
    
    func totalHoursForProject(_ projectId: UUID) -> Double {
        let minutes = totalMinutesForProject(projectId, period: .allTime)
        return Double(minutes) / 60.0
    }
    
    func unassignedMinutes(for period: StatsPeriod) -> Int {
        sessions
            .filter { $0.projectId == nil && $0.type == .work && period.includes($0.date) }
            .reduce(0) { $0 + $1.durationMinutes }
    }
    
    func daysSinceFirstUse() -> Int {
        guard let firstUse = firstUseDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: firstUse, to: Date()).day ?? 0
    }
}

// MARK: - Supporting Types

enum StatsPeriod {
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case allTime
    
    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .allTime:
            return true
        }
    }
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }
}

struct SessionStats {
    let workSessionsCompleted: Int
    let totalWorkMinutes: Int
    let totalBreakMinutes: Int
    let period: StatsPeriod
    
    var totalHours: Double {
        Double(totalWorkMinutes) / 60.0
    }
    
    var formattedWorkTime: String {
        let hours = totalWorkMinutes / 60
        let minutes = totalWorkMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
