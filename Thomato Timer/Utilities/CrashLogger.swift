//
//  CrashLogger.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/13.
//

import Foundation
#if os(iOS)
import UIKit
#endif

class CrashLogger {
    static let shared = CrashLogger()
    
    private let crashLogsKey = "thomato_crash_logs"
    private let maxLogs = 10
    
    func setup() {
        logEvent("App launched - Version: \(appVersion())")
        
        NSSetUncaughtExceptionHandler { exception in
            let crashLog = """
            ========== CRASH REPORT ==========
            App Version: \(CrashLogger.shared.appVersion())
            Date: \(Date())
            iOS Version: \(CrashLogger.shared.iOSVersion())
            Device: \(CrashLogger.shared.deviceModel())
            Exception: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "Unknown")
            
            Stack Trace:
            \(exception.callStackSymbols.joined(separator: "\n"))
            ==================================
            """
            
            print("CRASH DETECTED:")
            print(crashLog)
            
            CrashLogger.shared.saveCrashLog(crashLog)
        }
    }
    
    func logEvent(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        print("[\(timestamp)] \(message)")
        
        var events = UserDefaults.standard.stringArray(forKey: "app_events") ?? []
        events.append("[\(timestamp)] \(message)")
        
        if events.count > 50 {
            events = Array(events.suffix(50))
        }
        
        UserDefaults.standard.set(events, forKey: "app_events")
        
        let verification = UserDefaults.standard.stringArray(forKey: "app_events")?.count ?? 0
        print("Event logged. Total events now: \(verification)")
    }
    
    private func saveCrashLog(_ log: String) {
        var logs = UserDefaults.standard.stringArray(forKey: crashLogsKey) ?? []
        logs.append(log)
        
        if logs.count > maxLogs {
            logs = Array(logs.suffix(maxLogs))
        }
        
        UserDefaults.standard.set(logs, forKey: crashLogsKey)
        UserDefaults.standard.synchronize()
    }
    
    func getCrashLogs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: crashLogsKey) ?? []
    }
    
    func getAppEvents() -> [String] {
        return UserDefaults.standard.stringArray(forKey: "app_events") ?? []
    }
    
    func clearCrashLogs() {
        UserDefaults.standard.removeObject(forKey: crashLogsKey)
        UserDefaults.standard.removeObject(forKey: "app_events")
        UserDefaults.standard.synchronize()
    }
    
    func getCrashCount() -> Int {
        return getCrashLogs().count
    }
    
    func exportLogs() -> String {
        let crashes = getCrashLogs()
        let events = getAppEvents()
        
        return """
        THOMATO TIMER DEBUG REPORT
        Generated: \(Date())
        App Version: \(appVersion())
        iOS Version: \(iOSVersion())
        Device: \(deviceModel())
        
        ===== APP EVENTS (Last 50) =====
        \(events.joined(separator: "\n"))
        
        ===== CRASH LOGS (\(crashes.count)) =====
        \(crashes.joined(separator: "\n\n"))
        
        ===== END REPORT =====
        """
    }
    
    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
    
    private func iOSVersion() -> String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #else
        return "macOS"
        #endif
    }
    
    private func deviceModel() -> String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }
}
