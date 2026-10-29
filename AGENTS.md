# Agent instructions

When the docs disagree with the code, follow the code and list each conflict.

## Current implementation

These current-code notes supersede the conflicting statements in legacy `.cursorrules` listed below. Its quality and security goals remain goals for future implementation, not claims that the existing app meets them. Do not change behavior solely to make it match those legacy statements.

| Topic / legacy rule | Current code and guidance | Evidence |
| --- | --- | --- |
| Completeness / no placeholders | `PaymentManager.processPayment` is a TODO stub that immediately reports success. Do not describe that method as completed payment processing. | `cliktok/Managers/PaymentManager.swift:104-107` |
| Swift features / protocol architecture | The app uses Swift 5 language mode and SwiftUI MVVM with model structs and reference view models. Follow those existing patterns; the app does not require the latest language mode or declare its own protocols. | `cliktok.xcodeproj/project.pbxproj:314,347`; `cliktok/Models/User.swift:10`; `cliktok/ViewModels/VideoFeedViewModel.swift:6-18` |
| Folder layout | Use the existing `cliktok/` directories: App, Models, ViewModels, Views, Services, Managers, Utilities, Extensions, Resources and Assets.xcassets (also Preview Content). There is no Features/Core/UI layout. Resources does exist and contains fonts. | `cliktok/Models/User.swift:1`; `cliktok/ViewModels/VideoFeedViewModel.swift:1`; `cliktok/Services/ImageCache.swift:27`; tracked directory inventory, including `cliktok/Resources/Fonts/` |
| Error handling | Follow each existing API: image loading uses `async throws`; payment processing uses a `(Bool, String?)` callback. `Result` is not the app's established error convention. | `cliktok/Services/ImageCache.swift:27`; `cliktok/Managers/PaymentManager.swift:105` |
| Persistence | Current models use Codable and Firebase Firestore, not CoreData. | `cliktok/Models/User.swift:3,10-11`; `cliktok/ViewModels/VideoFeedViewModel.swift:18` |
| Certificate pinning | No app-level certificate pinning was found in first-party Swift. The feed uses `URLSession.shared`; StripeService creates a session with no custom trust delegate. Do not claim pinning is implemented or infer SDK guarantees. | `cliktok/ViewModels/VideoFeedViewModel.swift:407`; `cliktok/Services/StripeService.swift:85-104` |
| App Transport Security | `NSAllowsArbitraryLoads` is true, relaxing ATS. This describes current configuration and does not certify transport security. | `cliktok/Info.plist:21-24` |
| Unit/UI test suites | No first-party test suite or XCTest/XCUITest target is present. The Xcode project has only the application native target; do not invent a test command or claim tests passed. | `cliktok.xcodeproj/project.pbxproj:78-107`; first-party tracked-file inventory |
| CI/CD | No CI configuration is tracked in the first-party repository. Do not assume a local pipeline exists; external CI was not checked. | first-party tracked-file inventory; application target at `cliktok.xcodeproj/project.pbxproj:78-107` |
| Unit-test coverage | No unit-test suite or coverage result is available locally. Coverage is a future quality goal, not a measured current property. | `cliktok.xcodeproj/project.pbxproj:78-107`; first-party tracked-file inventory |

Inventory and symbol checks exclude `build-lead/` and `server/node_modules/`, which contain third-party build/dependency material. These notes record source inspection, not build, device, security or payment validation.
