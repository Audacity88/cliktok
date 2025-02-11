import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .tint(.green)
            Text("Loading...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
        }
    }
}

#Preview {
    LoadingView()
} 