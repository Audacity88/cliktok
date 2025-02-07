import SwiftUI

struct HashtagTextField: View {
    @Binding var text: String
    let placeholder: String
    @State private var currentInput: String = ""
    @State private var tags: [String] = []
    @State private var selectedTag: String?
    @FocusState private var isInputFocused: Bool
    var singleTagMode: Bool = false // For search functionality
    var onTagsChanged: (([String]) -> Void)?
    
    init(text: Binding<String>, placeholder: String, singleTagMode: Bool = false, onTagsChanged: (([String]) -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.singleTagMode = singleTagMode
        self.onTagsChanged = onTagsChanged
        
        // Initialize tags from text
        let initialTags = text.wrappedValue
            .split(separator: " ")
            .map { String($0).replacingOccurrences(of: " ", with: "") }
            .filter { !$0.isEmpty }
        _tags = State(initialValue: initialTags)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Input field
            HStack {
                if singleTagMode {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                }
                
                TextField(placeholder, text: $currentInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onChange(of: currentInput) { oldValue, newValue in
                        // Convert to lowercase and remove spaces
                        let processed = newValue.lowercased().replacingOccurrences(of: " ", with: "")
                        if processed != newValue {
                            currentInput = processed
                        }
                        
                        // Handle space or return
                        if newValue.contains(" ") || newValue.contains("\n") {
                            if !processed.isEmpty && !tags.contains(processed) {
                                if singleTagMode {
                                    // In single tag mode, replace existing tag
                                    tags = [processed]
                                } else {
                                    // In multi-tag mode, append
                                    tags.append(processed)
                                }
                                currentInput = ""
                                updateText()
                            } else {
                                currentInput = ""
                            }
                            // Keep keyboard focused
                            DispatchQueue.main.async {
                                isInputFocused = true
                            }
                        }
                    }
                    .onSubmit {
                        if !currentInput.isEmpty && !tags.contains(currentInput) {
                            if singleTagMode {
                                // In single tag mode, replace existing tag
                                tags = [currentInput]
                            } else {
                                // In multi-tag mode, append
                                tags.append(currentInput)
                            }
                            currentInput = ""
                            updateText()
                            // Keep keyboard focused
                            DispatchQueue.main.async {
                                isInputFocused = true
                            }
                        }
                    }
                
                if singleTagMode && !currentInput.isEmpty {
                    Button(action: {
                        currentInput = ""
                        tags.removeAll()
                        updateText()
                        // Keep keyboard focused
                        DispatchQueue.main.async {
                            isInputFocused = true
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Tag pills container
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Existing tags
                    ForEach(tags, id: \.self) { tag in
                        TagPillView(tag: tag, isSelected: selectedTag == tag)
                            .onTapGesture {
                                if singleTagMode {
                                    // In single tag mode, tapping removes the tag
                                    tags.removeAll()
                                    updateText()
                                } else {
                                    handleTagTap(tag)
                                }
                                // Keep keyboard focused
                                DispatchQueue.main.async {
                                    isInputFocused = true
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: tags.isEmpty ? 0 : nil)
        }
        .onChange(of: tags) { oldValue, newValue in
            updateText()
            onTagsChanged?(newValue)
        }
        .onChange(of: text) { oldValue, newValue in
            if newValue.isEmpty && !tags.isEmpty {
                tags.removeAll()
                currentInput = ""
                onTagsChanged?([])
            }
        }
    }
    
    private func updateText() {
        withAnimation {
            text = tags.joined(separator: " ")
        }
    }
    
    private func handleTagTap(_ tag: String) {
        if selectedTag == tag {
            // Second tap on the same tag - delete it
            withAnimation {
                tags.removeAll { $0 == tag }
                selectedTag = nil
            }
        } else {
            // First tap - select the tag
            withAnimation {
                selectedTag = tag
            }
        }
        updateText()
        // Keep keyboard focused
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }
}

// Extracted TagPillView for reusability and consistency
struct TagPillView: View {
    let tag: String
    var isSelected: Bool
    
    var body: some View {
        Text("#\(tag)")
            .font(.system(.subheadline, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 20) {
        Form {
            HashtagTextField(text: .constant("funny dance music"), placeholder: "Enter hashtags")
        }
        Form {
            HashtagTextField(text: .constant("funny"), placeholder: "Search hashtags...", singleTagMode: true)
        }
    }
}