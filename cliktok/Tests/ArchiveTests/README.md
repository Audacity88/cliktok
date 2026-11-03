# Internet Archive Tests

## Overview

These tests validate the core logic for Internet Archive metadata parsing, license validation, and media file selection. They are designed to run standalone without requiring Xcode or iOS simulators.

## Running the Tests

### On macOS with Swift installed:

```bash
swift Tests/ArchiveTests/MetadataParsingTests.swift
```

### On Linux with Swift installed:

```bash
swift Tests/ArchiveTests/MetadataParsingTests.swift
```

### Expected Output:

```
🚀 Starting Internet Archive Metadata Tests
==================================================

🧪 Running License Validation Tests...
✅ PASS: CC0 URL should be eligible
✅ PASS: CC0 URL should normalize to 'CC0'
✅ PASS: Public Domain rights should be eligible
✅ PASS: Public Domain should normalize correctly
✅ PASS: CC BY 4.0 should be eligible
✅ PASS: CC BY 4.0 should normalize correctly
✅ PASS: CC BY-NC should NOT be eligible
✅ PASS: No license info should NOT be eligible

==================================================
Test Results: 8 passed, 0 failed
==================================================

🧪 Running Media File Selection Tests...
✅ PASS: Should prefer 512kb MP4
✅ PASS: Should prefer MP4 format
✅ PASS: Should prefer larger file size
✅ PASS: Should detect video by extension

==================================================
Test Results: 4 passed, 0 failed
==================================================

🧪 Running Metadata Parsing Tests...
✅ PASS: Should parse identifier
✅ PASS: Should parse title
✅ PASS: Should parse creator
✅ PASS: Should parse date
✅ PASS: Should have license URL
✅ PASS: Should be eligible with CC0

==================================================
Test Results: 6 passed, 0 failed
==================================================

✨ All test suites completed!
```

## Test Coverage

### License Validation Tests
- ✅ CC0 license URL recognition
- ✅ Public Domain rights text detection
- ✅ CC BY 4.0 license validation
- ✅ Rejection of NC (Non-Commercial) restrictions
- ✅ Safe default for missing license info

### Media File Selection Tests
- ✅ Preference for 512kb MP4 variants
- ✅ MP4 format prioritization
- ✅ Size-based selection when formats match
- ✅ Video format detection by file extension

### Metadata Parsing Tests
- ✅ Identifier extraction
- ✅ Title parsing
- ✅ Creator/contributor parsing
- ✅ Date parsing
- ✅ License URL handling
- ✅ Eligibility determination

## Known Limitations

These tests validate the core parsing and selection logic but do not:
- Test actual network requests to archive.org
- Validate AVPlayer integration
- Test UI rendering
- Verify Firebase integration

These integration tests would require an iOS simulator or device with Xcode.

## Real-World Test Items

To manually verify the implementation works with real Internet Archive items, test with these known-good identifiers:

1. **prelinger**: Public Domain classic films
   - License: Public Domain
   - Has multiple MP4 derivatives

2. **gov.archives.arc.49442**: US Government archives
   - License: Public Domain (US Gov)
   - Has 512kb MP4 derivatives

3. **ElephantsDream**: Open movie project
   - License: CC BY 2.5
   - Has multiple quality MP4s

You can verify metadata at:
```
https://archive.org/metadata/{identifier}
```

Example:
```
https://archive.org/metadata/prelinger
```
