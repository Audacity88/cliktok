# Video Identifier System

The app uses several types of identifiers to track videos across different sources. This document explains how they work and interact.

## Types of Identifiers

### 1. `ArchiveVideo.identifier`
- Used in the `ArchiveVideo` model
- A stable identifier for both test videos and Internet Archive videos
- Examples:
  - Test videos: "test_pattern", "big_buck_bunny"
  - Internet Archive videos: Original archive.org identifier

### 2. `Video.archiveIdentifier`
- Used in the main `Video` model
- Optional field specifically for Internet Archive videos
- Stores the Internet Archive's identifier when converting from `ArchiveVideo` to `Video`
- Used to maintain a link to the original Internet Archive video

### 3. `Video.stableId`
- A computed property that provides a consistent identifier across app restarts
- Logic:
  ```swift
  if userID == "archive_user", let archiveId = archiveIdentifier {
      return "archive_\(archiveId)"
  }
  return id ?? UUID().uuidString
  ```

## Identifier Flow Examples

### 1. Internet Archive Videos
```
ArchiveVideo.identifier -> Video.archiveIdentifier -> Video.stableId
"some_video_id"        -> "some_video_id"         -> "archive_some_video_id"
```

### 2. Regular Uploaded Videos
```
Firestore document ID -> Video.id -> Video.stableId
"abc123"             -> "abc123" -> "abc123"
```

### 3. Test Videos
```
ArchiveVideo.identifier -> Video.archiveIdentifier -> Video.stableId
"test_pattern"         -> "test_pattern"         -> "archive_test_pattern"
```

## Benefits of This System

1. **Firestore Compatibility**
   - Avoids conflicts with Firestore's `@DocumentID` system
   - Maintains proper document ID management for uploaded videos

2. **Archive Integration**
   - Preserves original Internet Archive identifiers
   - Enables proper linking back to archive.org sources

3. **SwiftUI Integration**
   - Provides stable identifiers for SwiftUI's view identification
   - Ensures consistent list updates and animations

4. **Test Content Management**
   - Allows test videos to have consistent identifiers
   - No need for Firestore documents for test content

## Usage Guidelines

1. When working with Internet Archive videos:
   - Always use the original archive.org identifier
   - Pass it through the `archiveIdentifier` field

2. When working with uploaded videos:
   - Let Firestore manage the document ID
   - Use the Firestore ID as the stable identifier

3. When working with test videos:
   - Use descriptive, consistent identifiers
   - Follow the "test_" prefix convention

4. When displaying videos in SwiftUI:
   - Always use `stableId` for list identifiers
   - Example: `ForEach(videos, id: \.stableId)` 