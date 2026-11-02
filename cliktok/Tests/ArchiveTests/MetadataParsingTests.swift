import Foundation

/// Test cases for Internet Archive metadata parsing and license validation
/// These tests can be run on Linux using: swift Tests/ArchiveTests/MetadataParsingTests.swift

// MARK: - Test Models (simplified versions of the real models)

struct TestArchiveMetadata {
    let identifier: String
    let title: String?
    let description: String?
    let creator: String?
    let date: String?
    let licenseurl: String?
    let rights: String?
    
    var isLicenseEligible: Bool {
        let eligibleKeywords = [
            "public domain",
            "cc0",
            "creative commons zero",
            "pdm",
            "no known copyright",
            "cc by",
            "creative commons attribution"
        ]
        
        if let licenseurl = licenseurl?.lowercased() {
            if licenseurl.contains("creativecommons.org/publicdomain") ||
               licenseurl.contains("creativecommons.org/licenses/by/") ||
               licenseurl.contains("/zero/") {
                return true
            }
        }
        
        if let rights = rights?.lowercased() {
            return eligibleKeywords.contains { rights.contains($0) }
        }
        
        return false
    }
    
    var normalizedLicense: String? {
        if let licenseurl = licenseurl {
            if licenseurl.contains("publicdomain/zero") || licenseurl.contains("/zero/") {
                return "CC0"
            } else if licenseurl.contains("publicdomain/mark") {
                return "Public Domain Mark"
            } else if licenseurl.contains("licenses/by/4.0") {
                return "CC BY 4.0"
            } else if licenseurl.contains("licenses/by/3.0") {
                return "CC BY 3.0"
            }
        }
        
        if let rights = rights?.lowercased() {
            if rights.contains("public domain") {
                return "Public Domain"
            } else if rights.contains("cc0") {
                return "CC0"
            }
        }
        
        return rights ?? "Unknown License"
    }
}

// MARK: - Media File Selection Logic

struct TestArchiveFile {
    let name: String
    let format: String?
    let size: String?
    
    var videoFormat: VideoFormat? {
        let formats: [(String, VideoFormat)] = [
            ("mp4", .mp4),
            ("h.264", .mp4),
            ("mpeg4", .mp4),
            ("m4v", .m4v),
            ("quicktime", .mov),
            ("mov", .mov),
            ("matroska", .mkv)
        ]
        
        if let format = format?.lowercased() {
            if let match = formats.first(where: { format.contains($0.0) }) {
                return match.1
            }
        }
        
        let filename = name.lowercased()
        if filename.hasSuffix(".mp4") { return .mp4 }
        if filename.hasSuffix(".m4v") { return .m4v }
        if filename.hasSuffix(".mov") { return .mov }
        if filename.hasSuffix(".mkv") { return .mkv }
        
        return nil
    }
}

enum VideoFormat: Int {
    case mp4 = 1
    case m4v = 2
    case mov = 3
    case mkv = 4
}

func selectBestVideoFile(files: [TestArchiveFile]) -> TestArchiveFile? {
    let videoFiles = files.filter { $0.videoFormat != nil }
    
    let sorted = videoFiles.sorted { file1, file2 in
        let name1 = file1.name.lowercased()
        let name2 = file2.name.lowercased()
        
        if name1.contains("512kb") && !name2.contains("512kb") {
            return true
        }
        if !name1.contains("512kb") && name2.contains("512kb") {
            return false
        }
        
        if name1.hasSuffix(".mp4") && !name2.hasSuffix(".mp4") {
            return true
        }
        if !name1.hasSuffix(".mp4") && name2.hasSuffix(".mp4") {
            return false
        }
        
        if let size1 = Int(file1.size ?? "0"),
           let size2 = Int(file2.size ?? "0") {
            return size1 > size2
        }
        
        return false
    }
    
    return sorted.first
}

// MARK: - Test Suite

class TestRunner {
    var passedTests = 0
    var failedTests = 0
    
    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            print("✅ PASS: \(message)")
            passedTests += 1
        } else {
            print("❌ FAIL: \(message)")
            print("   Expected: \(expected)")
            print("   Got: \(actual)")
            failedTests += 1
        }
    }
    
    func assertNotNil<T>(_ value: T?, _ message: String) {
        if value != nil {
            print("✅ PASS: \(message)")
            passedTests += 1
        } else {
            print("❌ FAIL: \(message) - value was nil")
            failedTests += 1
        }
    }
    
    func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("Test Results: \(passedTests) passed, \(failedTests) failed")
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - Test Cases

