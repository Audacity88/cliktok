import SwiftUI
import FirebaseAuth

struct MarketerSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthenticationManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var companyName = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Company Information")) {
                    TextField("Company Name", text: $companyName)
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
        !email.isEmpty && !password.isEmpty && !companyName.isEmpty && password.count >= 6
    }
    
    private func signUp() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authManager.signUpAsMarketer(
                    email: email,
                    password: password,
                    companyName: companyName
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
