import Foundation

/// Represents a single action the AI agent can perform in the browser
/// Maximum vision and efficiency enabled

public enum AgentAction {
    /// Navigate to a specific URL
    case browse(url: String)
    
    /// Fill a form field with a value
    case fillForm(field: String, value: String)
    
    /// Submit the current form
    case submitForm()
    
    /// Take a screenshot of the current page
    case takeSnapshot()
    
    /// Send a notification to the user
    case sendNotification(message: String)
    
    /// Perform a complex multi-step operation
    case complexOperation(steps: [String])
    
    /// Interact with a specific element on the page
    case interact(element: String, action: String)
    
    /// Get the current page state
    case inspectPage()
    
    /// Mark a task as completed
    case completeTask(taskId: String)
}

/// Represents the state of an ongoing task in the agent
public struct Task {
    let id: String
    let type: String
    let status: TaskStatus
    let createdAt: Date
    let priority: TaskPriority
    
    enum TaskStatus {
        case pending
        case in_progress
        case completed
        case failed
        case cancelled
    }
    
    enum TaskPriority {
        .low = .low
        .medium = .medium
        .high = .high
        .critical = .critical
    }
}

/// Represents the result of an AI prediction
public struct AIPrediction {
    let action: AgentAction
    let confidence: Double
    let reasoning: String
    let estimatedLatency: TimeInterval
}

/// Represents a logged task for audit and debugging
public struct TaskLog {
    let taskId: String
    let actionType: String
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let metadata: [String: Any]
}
