import SwiftUI

struct MainView: View {
    @State private var selectedAgent: String?
    @State private var showingForm: Bool = false
    @State private var formField: String?
    @State private var formValue: String?
    
    var body: some View {
        NavigationStack(
            title: Text("Agent Browser"),
            selection: $selectedAgent
        ) {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "robot.chip")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    Text("Agent Browser")
                        .font(.title)
                        .padding(.top, 20)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(agents, id: \.id) { agent in
                            NavigationLink(
                                destination: AgentDetailView(agent: agent),
                                label: Text(agent.name)
                            ) {
                                if let action = getAvailableActions(agent: agent) {
                                    Button(action: { selectedAgent = agent.name }) {
                                        Text(action.label).fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    if agents.isEmpty {
                        Text("No agents yet").font(.caption).ignoringCase.padding()
                    }
                }
            }
            .navigationTitle("Home")
        }
    }
}

@ViewBuilder
func getAvailableActions(agent: String) -> [String] {
    let actions: [String] = [
        "browse": "Browse Website",
        "fillForm": "Fill Form",
        "submitForm": "Submit Form",
        "takeSnapshot": "Take Snapshot",
        "sendNotification": "Send Notification"
    ]
    return actions
}
