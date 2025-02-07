import SwiftUI
import FirebaseAuth

struct MarketerSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthenticationManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Brand Information")) {
                    TextField("Brand/Company Name", text: $displayName)
                }
                
                Section(header: Text("Account Details")) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                }
                
                Section {
                    Button(action: signUp) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Sign Up as Marketer")
                        }
                    }
                    .disabled(isLoading || !isValidInput)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Marketer Sign Up")
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValidInput: Bool {
        !email.isEmpty && !password.isEmpty && !displayName.isEmpty && password.count >= 6
    }
    
    private func signUp() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authManager.signUpAsMarketer(
                    email: email,
                    password: password,
                    companyName: displayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showAlert = true
            }
            isLoading = false
        }
    }
}

#Preview {
    MarketerSignUpView()
}
