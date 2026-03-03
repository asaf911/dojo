import Foundation

/// Centralized debug logger for Heart Rate subsystem.
/// All logs use format: `[HR] Component: Message`
enum HRDebugLogger {
    
    enum Component: String {
        case service = "Service"
        case airpods = "AirPods"
        case watch = "Watch"
        case fitbit = "Fitbit"
        case passive = "Passive"
        case router = "Router"
        case bpmTracker = "BPMTracker"
        case ui = "UI"
    }
    
    /// Log an informational message
    static func log(_ component: Component, _ message: String) {
        print("[HR] \(component.rawValue): \(message)")
    }
    
    /// Log a heart rate sample received
    static func logBPM(_ component: Component, bpm: Double, age: TimeInterval, source: String? = nil) {
        let sourceStr = source.map { " src=\($0)" } ?? ""
        print("[HR] \(component.rawValue): BPM=\(Int(bpm)) age=\(String(format: "%.1f", age))s\(sourceStr)")
    }
    
    /// Log a status change
    static func logStatus(_ component: Component, from: String, to: String) {
        print("[HR] \(component.rawValue): Status \(from) -> \(to)")
    }
    
    /// Log a source switch in router
    static func logSourceSwitch(from: String, to: String) {
        print("[HR] Router: Source switched \(from) -> \(to)")
    }
    
    /// Log a command sent to Watch
    static func logCommand(_ command: String, sessionId: String?) {
        let sid = sessionId ?? "none"
        print("[HR] Watch: Command sent - \(command) sessionId=\(sid)")
    }
    
    /// Log a warning
    static func warn(_ component: Component, _ message: String) {
        print("[HR] \(component.rawValue): ⚠️ \(message)")
    }
    
    /// Log an error
    static func error(_ component: Component, _ message: String) {
        print("[HR] \(component.rawValue): ❌ \(message)")
    }
}

