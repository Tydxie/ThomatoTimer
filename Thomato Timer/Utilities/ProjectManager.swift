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
    
    var projects: [Project] = []
    var currentProjectId: UUID?
    
    var currentProject: Project? {
        guard let id = currentProjectId else { return nil }
        return projects.first { $0.id == id }
    }
    
    private init() {
        loadData()
    }
    
    // MARK: - Data Persistence
    
    private func loadData() {
        // Load projects
        if let data = UserDefaults.standard.data(forKey: projectsKey),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
            print("📁 Loaded \(projects.count) projects")
        } else {
            projects = []
            print("📁 No existing projects found")
        }
        
        // Load current project selection
        if let idString = UserDefaults.standard.string(forKey: currentProjectKey),
           let id = UUID(uuidString: idString) {
            currentProjectId = id
            print("📁 Current project: \(currentProject?.displayName ?? "nil")")
        } else {
            currentProjectId = nil
            print("📁 No project selected")
        }
    }
    
    private func saveData() {
        // Save projects
        if let encoded = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(encoded, forKey: projectsKey)
        }
        
        // Save current selection
        if let id = currentProjectId {
            UserDefaults.standard.set(id.uuidString, forKey: currentProjectKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentProjectKey)
        }
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
