//
//  ProjectManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/29.
//

import Foundation
import Observation

@Observable
class ProjectManager {
    static let shared = ProjectManager()
    
    private let projectsKey = "savedProjects"
    private let currentProjectKey = "currentProjectId"
    
    // Use iCloud key-value store for sync across devices
    private let iCloud = NSUbiquitousKeyValueStore.default
    
    var projects: [Project] = []
    var currentProjectId: UUID?
    
    var currentProject: Project? {
        guard let id = currentProjectId else { return nil }
        return projects.first { $0.id == id }
    }
    
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
        // Handle changes from other devices
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        print("☁️ iCloud sync update received, reason: \(changeReason)")
        
        DispatchQueue.main.async {
            self.loadData()
        }
    }
    
    // MARK: - Data Persistence
    
    private func loadData() {
        // Load projects from iCloud
        if let data = iCloud.data(forKey: projectsKey),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
            print("📁 Loaded \(projects.count) projects from iCloud")
        } else {
            // Fallback: try loading from UserDefaults (migration from old version)
            if let data = UserDefaults.standard.data(forKey: projectsKey),
               let decoded = try? JSONDecoder().decode([Project].self, from: data) {
                projects = decoded
                print("📁 Migrated \(projects.count) projects from UserDefaults to iCloud")
                // Save to iCloud and remove from UserDefaults
                saveData()
                UserDefaults.standard.removeObject(forKey: projectsKey)
            } else {
                projects = []
                print("📁 No existing projects found")
            }
        }
        
        // Load current project selection from iCloud
        if let idString = iCloud.string(forKey: currentProjectKey),
           let id = UUID(uuidString: idString) {
            currentProjectId = id
            print("📁 Current project: \(currentProject?.displayName ?? "nil")")
        } else {
            // Fallback: try loading from UserDefaults
            if let idString = UserDefaults.standard.string(forKey: currentProjectKey),
               let id = UUID(uuidString: idString) {
                currentProjectId = id
                saveData()
                UserDefaults.standard.removeObject(forKey: currentProjectKey)
            } else {
                currentProjectId = nil
                print("📁 No project selected")
            }
        }
    }
    
    private func saveData() {
        // Save projects to iCloud
        if let encoded = try? JSONEncoder().encode(projects) {
            iCloud.set(encoded, forKey: projectsKey)
        }
        
        // Save current selection to iCloud
        if let id = currentProjectId {
            iCloud.set(id.uuidString, forKey: currentProjectKey)
        } else {
            iCloud.removeObject(forKey: currentProjectKey)
        }
        
        // Trigger sync
        iCloud.synchronize()
        print("☁️ Saved to iCloud")
    }
    
    // MARK: - Project Management
    
    func createProject(name: String, emoji: String?) -> Project {
        let project = Project(name: name, emoji: emoji)
        projects.append(project)
        saveData()
        print("📁 Created project: \(project.displayName)")
        return project
    }
    
    func updateProject(_ project: Project, name: String, emoji: String?) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].name = name
        projects[index].emoji = emoji
        saveData()
        print("📁 Updated project: \(projects[index].displayName)")
    }
    
    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        
        // If this was the current project, clear selection
        if currentProjectId == project.id {
            currentProjectId = nil
        }
        
        // Delete all sessions for this project
        StatisticsManager.shared.deleteSessionsForProject(projectId: project.id)
        
        saveData()
        print("📁 Deleted project: \(project.displayName)")
    }
    
    func selectProject(_ project: Project?) {
        currentProjectId = project?.id
        saveData()
        print("📁 Selected project: \(project?.displayName ?? "None")")
    }
    
    // MARK: - Statistics
    
    func totalHoursForProject(_ projectId: UUID) -> Double {
        StatisticsManager.shared.totalHoursForProject(projectId)
    }
}
