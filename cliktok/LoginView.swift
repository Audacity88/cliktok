import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSignUp = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Welcome to CliktTok")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: {
                    Task {
                        do {
                            if isSignUp {
                                try await authManager.signUp(email: email, password: password)
                            } else {
                                try await authManager.signIn(email: email, password: password)
                            }
                        } catch {
                            showError = true
                            errorMessage = error.localizedDescription
                        }
                    }
                }) {
                    Text(isSignUp ? "Sign Up" : "Sign In")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        showError = false
                        errorMessage = ""
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
                
                if showError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
} 