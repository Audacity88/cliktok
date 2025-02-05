import SwiftUI

struct TipBubbleView: View {
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Text("1¢")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .padding(8)
            .background(
                Circle()
                    .fill(Color.green.opacity(0.8))
            )
            .offset(y: yOffset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5)) {
                    yOffset = -100
                    opacity = 0
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black
        TipBubbleView()
    }
}
