//
//  ProjectSwitcherView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/29.
//

import SwiftUI

struct ProjectSwitcherView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var projectManager = ProjectManager.shared
    @State private var showingProjectList = false
    
    var body: some View {
        Menu {
            // Current projects
            ForEach(projectManager.projects) { project in
                Button(action: {
                    viewModel.switchProject(to: project)
                }) {
                    HStack {
                        Text(project.displayName)
                        if projectManager.currentProjectId == project.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            // No project option
            Button(action: {
                viewModel.switchProject(to: nil)
            }) {
                HStack {
                    Text("Freestyle")
                    if projectManager.currentProjectId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            // Manage projects
            Button(action: {
                showingProjectList = true
            }) {
                Label("Manage Projects", systemImage: "folder.badge.gearshape")
            }
        } label: {
            HStack(spacing: 6) {
                if let currentProject = projectManager.currentProject {
                    Text(currentProject.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                } else {
                    Text("Freestyle")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .sheet(isPresented: $showingProjectList) {
            ProjectListView()
        }
    }
}
