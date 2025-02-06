import SwiftUI

struct GuestRestrictedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Guest Access Restricted")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please sign in or create an account to access this feature")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            NavigationLink(destination: LoginView()) {
                Text("Sign In")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        GuestRestrictedView()
    }
}
