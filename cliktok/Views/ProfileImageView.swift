import SwiftUI

struct ProfileImageView: View {
    let imageURL: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let imageURL = imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 1)
        )
        .shadow(radius: 2)
    }
}
