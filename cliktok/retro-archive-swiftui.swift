// import SwiftUI

// struct ContentView: View {
//     @State private var isLiked = false
//     @State private var isMuted = false
    
//     var body: some View {
//         ZStack {
//             // Main background
//             Color.black
//                 .ignoresSafeArea()
            
//             VStack(spacing: 0) {
//                 // Top Status Bar
//                 HStack {
//                     Text("9:00")
//                         .font(.system(.body, design: .monospaced))
//                         .foregroundColor(.green)
                    
//                     Spacer()
                    
//                     Text("77%")
//                         .font(.system(.body, design: .monospaced))
//                         .foregroundColor(.green)
//                 }
//                 .padding()
//                 .background(Color.black.opacity(0.5))
                
//                 // Video Container
//                 ZStack {
//                     Color(UIColor.systemGray6)
                    
//                     // Vintage TV Frame
//                     VintageTelevisionFrame()
                    
//                     // Video Placeholder
//                     Circle()
//                         .fill(Color(UIColor.systemGray5))
//                         .frame(width: 64, height: 64)
//                         .overlay(
//                             Rectangle()
//                                 .fill(Color.white)
//                                 .frame(width: 32, height: 32)
//                         )
                    
//                     // Right side interaction buttons
//                     VStack {
//                         Spacer()
//                         HStack {
//                             Spacer()
//                             VStack(spacing: 24) {
//                                 Button(action: { isLiked.toggle() }) {
//                                     Image(systemName: isLiked ? "heart.fill" : "heart")
//                                         .font(.system(size: 32))
//                                         .foregroundColor(isLiked ? .red : .white)
//                                 }
                                
//                                 Button(action: { isMuted.toggle() }) {
//                                     Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
//                                         .font(.system(size: 32))
//                                         .foregroundColor(.white)
//                                 }
                                
//                                 VStack(spacing: 4) {
//                                     Image(systemName: "eye.fill")
//                                         .font(.system(size: 32))
//                                     Text("0")
//                                         .font(.caption)
//                                 }
//                                 .foregroundColor(.white)
//                             }
//                             .padding(.trailing, 16)
//                             .padding(.bottom, 80)
//                         }
//                     }
                    
//                     // Progress Bar
//                     VStack {
//                         Spacer()
//                         GeometryReader { geometry in
//                             ZStack(alignment: .leading) {
//                                 Rectangle()
//                                     .fill(Color(UIColor.systemGray5))
//                                     .frame(height: 4)
                                
//                                 Rectangle()
//                                     .fill(Color.green)
//                                     .frame(width: geometry.size.width / 3, height: 4)
//                             }
//                         }
//                         .frame(height: 4)
//                     }
//                 }
//                 .frame(height: UIScreen.main.bounds.height * 0.75)
                
//                 // Video Info
//                 VStack(alignment: .leading, spacing: 4) {
//                     Text("Horror Movie Trailers, 1970s")
//                         .font(.system(.headline, design: .monospaced))
//                         .foregroundColor(.green)
                    
//                     Text("#archive")
//                         .font(.system(.subheadline, design: .monospaced))
//                         .foregroundColor(.gray)
//                 }
//                 .padding()
                
//                 Spacer()
                
//                 // Bottom Navigation
//                 CustomTabBar()
//             }
//         }
//     }
// }

// struct VintageTelevisionFrame: View {
//     var body: some View {
//         ZStack {
//             // TV Frame
//             Rectangle()
//                 .fill(Color.clear)
//                 .overlay(
//                     RoundedRectangle(cornerRadius: 12)
//                         .stroke(Color(UIColor.systemGray5), lineWidth: 40)
//                 )
            
//             // TV Knobs
//             HStack {
//                 ForEach(0..<2) { _ in
//                     Circle()
//                         .fill(Color(UIColor.systemGray4))
//                         .frame(width: 32, height: 32)
//                 }
//                 Spacer()
//             }
//             .padding(.leading, 16)
//             .offset(y: -35)
//         }
//     }
// }

// struct CustomTabBar: View {
//     var body: some View {
//         VStack(spacing: 0) {
//             Divider()
//                 .background(Color(UIColor.systemGray5))
            
//             HStack {
//                 ForEach(TabItem.allCases, id: \.self) { item in
//                     Spacer()
//                     VStack(spacing: 4) {
//                         Image(systemName: item.iconName)
//                             .font(.system(size: 24))
//                         Text(item.title)
//                             .font(.system(.caption, design: .monospaced))
//                     }
//                     .foregroundColor(item == .archive ? .green : .gray)
//                     Spacer()
//                 }
//             }
//             .padding(.vertical, 16)
//             .background(Color(UIColor.systemGray6))
//         }
//     }
// }

// enum TabItem: CaseIterable {
//     case archive, home, search, wallet, more
    
//     var iconName: String {
//         switch self {
//         case .archive: return "tv"
//         case .home: return "house"
//         case .search: return "magnifyingglass"
//         case .wallet: return "creditcard"
//         case .more: return "ellipsis"
//         }
//     }
    
//     var title: String {
//         switch self {
//         case .archive: return "Archive"
//         case .home: return "Home"
//         case .search: return "Search"
//         case .wallet: return "Wallet"
//         case .more: return "More"
//         }
//     }
// }

// struct ContentView_Previews: PreviewProvider {
//     static var previews: some View {
//         ContentView()
//     }
// }
