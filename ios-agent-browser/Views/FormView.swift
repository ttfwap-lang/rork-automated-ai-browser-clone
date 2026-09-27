import SwiftUI

struct FormView: View {
    @Binding var agent: String
    @Binding var formField: String?
    @Binding var formValue: String?
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Form for Agent: \(agent ?? "Unassigned")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("Field Name", text: $formField)
                    .textFieldStyle(.roundedBorder)
                    .border(Color.gray.opacity(0.2))
                    .padding()
                    .frame(minWidth: 200)
                
                TextField("Value", text: $formValue)
                    .textFieldStyle(.roundedBorder)
                    .border(Color.gray.opacity(0.2))
                    .padding()
                    .frame(minWidth: 200)
            }
            
            HStack(spacing: 15) {
                Button(action: { formValue = formField }) {
                    Text("Submit")
                        .font(.button)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                Spacer()
                Button(action: { showingForm = false }) {
                    Text("Cancel")
                        .font(.button)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.gray)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