func testLicenseValidation() {
    print("\n🧪 Running License Validation Tests...")
    let runner = TestRunner()
    
    // Test CC0 URL
    let cc0Item = TestArchiveMetadata(
        identifier: "test1",
        title: "Test Video",
        description: nil,
        creator: nil,
        date: nil,
        licenseurl: "https://creativecommons.org/publicdomain/zero/1.0/",
        rights: nil
    )
    runner.assertEqual(cc0Item.isLicenseEligible, true, "CC0 URL should be eligible")
    runner.assertEqual(cc0Item.normalizedLicense, "CC0", "CC0 URL should normalize to 'CC0'")
    
    // Test Public Domain rights text
    let pdItem = TestArchiveMetadata(
        identifier: "test2",
        title: "Test Video 2",
        description: nil,
        creator: nil,
        date: nil,
        licenseurl: nil,
        rights: "This work is in the Public Domain"
    )
    runner.assertEqual(pdItem.isLicenseEligible, true, "Public Domain rights should be eligible")
    runner.assertEqual(pdItem.normalizedLicense, "Public Domain", "Public Domain should normalize correctly")
    
    // Test CC BY 4.0
    let ccByItem = TestArchiveMetadata(
        identifier: "test3",
        title: "Test Video 3",
        description: nil,
        creator: nil,
        date: nil,
        licenseurl: "https://creativecommons.org/licenses/by/4.0/",
        rights: nil
    )
    runner.assertEqual(ccByItem.isLicenseEligible, true, "CC BY 4.0 should be eligible")
    runner.assertEqual(ccByItem.normalizedLicense, "CC BY 4.0", "CC BY 4.0 should normalize correctly")
    
    // Test ineligible license (NC restriction)
    let ncItem = TestArchiveMetadata(
        identifier: "test4",
        title: "Test Video 4",
        description: nil,
        creator: nil,
        date: nil,
        licenseurl: "https://creativecommons.org/licenses/by-nc/4.0/",
        rights: nil
    )
    runner.assertEqual(ncItem.isLicenseEligible, false, "CC BY-NC should NOT be eligible")
    
    // Test no license info (should be false for safety)
    let noLicenseItem = TestArchiveMetadata(
        identifier: "test5",
        title: "Test Video 5",
        description: nil,
        creator: nil,
        date: nil,
        licenseurl: nil,
        rights: nil
    )
    runner.assertEqual(noLicenseItem.isLicenseEligible, false, "No license info should NOT be eligible")
    
    runner.printSummary()
}

func testMediaFileSelection() {
    print("\n🧪 Running Media File Selection Tests...")
    let runner = TestRunner()
    
    // Test preference for 512kb MP4
    let files1 = [
        TestArchiveFile(name: "video.avi", format: "avi", size: "10000000"),
        TestArchiveFile(name: "video_512kb.mp4", format: "h.264", size: "5000000"),
        TestArchiveFile(name: "video.mp4", format: "h.264", size: "8000000")
    ]
    let best1 = selectBestVideoFile(files: files1)
    runner.assertEqual(best1?.name, "video_512kb.mp4", "Should prefer 512kb MP4")
    
    // Test preference for MP4 over other formats
    let files2 = [
        TestArchiveFile(name: "video.mkv", format: "matroska", size: "10000000"),
        TestArchiveFile(name: "video.mp4", format: "mpeg4", size: "8000000")
    ]
    let best2 = selectBestVideoFile(files: files2)
    runner.assertEqual(best2?.name, "video.mp4", "Should prefer MP4 format")
    
    // Test size preference when format is same
    let files3 = [
        TestArchiveFile(name: "video_low.mp4", format: "h.264", size: "2000000"),
        TestArchiveFile(name: "video_high.mp4", format: "h.264", size: "10000000")
    ]
    let best3 = selectBestVideoFile(files: files3)
    runner.assertEqual(best3?.name, "video_high.mp4", "Should prefer larger file size")
    
    // Test video format detection by extension
    let files4 = [
        TestArchiveFile(name: "document.pdf", format: nil, size: "1000000"),
        TestArchiveFile(name: "video.mp4", format: nil, size: "5000000")
    ]
    let best4 = selectBestVideoFile(files: files4)
    runner.assertEqual(best4?.name, "video.mp4", "Should detect video by extension")
    
    runner.printSummary()
}

func testMetadataParsing() {
    print("\n🧪 Running Metadata Parsing Tests...")
    let runner = TestRunner()
    
    // Test full metadata parsing
    let item = TestArchiveMetadata(
        identifier: "prelinger-archive-001",
        title: "Historic Film",
        description: "A film from the archives",
        creator: "Prelinger Archives",
        date: "1950",
        licenseurl: "https://creativecommons.org/publicdomain/zero/1.0/",
        rights: "Public Domain"
    )
    
    runner.assertEqual(item.identifier, "prelinger-archive-001", "Should parse identifier")
    runner.assertEqual(item.title, "Historic Film", "Should parse title")
    runner.assertEqual(item.creator, "Prelinger Archives", "Should parse creator")
    runner.assertEqual(item.date, "1950", "Should parse date")
    runner.assertNotNil(item.licenseurl, "Should have license URL")
    runner.assertEqual(item.isLicenseEligible, true, "Should be eligible with CC0")
    
    runner.printSummary()
}

// MARK: - Main Execution

print("🚀 Starting Internet Archive Metadata Tests")
print("=" + String(repeating: "=", count: 49))

testLicenseValidation()
testMediaFileSelection()
testMetadataParsing()

print("\n✨ All test suites completed!")
