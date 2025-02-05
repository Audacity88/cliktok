import SwiftUI
import FirebaseAuth
import AuthenticationServices

struct LoginView: View {
    // Use StateObject to observe changes
    @StateObject private var authManager = AuthenticationManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Welcome to ClikTok")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(isSignUp ? .username : .emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .disabled(isLoading)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(isSignUp ? .newPassword : .password)
                    .submitLabel(.done)
                    .disabled(isLoading)
                
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        
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
                    HStack {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        
                        do {
                            try await authManager.signInAnonymously()
                        } catch {
                            showError = true
                            errorMessage = error.localizedDescription
                        }
                    }
                }) {
                    Text("Continue as Guest")
                        .foregroundColor(.gray)
                }
                .disabled(isLoading)
                
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
                .disabled(isLoading)
                
                if showError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .disabled(isLoading)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}