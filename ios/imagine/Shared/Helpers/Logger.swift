//
//  Logger.swift
//  Dojo
//
//  Created by Michael Tabachnik on 10/18/24.
//

import Foundation
import OSLog
import FirebaseCrashlytics

public protocol LoggerProtocol {
    static var defaultSubsystem: String { get }
    
    func errorMessage(_ message: String, function: String, line: Int, file: String)
    func infoMessage(_ message: String, function: String, line: Int, file: String)
    func debugMessage(_ message: String, function: String, line: Int, file: String)
    func eventMessage(_ message: String, function: String, line: Int, file: String)
    func warnMessage(_ message: String, function: String, line: Int, file: String)
}

public extension LoggerProtocol {
    func errorMessage(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        errorMessage(message, function: function, line: line, file: file)
    }
    
    func infoMessage(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        infoMessage(message, function: function, line: line, file: file)
    }
    
    func debugMessage(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        debugMessage(message, function: function, line: line, file: file)
    }
    
    func eventMessage(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        eventMessage(message, function: function, line: line, file: file)
    }
    
    func warnMessage(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        warnMessage(message, function: function, line: line, file: file)
    }

    // MARK: - AI Chat Debug Helpers
    // Unified tag so logs are easy to isolate across subsystems
    // Filter by "🧠 AI_DEBUG" in console or external log tools
    // Set to true only when debugging scroll behavior
    private static var verboseScrollLogging: Bool { false }
    
    func aiChat(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        // Skip high-frequency scroll logs unless explicitly enabled
        if message.contains("AI_SCROLL") && !Self.verboseScrollLogging { return }
        // Strip existing prefix to prevent duplication
        let cleanMessage = message.hasPrefix("🧠 AI_DEBUG ") ? String(message.dropFirst(12)) : message
        eventMessage("🧠 AI_DEBUG " + cleanMessage, function: function, line: line, file: file)
    }
    func aiChatError(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        // Strip existing prefix to prevent duplication
        let cleanMessage = message.hasPrefix("🧠 AI_DEBUG ") ? String(message.dropFirst(12)) : message
        errorMessage("🧠 AI_DEBUG " + cleanMessage, function: function, line: line, file: file)
    }

    /// Portable timer / OneLink / fractional hydration (AI_DEBUG sub-channel).
    /// **Console filter:** `[[TIMER_DEEPLINK]]` (matches `🧠 AI_DEBUG [[TIMER_DEEPLINK]] …` in unified logs).
    func timerDeepLink(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        aiChat("[[TIMER_DEEPLINK]] " + message, function: function, line: line, file: file)
    }

    func timerDeepLinkError(_ message: String, function: String = #function, line: Int = #line, file: String = #file) {
        aiChatError("[[TIMER_DEEPLINK]] " + message, function: function, line: line, file: file)
    }
}

public final class Logger: LoggerProtocol {
    public static let defaultSubsystem = Bundle.main.bundleIdentifier!
    private let logger: os.Logger
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        return dateFormatter
    }()
    
    public init(subsystem: String = Logger.defaultSubsystem, category: String) {
        logger = os.Logger(subsystem: subsystem, category: category)
    }
    
    public init(logger: os.Logger) {
        self.logger = logger
    }
    
    public func errorMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logger.error("❌ \(composedMessage, privacy: .public)")
    }
    
    public func infoMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logger.info("ℹ️ \(composedMessage, privacy: .public)")
    }
    
    public func debugMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logger.debug("🛠️ \(composedMessage, privacy: .public)")
    }
    
    public func eventMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logger.notice("👁️ \(composedMessage, privacy: .public)")
    }
    
    public func warnMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logger.warning("⚠️ \(composedMessage, privacy: .public)")
    }
    
    private func composeMessage(_ message: String, function: String, line: Int, file: String) -> String {
        let fileName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let timeString = getCurrentTimeString()
        let composed = "[\(timeString)] " + message + "\nSource⅏: \(fileName) -> F:\(function) -> #\(line)"
        return composed
    }
    
    // Helper function to get current time as string
    private func getCurrentTimeString() -> String {
        return dateFormatter.string(from: Date())
    }
}

#if !DEBUG
public final class FirebaseLogger: LoggerProtocol {
    public static let defaultSubsystem = Bundle.main.bundleIdentifier!
    private var crashlytics: Crashlytics { Crashlytics.crashlytics() }
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        return dateFormatter
    }()
    private let operationQueue = DispatchQueue(label: String(describing: FirebaseLogger.self) + ".queue")
    
    private func logFirebase(_ message: String) {
        operationQueue.sync {
            crashlytics.log(message)
        }
    }
    
    public func errorMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logFirebase("❌ \(composedMessage)")
        
        let exception = ExceptionModel(name: "ERROR:", reason: message)
        exception.stackTrace = [
            StackFrame(symbol: function, file: file, line: line)
        ]
        
        operationQueue.sync {
            crashlytics.record(exceptionModel: exception)
        }
    }
    
    public func infoMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logFirebase("ℹ️ \(composedMessage)")
    }
    
    public func debugMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logFirebase("🛠️ \(composedMessage)")
    }
    
    public func eventMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logFirebase("👁️ \(composedMessage)")
    }
    
    public func warnMessage(_ message: String, function: String, line: Int, file: String) {
        let composedMessage = composeMessage(message, function: function, line: line, file: file)
        logFirebase("⚠️ \(composedMessage)")
    }
    
    private func composeMessage(_ message: String, function: String, line: Int, file: String) -> String {
        let fileName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let timeString = getCurrentTimeString()
        let composed = "[\(timeString)] " + message + "\nSource⅏: \(fileName) -> F:\(function) -> #\(line)"
        return composed
    }
    
    // Helper function to get current time as string
    private func getCurrentTimeString() -> String {
        return dateFormatter.string(from: Date())
    }
}
#endif


let logger: LoggerProtocol = {
#if DEBUG
        return Logger(category: "DojoApp")
#else
        return FirebaseLogger()
#endif
}()
