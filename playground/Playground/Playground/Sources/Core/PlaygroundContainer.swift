import SwiftUI

/// Main container view - shows the Conversion app directly
struct PlaygroundContainer: View {
    var body: some View {
        NavigationStack {
            ConversionHistoryView()
        }
    }
}

#Preview {
    PlaygroundContainer()
}
