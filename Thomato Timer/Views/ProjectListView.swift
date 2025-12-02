//
//  ProjectListView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/29.
//

import SwiftUI

struct ProjectListView: View {
    @State private var projectManager = ProjectManager.shared
    @State private var showingNewProject = false
    @State private var editingProject: Project?
    @State private var showingDeleteConfirmation: Project?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            Group {
                if projectManager.projects.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(projectManager.projects) { project in
                                ProjectCard(
                                    project: project,
                                    onRename: {
                                        editingProject = project
                                    },
                                    onDelete: {
                                        showingDeleteConfirmation = project
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewProject = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
            }
            .sheet(item: $editingProject) { project in
                EditProjectView(project: project)
            }
            .alert("Delete Project", isPresented: .constant(showingDeleteConfirmation != nil)) {
                Button("Cancel", role: .cancel) {
                    showingDeleteConfirmation = nil
                }
                Button("Delete", role: .destructive) {
                    if let project = showingDeleteConfirmation {
                        projectManager.deleteProject(project)
                        showingDeleteConfirmation = nil
                    }
                }
            } message: {
                if let project = showingDeleteConfirmation {
                    Text("Are you sure you want to delete \"\(project.displayName)\"? All tracked hours for this project will be permanently deleted.")
                }
            }
        }
    }
    #endif
    
    // MARK: - macOS Layout
    
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("My Projects")
                    .font(.title)
                    .bold()
                
                Spacer()
                
                Button(action: {
                    showingNewProject = true
                }) {
                    Label("New", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.thTeal)
            }
            .padding()
            
            Divider()
            
            // Project List
            if projectManager.projects.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(projectManager.projects) { project in
                            ProjectCard(
                                project: project,
                                onRename: {
                                    editingProject = project
                                },
                                onDelete: {
                                    showingDeleteConfirmation = project
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingNewProject) {
            NewProjectView()
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project)
        }
        .alert("Delete Project", isPresented: .constant(showingDeleteConfirmation != nil)) {
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = nil
            }
            Button("Delete", role: .destructive) {
                if let project = showingDeleteConfirmation {
                    projectManager.deleteProject(project)
                    showingDeleteConfirmation = nil
                }
            }
        } message: {
            if let project = showingDeleteConfirmation {
                Text("Are you sure you want to delete \"\(project.displayName)\"? All tracked hours for this project will be permanently deleted.")
            }
        }
    }
    #endif
    
    // MARK: - Shared Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No projects yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Create your first project to start tracking your 10,000 hours")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Project Card (Shared)

struct ProjectCard: View {
    let project: Project
    let onRename: () -> Void
    let onDelete: () -> Void
    
    @State private var statsManager = StatisticsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Project name
            Text(project.displayName)
                .font(.title2)
                .bold()
            
            // Progress
            let totalHours = Int(statsManager.totalHoursForProject(project.id))
            let current = Milestone.currentMilestone(for: totalHours)
            
            HStack(spacing: 8) {
                // Current level badge
                HStack(spacing: 4) {
                    Text(current.emoji)
                    Text(current.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
                
                Spacer()
                
                Text("\(totalHours)h")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Progress to next milestone
            if let next = Milestone.nextMilestone(for: totalHours) {
                let progress = Double(totalHours) / Double(next.hours)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Next: \(next.emoji) \(next.title) (\(next.hours)h)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(next.hours - totalHours)h to go")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(Color.thTeal)
                                .frame(width: geometry.size.width * min(progress, 1.0), height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)
                }
            } else {
                Text("🎉 All milestones completed!")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.vertical, 4)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Rename") {
                    onRename()
                }
                .buttonStyle(.bordered)
                .tint(.thTeal)
                
                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - New Project View

struct NewProjectView: View {
    @State private var projectName = ""
    @State private var projectEmoji = ""
    @State private var projectManager = ProjectManager.shared
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $projectName)
                    TextField("Emoji (optional)", text: $projectEmoji)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createProject()
                    }
                    .bold()
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #else
        VStack(spacing: 20) {
            Text("New Project")
                .font(.title)
                .bold()
            
            TextField("Project Name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            TextField("Emoji (optional)", text: $projectEmoji)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .tint(.thTeal)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        #endif
    }
    
    private func createProject() {
        let emoji = projectEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEmoji = emoji.isEmpty ? nil : emoji
        _ = projectManager.createProject(
            name: projectName,
            emoji: finalEmoji
        )
        dismiss()
    }
}

// MARK: - Edit Project View

struct EditProjectView: View {
    let project: Project
    
    @State private var projectName: String
    @State private var projectEmoji: String
    @State private var projectManager = ProjectManager.shared
    
    @Environment(\.dismiss) var dismiss
    
    init(project: Project) {
        self.project = project
        _projectName = State(initialValue: project.name)
        _projectEmoji = State(initialValue: project.emoji ?? "")
    }
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $projectName)
                    TextField("Emoji (optional)", text: $projectEmoji)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProject()
                    }
                    .bold()
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #else
        VStack(spacing: 20) {
            Text("Edit Project")
                .font(.title)
                .bold()
            
            TextField("Project Name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            TextField("Emoji (optional)", text: $projectEmoji)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveProject()
                }
                .buttonStyle(.borderedProminent)
                .tint(.thTeal)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        #endif
    }
    
    private func saveProject() {
        let emoji = projectEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEmoji = emoji.isEmpty ? nil : emoji
        projectManager.updateProject(
            project,
            name: projectName,
            emoji: finalEmoji
        )
        dismiss()
    }
}

#Preview {
    ProjectListView()
}
