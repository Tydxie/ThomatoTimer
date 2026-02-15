//
//  SettingsView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @ObservedObject var viewModel: TimerViewModel
    @Bindable var spotifyManager: SpotifyManager
    @Bindable var appleMusicManager: AppleMusicManager
    @Binding var selectedService: MusicService
    @State private var showingStats = false
    
    #if os(macOS)
    @AppStorage("keepWindowOpen") private var keepWindowOpen = false
    @EnvironmentObject var menuBarManager: MenuBarManager
    #endif
    
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
            Form {
                Section {
                    Stepper("Work Session: \(viewModel.timerState.workDuration) min",
                            value: $viewModel.timerState.workDuration, in: 1...60)
                    
                    Stepper("Short Break: \(viewModel.timerState.shortBreakDuration) min",
                            value: $viewModel.timerState.shortBreakDuration, in: 1...30)
                    
                    Stepper("Long Break: \(viewModel.timerState.longBreakDuration) min",
                            value: $viewModel.timerState.longBreakDuration, in: 1...60)
                    
                    Stepper(
                        "Sessions bef. long break: \(viewModel.timerState.sessionsUntilLongBreak)",
                        value: $viewModel.timerState.sessionsUntilLongBreak,
                        in: 2...8
                    )
                    
                    HStack {
                        Text("Warmup Duration")
                        Spacer()
                        Picker("", selection: $viewModel.timerState.warmupDuration) {
                            Text("None").tag(0)
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .onChange(of: viewModel.timerState.warmupDuration) { oldValue, newValue in
                        if !viewModel.timerState.isRunning && !viewModel.timerState.isPaused {
                            if newValue == 0 && viewModel.timerState.currentPhase == .warmup {
                                viewModel.timerState.currentPhase = .work
                                viewModel.timerState.timeRemaining = TimeInterval(viewModel.timerState.workDuration * 60)
                            } else if newValue > 0 && viewModel.timerState.currentPhase == .work && viewModel.timerState.completedWorkSessions == 0 {
                                viewModel.timerState.currentPhase = .warmup
                                viewModel.timerState.timeRemaining = TimeInterval(newValue * 60)
                            }
                        }
                    }
                    
                } header: {
                    Label("Timer Settings", systemImage: "clock")
                }
                
                Section {
                    Picker("Service", selection: $selectedService) {
                        ForEach(MusicService.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }
                    
                    if selectedService == .spotify {
                        spotifySectioniOS
                    } else if selectedService == .appleMusic {
                        appleMusicSectioniOS
                    }
                } header: {
                    Label("Music Integration", systemImage: "music.note")
                }
                
                Section {
                    HStack {
                        Text("Recorded Crashes")
                        Spacer()
                        Text("\(CrashLogger.shared.getCrashCount())")
                            .foregroundColor(CrashLogger.shared.getCrashCount() > 0 ? .red : .secondary)
                            .bold()
                    }
                    
                    HStack {
                        Text("Logged Events")
                        Spacer()
                        Text("\(CrashLogger.shared.getAppEvents().count)")
                            .foregroundColor(.blue)
                            .bold()
                    }
                    
                    Button("Test Logging System") {
                        CrashLogger.shared.logEvent("TEST EVENT - Tapped at \(Date())")
                        CrashLogger.shared.logEvent("TEST EVENT 2 - This is a second test")
                        CrashLogger.shared.logEvent("TEST EVENT 3 - Third test event")
                        
                        let count = CrashLogger.shared.getAppEvents().count
                        print("Test completed. Total events: \(count)")
                    }
                    
                    Button(action: {
                        let report = CrashLogger.shared.exportLogs()
                        UIPasteboard.general.string = report
                        
                        print("\nDEBUG REPORT COPIED TO CLIPBOARD:")
                        print("=====================================")
                        print(report)
                        print("=====================================\n")
                    }) {
                        Label("Copy Report to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    
                    Button(action: {
                        let report = CrashLogger.shared.exportLogs()
                        let activityVC = UIActivityViewController(
                            activityItems: [report],
                            applicationActivities: nil
                        )
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootVC = window.rootViewController {
                            rootVC.present(activityVC, animated: true)
                        }
                    }) {
                        Label("Share Debug Report", systemImage: "square.and.arrow.up")
                    }
                    
                    if CrashLogger.shared.getCrashCount() > 0 || CrashLogger.shared.getAppEvents().count > 0 {
                        Button(role: .destructive) {
                            CrashLogger.shared.clearCrashLogs()
                        } label: {
                            Label("Clear All Logs", systemImage: "trash")
                        }
                    }
                } header: {
                    Label("Debug Info", systemImage: "ladybug")
                }
                
                Section {
                    Button(action: { showingStats = true }) {
                        HStack {
                            Text("View Statistics")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingStats) {
                StatisticsView()
            }
        }
    }
    
    // MARK: - iOS Spotify Section
    
    @ViewBuilder
    private var spotifySectioniOS: some View {
        if !spotifyManager.isAuthenticated {
            Button("Connect to Spotify") {
                spotifyManager.authenticate()
            }
            .foregroundColor(.green)
        } else {
            HStack {
                Text("Status")
                Spacer()
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            if !spotifyManager.playlists.isEmpty {
                Picker("Work Playlist", selection: $spotifyManager.selectedWorkPlaylistId) {
                    Text("None").tag(nil as String?)
                    ForEach(spotifyManager.playlists) { playlist in
                        Text(playlist.name).tag(playlist.id as String?)
                    }
                }
                
                Picker("Warmup/Break Playlist", selection: $spotifyManager.selectedBreakPlaylistId) {
                    Text("None").tag(nil as String?)
                    ForEach(spotifyManager.playlists) { playlist in
                        Text(playlist.name).tag(playlist.id as String?)
                    }
                }
                
            } else {
                Button("Load Playlists") {
                    Task { await spotifyManager.fetchPlaylists() }
                }
            }
            
            Button("Disconnect", role: .destructive) {
                Task {
                    await spotifyManager.pausePlayback()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        spotifyManager.accessToken = nil
                        spotifyManager.refreshToken = nil
                        spotifyManager.isAuthenticated = false
                        spotifyManager.playlists = []
                        spotifyManager.selectedWorkPlaylistId = nil
                        spotifyManager.selectedBreakPlaylistId = nil
                        spotifyManager.selectedWarmupTrackId = nil
                        spotifyManager.warmupTrackName = nil
                    }
                }
            }
            
            if let expirationDate = spotifyManager.tokenExpirationDate {
                HStack {
                    Text("Token expires")
                    Spacer()
                    Text(expirationDate, style: .relative)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
        }
        
        if let error = spotifyManager.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    // MARK: - iOS Apple Music Section
    
    @ViewBuilder
    private var appleMusicSectioniOS: some View {
        if !appleMusicManager.isAuthorized {
            Button("Authorize Apple Music") {
                Task { await appleMusicManager.requestAuthorization() }
            }
            .foregroundColor(.red)
            
            Text("Requires Apple Music subscription")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            HStack {
                Text("Status")
                Spacer()
                Label("Authorized", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            if !appleMusicManager.playlists.isEmpty {
                Picker("Work Playlist", selection: $appleMusicManager.selectedWorkPlaylistId) {
                    Text("None").tag(nil as String?)
                    ForEach(appleMusicManager.playlists) { playlist in
                        Text(playlist.name).tag(playlist.id as String?)
                    }
                }
                
                Picker("Warmup/Break Playlist", selection: $appleMusicManager.selectedBreakPlaylistId) {
                    Text("None").tag(nil as String?)
                    ForEach(appleMusicManager.playlists) { playlist in
                        Text(playlist.name).tag(playlist.id as String?)
                    }
                }
                
            } else {
                Button("Load Playlists") {
                    Task { await appleMusicManager.fetchUserPlaylists() }
                }
            }
        }
        
        if let error = appleMusicManager.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    #endif
    
    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button("View Statistics") {
                    showingStats = true
                }
                .buttonStyle(.bordered)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
            }
            .padding([.top, .horizontal])
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox(label: Label("Timer Settings", systemImage: "clock")) {
                        VStack(spacing: 15) {
                            HStack {
                                Text("Work Session (Mins):")
                                    .frame(width: 180, alignment: .leading)
                                TextField("Minutes", value: $viewModel.timerState.workDuration, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                            
                            HStack {
                                Text("Short Break (Mins):")
                                    .frame(width: 180, alignment: .leading)
                                TextField("Minutes", value: $viewModel.timerState.shortBreakDuration, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                            
                            HStack {
                                Text("Long Break (Mins):")
                                    .frame(width: 180, alignment: .leading)
                                TextField("Minutes", value: $viewModel.timerState.longBreakDuration, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                            
                            HStack {
                                Text("Sessions until long break:")
                                    .frame(width: 180, alignment: .leading)
                                TextField("Count", value: $viewModel.timerState.sessionsUntilLongBreak, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                            
                            HStack {
                                Text("Warmup Duration:")
                                    .frame(width: 180, alignment: .leading)
                                Picker(selection: $viewModel.timerState.warmupDuration, label: Text("")) {
                                    Text("None").tag(0)
                                    Text("5 min").tag(5)
                                    Text("10 min").tag(10)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            .onChange(of: viewModel.timerState.warmupDuration) { oldValue, newValue in
                                if !viewModel.timerState.isRunning && !viewModel.timerState.isPaused {
                                    if newValue == 0 && viewModel.timerState.currentPhase == .warmup {
                                        viewModel.timerState.currentPhase = .work
                                        viewModel.timerState.timeRemaining = TimeInterval(viewModel.timerState.workDuration * 60)
                                    } else if newValue > 0 && viewModel.timerState.currentPhase == .work && viewModel.timerState.completedWorkSessions == 0 {
                                        viewModel.timerState.currentPhase = .warmup
                                        viewModel.timerState.timeRemaining = TimeInterval(newValue * 60)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    
                    GroupBox(label: Label("Music Integration", systemImage: "music.note")) {
                        VStack(spacing: 15) {
                            HStack {
                                Text("Service:")
                                    .frame(width: 180, alignment: .leading)
                                
                                Picker("", selection: $selectedService) {
                                    ForEach(MusicService.allCases) { service in
                                        Text(service.rawValue).tag(service)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            
                            Divider()
                            
                            if selectedService == .spotify {
                                spotifySectionMac
                            } else if selectedService == .appleMusic {
                                appleMusicSectionMac
                            } else {
                                Text("No music service selected")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    
                    GroupBox(label: Label("Window Behavior", systemImage: "rectangle.topthird.inset")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Keep timer dropdown open", isOn: $keepWindowOpen)
                                .toggleStyle(.switch)
                                .onChange(of: keepWindowOpen) { oldValue, newValue in
                                    if !newValue {
                                        menuBarManager.checkAndCloseIfNeeded()
                                    }
                                }
                            
                            Text("When enabled, the menu bar timer window will stay open until you close it manually instead of closing when you click away.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    }
                    
                    GroupBox(label: Label("Debug Info", systemImage: "ladybug")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Recorded Crashes:")
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Text("\(CrashLogger.shared.getCrashCount())")
                                    .foregroundColor(CrashLogger.shared.getCrashCount() > 0 ? .red : .secondary)
                                    .bold()
                                    .frame(width: 40)
                            }
                            
                            Button(action: {
                                let report = CrashLogger.shared.exportLogs()
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(report, forType: .string)
                                print("Debug report copied to clipboard")
                                print(report)
                            }) {
                                Label("Copy Debug Report", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                            
                            if CrashLogger.shared.getCrashCount() > 0 {
                                Button(role: .destructive) {
                                    CrashLogger.shared.clearCrashLogs()
                                } label: {
                                    Label("Clear Debug Logs", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding()
            }
            .frame(width: 300, height: 520)
        }
        .sheet(isPresented: $showingStats) {
            StatisticsView()
        }
    }
    
    // MARK: - macOS Spotify Section
    
    @ViewBuilder
    private var spotifySectionMac: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundColor(.green)
                Text("Spotify")
                    .font(.headline)
                Spacer()
                
                if spotifyManager.isAuthenticated {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            if !spotifyManager.isAuthenticated {
                Button("Connect to Spotify") {
                    spotifyManager.authenticate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                VStack(spacing: 10) {
                    if !spotifyManager.playlists.isEmpty {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Work Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $spotifyManager.selectedWorkPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(spotifyManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            
                            HStack {
                                Text("Warmup/Break Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $spotifyManager.selectedBreakPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(spotifyManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    } else {
                        Button("Load Playlists") {
                            Task { await spotifyManager.fetchPlaylists() }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 10) {
                        Button("Disconnect") {
                            Task {
                                await spotifyManager.pausePlayback()
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                await MainActor.run {
                                    spotifyManager.accessToken = nil
                                    spotifyManager.refreshToken = nil
                                    spotifyManager.isAuthenticated = false
                                    spotifyManager.playlists = []
                                    spotifyManager.selectedWorkPlaylistId = nil
                                    spotifyManager.selectedBreakPlaylistId = nil
                                    spotifyManager.selectedWarmupTrackId = nil
                                    spotifyManager.warmupTrackName = nil
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Refresh Token") {
                            Task { await spotifyManager.refreshAccessToken() }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let expirationDate = spotifyManager.tokenExpirationDate {
                        Text("Token expires: \(expirationDate, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let error = spotifyManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - macOS Apple Music Section
    
    @ViewBuilder
    private var appleMusicSectionMac: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundColor(.red)
                Text("Apple Music")
                    .font(.headline)
                Spacer()
                
                if appleMusicManager.isAuthorized {
                    Label("Authorized", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            if !appleMusicManager.isAuthorized {
                Button("Authorize Apple Music") {
                    Task { await appleMusicManager.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Text("Requires Apple Music subscription")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    if !appleMusicManager.playlists.isEmpty {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Work Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $appleMusicManager.selectedWorkPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(appleMusicManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            
                            HStack {
                                Text("Warmup/Break Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $appleMusicManager.selectedBreakPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(appleMusicManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    } else {
                        Button("Load Playlists") {
                            Task { await appleMusicManager.fetchUserPlaylists() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            if let error = appleMusicManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
    #endif
}

#Preview {
    SettingsView(
        viewModel: TimerViewModel(),
        spotifyManager: SpotifyManager(),
        appleMusicManager: AppleMusicManager(),
        selectedService: .constant(.none)
    )
}
