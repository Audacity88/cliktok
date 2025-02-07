import SwiftUI

struct HashtagTextField: View {
    @Binding var text: String
    let placeholder: String
    @State private var currentInput: String = ""
    @State private var tags: [String] = []
    @State private var selectedTag: String?
    @FocusState private var isInputFocused: Bool
    var singleTagMode: Bool = false // For search functionality
    
    init(text: Binding<String>, placeholder: String, singleTagMode: Bool = false) {
        self._text = text
        self.placeholder = placeholder
        self.singleTagMode = singleTagMode
        
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
                        .foregroundColor(.gray)
                }
                
                TextField(placeholder, text: $currentInput)
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
                                addTag(processed)
                            } else {
                                currentInput = ""
                            }
                            // Keep keyboard focused
                            isInputFocused = true
                        }
                    }
                    .onSubmit {
                        if !currentInput.isEmpty && !tags.contains(currentInput) {
                            addTag(currentInput)
                            // Keep keyboard focused
                            isInputFocused = true
                        }
                    }
                
                if singleTagMode && currentInput.isEmpty && tags.isEmpty {
                    Button(action: {
                        currentInput = ""
                        tags.removeAll()
                        updateText()
                        // Keep keyboard focused
                        isInputFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
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
                                handleTagTap(tag)
                                // Keep keyboard focused after tag interaction
                                isInputFocused = true
                            }
                    }
                    
                    // Preview pill for current input
                    if !currentInput.isEmpty {
                        TagPillView(tag: currentInput, isPreview: true)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.2), value: currentInput)
            }
        }
    }
    
    private func addTag(_ tag: String) {
        tags.append(tag)
        currentInput = ""
        updateText()
    }
    
    private func handleTagTap(_ tag: String) {
        if selectedTag == tag {
            // Second tap on the same tag - delete it
            tags.removeAll { $0 == tag }
            selectedTag = nil
            updateText()
        } else {
            // First tap - select the tag
            selectedTag = tag
        }
    }
    
    private func updateText() {
        text = tags.joined(separator: " ")
    }
}

// Extracted TagPillView for reusability and consistency
struct TagPillView: View {
    let tag: String
    var isSelected: Bool = false
    var isPreview: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .opacity(isPreview ? 0.7 : 1.0)
    }
    
    private var backgroundColor: Color {
        if isPreview {
            return Color.gray.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.6)
        } else {
            return Color.blue.opacity(0.3)
        }
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