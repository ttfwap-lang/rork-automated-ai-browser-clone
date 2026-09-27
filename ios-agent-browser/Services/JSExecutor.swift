import Foundation

/// High-performance JavaScript executor for the WebView
/// Provides script caching, batched compilation, and parallel execution
public final class JSExecutor {
    // Script cache: maps script sources to compiled code
    private var scriptCache: [String: Data] = [:] // Key: script source hash, Value: compiled code
    
    // Batched compilation queue
    private var pendingJobs: [String: Job] = [:] // Key: script source, Value: Job
    
    // Thread pool for parallel execution
    private static let threadPoolSize = 4
    
    // Configuration for maximum power
    private let maxParallelJobs = 10
    private let maxScriptBatchSize = 50
    
    /// Enable maximum power mode for script execution
    public func enableMaxPower() {
        self.maxParallelJobs = 10
        self.maxScriptBatchSize = 50
    }
    
    /// Disable maximum power mode
    public func disableMaxPower() {
        self.maxParallelJobs = 4
        self.maxScriptBatchSize = 20
    }
    
    /// Set maximum parallel jobs
    public func setMaxParallelJobs(_ value: Int) {
        self.maxParallelJobs = max(1, min(value, 20))
    }
    
    /// Set maximum script batch size
    public func setMaxScriptBatchSize(_ value: Int) {
        self.maxScriptBatchSize = max(1, min(value, 100))
    }
    
    /// Compile a JavaScript snippet and cache it
    public func compileScript(_ source: String) -> Data? {
        // Generate a unique key for this script based on content hash
        let hash = SHA256.hash(data: source.data(using: .utf8)).prefix(16).map { $0.unicodeScalars.first!.code }.joined()
        
        if let cached = scriptCache[hash] {
            return cached
        }
        
        // Compile the script (simplified - in production would use WebKitJS or similar)
        // For now, we simulate compilation by returning a placeholder
        // In a real implementation, this would use WebKit's JS engine
        let compiled = Data(binaryData: source.data(using: .utf8)!)
        scriptCache[hash] = compiled
        return compiled
    }
    
    /// Execute a JavaScript snippet synchronously (with caching)
    public func executeScript(_ source: String) -> Any? {
        // Try to get from cache first
        if let cached = scriptCache[computeHash(source)] {
            return cached
        }
        
        // Compile and execute
        let compiled = compileScript(source)
        if let compiled = compiled {
            // Simulate execution - in reality, this would run JS in WKWebView
            return executeInWebView(source)
        }
        return nil
    }
    
    /// Execute a JavaScript snippet asynchronously (parallel)
    public func executeScriptAsync(_ source: String) -> Any? {
        // Find or create a job for this script
        if let job = pendingJobs[computeHash(source)] {
            return job.run()
        }
        
        // Create a new job
        let job = Job(source: source, priority: 1)
        pendingJobs[computeHash(source)] = job
        
        // Execute in background thread
        DispatchQueue.global(qos: .userInitiated).async {
            if let result = executeInWebView(source) {
                job.run()
            }
        }
        
        return job
    }
    
    /// Batch multiple scripts for efficient processing
    public func executeScriptsBatch(_ sources: [String]) -> [Any?] {
        // Group by hash to minimize redundant compilation
        let grouped = groupByHash(sources)
        
        // Process in batches
        var results: [Any?] = []
        let batchSize = maxScriptBatchSize
        
        for (hash, sourcesInGroup) in grouped {
            let batch = sourcesInGroup.prefix(batchSize)
            let remaining = sourcesInGroup.suffix(sourcesInGroup.count - batchSize)
            
            // Compile and execute batch
            let compiled = compileScript(hash)
            if let compiled = compiled {
                // Execute each script in the batch
                for source in batch {
                    if let result = executeInWebView(source) {
                        results.append(result)
                    }
                }
            }
            
            // Wait for partial completion (optional)
        }
        
        return results
    }
    
    /// Get the current compilation statistics
    public func getCompilationStats() -> CompilationStats {
        return CompilationStats(
            totalCompiled: scriptCache.count,
            totalPending: pendingJobs.count,
            maxParallel: maxParallelJobs,
            maxBatchSize: maxScriptBatchSize
        )
    }
}

/// Simple job wrapper for asynchronous JavaScript execution
private final class Job {
    let source: String
    let priority: Int
    
    init(source: String, priority: Int = 1) {
        self.source = source
        self.priority = priority
    }
    
    func run() {
        // In a real implementation, this would dispatch to the web view
        // For now, we simulate completion
        print("Job executed: \(source)")
    }
}

/// Statistics for compilation performance
public struct CompilationStats {
    let totalCompiled: Int
    let totalPending: Int
    let maxParallel: Int
    let maxBatchSize: Int
}

/// Helper to compute hash from string
private func computeHash(_ source: String) -> String {
    let data = source.data(using: .utf8)!
    return SHA256.hash(data: data).prefix(16).map { $0.unicodeScalars.first!.code }.joined()
}

/// Helper to group strings by hash
private func groupByHash(_ sources: [String]) -> [(String, [String])] {
    var groups: [String: [String]] = [:]
    for source in sources {
        let hash = computeHash(source)
        groups[hash, default: []].append(source)
    }
    return groups
}