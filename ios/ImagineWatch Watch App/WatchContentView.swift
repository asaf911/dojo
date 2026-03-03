//
//  WatchContentView.swift
//  Dojo
//

import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject var healthKitManager: WatchHealthKitManager
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var currentTime = Date()
    
    // Timer to refresh UI for data freshness updates
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Purple background
            Color.backgroundDarkPurple.ignoresSafeArea()

            VStack(spacing: 8) {
                // 1. Dojo (title of the app)
                Text("Dojo")
                    .nunitoFont(size: 24, style: .bold)
                    .foregroundColor(.white)
                
                if !healthKitManager.isMeasuringHR {
                    // Single clean message in not-measuring mode
                    Text("Start meditation to begin measuring heart rate")
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(Color.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                } else {
                    // Live BPM only
                    VStack(spacing: 2) {
                        if let bpm = healthKitManager.latestBPM, isDataFresh {
                            Text("\(Int(bpm))")
                                .nunitoFont(size: 48, style: .bold)
                                .foregroundColor(.white)
                            HStack(spacing: 4) {
                                Text("BPM")
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.white.opacity(0.7))
                                // Fresh data indicator
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                        } else {
                            Text("--")
                                .nunitoFont(size: 48, style: .bold)
                                .foregroundColor(.gray)
                            Text("BPM")
                                .nunitoFont(size: 14, style: .medium)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding()
        }
        .onReceive(refreshTimer) { _ in
            currentTime = Date()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Check if current heart rate data is fresh (within 45 seconds)
    private var isDataFresh: Bool {
        guard let lastUpdate = healthKitManager.lastHeartRateUpdate else { return false }
        let dataAge = Date().timeIntervalSince(lastUpdate)
        return dataAge <= 45 // 45 seconds threshold - much stricter for live data
    }
    
    private var statusText: String {
        // Show data state only - no modes
        if healthKitManager.latestBPM == nil {
            return "No Heart Rate Data"
        } else if !isDataFresh {
            return "Data Too Old"
        } else {
            return "Live Heart Rate"
        }
    }
    
    private var statusColor: Color {
        // Color based on data state only
        if healthKitManager.latestBPM == nil {
            return Color.gray
        } else if !isDataFresh {
            return Color.orange
        } else {
            return Color.green // Live data is always green
        }
    }
    
    private var shouldShowErrorMessage: Bool {
        let message = healthKitManager.statusMessage.lowercased()
        // Show error message if it contains error-related keywords or permission issues
        return message.contains("error") || 
               message.contains("failed") || 
               message.contains("denied") || 
               message.contains("cannot") ||
               message.contains("settings") ||
               message.contains("privacy") ||
               message.contains("health") ||
               message.contains("allow") ||
               healthKitManager.latestBPM == nil
    }
}

// MARK: - Preview
struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchHealthKitManager.shared)
            .environmentObject(WatchConnectivityManager.shared)
    }
}
