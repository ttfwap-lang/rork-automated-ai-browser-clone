import SwiftUI

struct AgentDetailView: View {
    let agent: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(agent)
                    .font(.largeTitle)
                    .foregroundColor(.primary)
                
                Divider().padding()
                
                // Quick Actions Bar
                HStack(spacing: 10) {
                    ForEach(getQuickActions(agent: agent), id: "") { action in
                        Button(action: {
                            switch action {
                                case .browse: { /* handle browse */ }
                                case .fillForm: { /* handle fillForm */ }
                                case .submitForm: { /* handle submitForm */ }
                                case .takeSnapshot: { /* handle takeSnapshot */ }
                                case .sendNotification: { /* handle sendNotification */ }
                            }
                        }) {
                            Text(action.label)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                // Details Panel
                if let info = agent.details {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Details")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("ID: \(info.id)")
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        Text("Status: \(info.status)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Helper Functions
@ViewBuilder
func getQuickActions(agent: String) -> [String] {
    // Map agent capabilities to available actions
    let mappings: [String: [String]] = [
        "agent1": ["browse", "fillForm", "submitForm", "takeSnapshot", "sendNotification"],
        "agent2": ["browse", "fillForm", "submitForm", "takeSnapshot"]
    ]
    return mappings[agent] ?? ["browse", "fillForm", "submitForm", "takeSnapshot"]
}

func getAgentDetails(agent: String) -> (id: String, details: String?) {
    // In a real implementation, this would fetch details from the database
    // For now, returning mock data
    return (
        id: "agent_\(Int.random(in: 1...10))",
        details: "This agent handles document retrieval and form submissions."
    )
}
