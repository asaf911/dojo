import SwiftUI

struct WatchConnectivityDebugView: View {
    @StateObject private var phoneConnectivity = PhoneConnectivityManager.shared
    @StateObject private var bpmTracker = PracticeBPMTracker.shared
    
    // Watch pairing manager
    @ObservedObject private var watchPairingManager = WatchPairingManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🧪 Watch Connectivity Debug")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 15) {
                Button("🟢 Start Live Mode") {
                    phoneConnectivity.notifyPracticePreloaded()
                }
                .buttonStyle(.borderedProminent)
                
                Button("🔴 Stop Live Mode") {
                    phoneConnectivity.notifyPracticeEnded()
                }
                .buttonStyle(.bordered)
                
                Button("👀 Watch App Foreground") {
                    phoneConnectivity.notifyWatchAppInForeground()
                }
                .buttonStyle(.bordered)
                
                Button("🌫️ Watch App Background") {
                    phoneConnectivity.notifyWatchAppInBackground()
                }
                .buttonStyle(.bordered)
                
                Button("🗑️ Reset BPM Data") {
                    bpmTracker.resetData()
                }
                .buttonStyle(.bordered)
                
                Button("🧪 Add Test BPM Reading") {
                    // Add a random heart rate reading for testing
                    let testBPM = Double.random(in: 60...100)
                    bpmTracker.receivedHeartRate(testBPM, timestamp: Date())
                }
                .buttonStyle(.bordered)
                
                Button("🆕 Simulate New Practice Tap") {
                    // Simulate what happens when user taps a new practice
                    print("🧪 Debug: Simulating new practice tap")
                    PracticeBPMTracker.shared.resetData()
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("📊 BPM Tracker (Simplified)")
                        .font(.headline)

                    if bpmTracker.hasAnyData {
                        // Current Status
                        VStack(alignment: .leading, spacing: 5) {
                            Text("📍 Current Status")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Current: \(Int(bpmTracker.currentBPM)) BPM")
                            Text("Results locked: \(bpmTracker.hasLockedResults ? "🔒 YES" : "🔄 NO")")
                            Text("Summary: \(bpmTracker.summaryString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)

                        // Live Session Data
                        VStack(alignment: .leading, spacing: 5) {
                            Text("🔄 Live Session Data")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Total readings: \(bpmTracker.sampleCount)")
                            Text("First 3 avg: \(String(format: "%.1f", bpmTracker.firstThreeAverage)) BPM")
                            Text("Last 3 avg: \(String(format: "%.1f", bpmTracker.lastThreeAverage)) BPM")
                            Text("Overall avg: \(String(format: "%.1f", bpmTracker.overallAverage)) BPM")
                            Text("Change: \(String(format: "%.1f", bpmTracker.heartRateChange))%")
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                        // Final Results (if locked)
                        if bpmTracker.hasLockedResults {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("🔒 Final Results (LOCKED)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Final readings: \(bpmTracker.finalSampleCount)")
                                Text("Final first 3 avg: \(String(format: "%.1f", bpmTracker.finalFirstThreeAverage)) BPM")
                                Text("Final last 3 avg: \(String(format: "%.1f", bpmTracker.finalLastThreeAverage)) BPM")
                                Text("Final overall avg: \(String(format: "%.1f", bpmTracker.finalOverallAverage)) BPM")
                                Text("Final change: \(String(format: "%.1f", bpmTracker.finalHeartRateChange))%")
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // What PostPracticeView Will Use
                        VStack(alignment: .leading, spacing: 5) {
                            Text("📱 PostPracticeView Will Show")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Start BPM: \(String(format: "%.1f", bpmTracker.bestFirstThreeAverage)) BPM")
                            Text("End BPM: \(String(format: "%.1f", bpmTracker.bestLastThreeAverage)) BPM")
                            Text("Change: \(String(format: "%.1f", bpmTracker.bestHeartRateChange))%")
                            Text("Has valid data: \(bpmTracker.hasValidData ? "✅" : "❌")")
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)

                        if let lastUpdate = bpmTracker.lastUpdateTime {
                            Text("Last update: \(lastUpdate.formatted(.dateTime.hour().minute().second()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No heart rate data available")
                            .foregroundColor(.gray)
                    }
                }
            }

            if !watchPairingManager.isWatchPaired {
                VStack(alignment: .leading, spacing: 10) {
                    Text("📱 Apple Watch Status")
                        .font(.headline)

                    Text("Apple Watch not paired")
                        .foregroundColor(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchConnectivityDebugView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchConnectivityDebugView()
        }
    }
} 