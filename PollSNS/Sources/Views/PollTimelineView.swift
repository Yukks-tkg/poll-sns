import SwiftUI

struct PollTimelineView: View {
    @State private var polls: [Poll] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List(polls) { poll in
                NavigationLink {
                    PollDetailView(poll: poll)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(poll.question)
                            .font(.headline)
                        Text(poll.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Timeline")
            .task {
                do {
                    polls = try await PollAPI.fetchPolls()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
