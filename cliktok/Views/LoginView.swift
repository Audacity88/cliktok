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
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300)
                        .padding(.vertical, 40)
                    
                    // Guest Login Button
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
                        HStack {
                            Image(systemName: "person.fill")
                            Text("Continue as Guest")
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    
                    Text("or")
                        .foregroundColor(.gray)
                        .padding(.vertical, 10)
                    
                    TextField("", text: $email)
                        .textFieldStyle(.plain)
                        .placeholder(when: email.isEmpty) {
                            Text("Email")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(isSignUp ? .username : .emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .disabled(isLoading)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    
                    SecureField("", text: $password)
                        .textFieldStyle(.plain)
                        .placeholder(when: password.isEmpty) {
                            Text("Password")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .textContentType(isSignUp ? .newPassword : .password)
                        .submitLabel(.done)
                        .disabled(isLoading)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    
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
                            Image(systemName: isSignUp ? "person.badge.plus" : "person.fill")
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
                        withAnimation {
                            isSignUp.toggle()
                            showError = false
                            errorMessage = ""
                        }
                    }) {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .foregroundColor(.white)
                    }
                    .disabled(isLoading)
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding()
                .disabled(isLoading)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}