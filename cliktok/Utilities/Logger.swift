import Foundation

public class Logger {
    public enum LogLevel {
        case debug
        case info
        case warning
        case error
        case success
        case performance
        
        var prefix: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            case .success: return "SUCCESS"
            case .performance: return "PERF"
            }
        }
    }
    
    private let component: String
    
    public init(component: String) {
        self.component = component
    }
    
    public func log(_ message: String, level: LogLevel = .info) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] [\(component)] \(level.prefix): \(message)")
    }
    
    // Static convenience method for quick logging without instantiation
    public static func log(_ message: String, level: LogLevel = .info, component: String = "App") {
        let logger = Logger(component: component)
        logger.log(message, level: level)
    }
    
    // Convenience methods for different log levels
    public func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    public func info(_ message: String) {
        log(message, level: .info)
    }
    
    public func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    public func error(_ message: String) {
        log(message, level: .error)
    }
    
    public func success(_ message: String) {
        log(message, level: .success)
    }
    
    public func performance(_ message: String) {
        log(message, level: .performance)
    }
} 