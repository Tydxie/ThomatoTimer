//
//  ContentView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @State private var showingSettings = false
    let spotifyManager: SpotifyManager
    
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Spacer()
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding()
            }
            
            
            VStack(spacing: 20) {
                // Phase title (Work, Break, etc.)
                Text(viewModel.phaseTitle)
                    .font(.title)
                    .bold()
                
                // Timer display
                Text(viewModel.displayTime)
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                
                // Slider to control time
                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: {
                                let maxDuration = viewModel.currentPhaseDuration
                                return maxDuration - viewModel.timerState.timeRemaining
                            },
                            set: { newValue in
                                let maxDuration = viewModel.currentPhaseDuration
                                viewModel.timerState.timeRemaining = max(0.1, maxDuration - newValue)
                            }
                        ),
                        in: 0...viewModel.currentPhaseDuration
                    )
                    .frame(width: 300)
                    
                    // Time labels under slider
                    HStack {
                        Text("0:00")
                            .font(.caption)
                        Spacer()
                        Text(viewModel.displayTime)
                            .font(.caption)
                    }
                    .frame(width: 300)
                }
                
                
                
                // Buttons
                HStack(spacing: 15) {
                    if viewModel.timerState.isRunning {
                        Button("Skip") {
                            viewModel.skipToNext()
                        }
                    }
                    
                    Button(viewModel.buttonTitle) {
                        viewModel.toggleTimer()
                    }
                    
                    Button("Reset") {
                        viewModel.reset()
                    }
                }
                .font(.title2)
                
                // Checkmarks display
                Text(viewModel.timerState.checkmarks)
                    .font(.title3)
                
                
            }
            .padding(.horizontal,30)
            .padding(.vertical,15)
        }
        .frame(width: 480, height:400)
        .background(Color(red: 1.0, green: 0.95, blue: 0.94))
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel, spotifyManager: spotifyManager)  
        }
        .onAppear {
            viewModel.spotifyManager = spotifyManager
        }
    }
}

#Preview {
    ContentView(spotifyManager: SpotifyManager())
}
