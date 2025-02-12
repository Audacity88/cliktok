import SwiftUI

struct TipBubbleView: View {
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    let amount: Double
    var onComplete: (() -> Void)?
    
    var body: some View {
        Text("\(Int(amount))¢")
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
                
                // Schedule completion callback after animation duration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onComplete?()
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black
        TipBubbleView(amount: 1.0)
    }
}
