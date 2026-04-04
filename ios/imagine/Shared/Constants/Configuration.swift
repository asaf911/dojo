//
//  Configuration.swift
//  Dojo
//
//  Created by Michael Tabachnik on 10/15/24.
//

import Foundation
import FirebaseStorage

struct Config {
    static var appsFlyerDevKey          = "eLUB6YrwUiT9stNvVy5BRh"
    static var appsFlyerAppleAppID      = "6503365052"
    static var mixpanelToken            = "6c6496e5e2332f2993f0867302531535"
    static var applePurchasesApiKey     = "appl_xGtXKpEiULtTqRvsPjnDIpGvROf"
    static var oneSignalAppID           = "379f6073-0247-4fcb-b3d5-d978338826a9"
    static var storagePathPrefix        = "gs://"
    static var productionServerPath     = "imagine-c6162.appspot.com/"
    static var devServerPath            = "imaginedev-e5fd3.appspot.com/"
    static var audioFileJsonFileName    = "audioFiles.json"
    
    // MARK: - OneLink Deep Link Configuration
    static var oneLinkBaseURL           = "https://medidojo.onelink.me/miw9/share"

    // MARK: - App Install Source (for Mixpanel filtering)
    /// "simulator" | "xcode" | "testflight" | "store"
    /// Filter in Mixpanel: where properties.source == "store" for production users only
    static var appSource: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #elseif DEBUG
        // Debug builds only run from Xcode (never TestFlight/Store).
        // Receipt check is unreliable: a stale sandbox receipt can persist when
        // overwriting a TestFlight install with an Xcode install.
        return "xcode"
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return "xcode"
        }
        return receiptURL.lastPathComponent == "sandboxReceipt" ? "testflight" : "store"
        #endif
    }

    // MARK: - Server Selection (runtime, from Dev Mode toggle)
    /// Human-readable label for logging: "Production" or "Dev"
    static var serverLabel: String {
        SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
            ? "Dev"
            : "Production"
    }

    /// Firebase Storage instance for the active server. Use when constructing URLs ourselves (e.g. pathSteps, audioFiles).
    static var activeStorage: Storage {
        SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
            ? Storage.storage(url: "gs://\(devServerPath.dropLast())")
            : Storage.storage()
    }

    /// Storage instance that matches the bucket in the given gs:// URL. Use when the URL comes from external data (catalogs, AI response, cache) which may be prod or dev.
    static func storage(for urlString: String) -> Storage {
        if urlString.contains("imaginedev-e5fd3.appspot.com") {
            return Storage.storage(url: "gs://imaginedev-e5fd3.appspot.com")
        }
        return Storage.storage()
    }

    // MARK: - Single Content Bucket (prod)

    /// Content bucket for MP3s, images, audioFiles.json, pathSteps.json. Always prod.
    static var contentStorage: Storage {
        Storage.storage()
    }

    /// Content bucket path (gs://). Always prod.
    static var contentStoragePath: String {
        "gs://imagine-c6162.appspot.com/"
    }

    /// Rewrites dev bucket media URLs to content bucket. Use before fetching MP3s or images.
    static func resolveMediaUrl(_ url: String) -> String {
        if url.contains("imaginedev-e5fd3.appspot.com") {
            return url.replacingOccurrences(of: "imaginedev-e5fd3.appspot.com", with: "imagine-c6162.appspot.com")
        }
        return url
    }

    /// Active storage path (bucket) based on useDevServer flag. Used for Firebase Storage refs.
    static var activeServerPath: String {
        SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
            ? devServerPath
            : productionServerPath
    }

    /// Cloud Functions base URL (region + project). Dev: imaginedev-e5fd3, Prod: imagine-c6162.
    private static var cloudFunctionsBase: String {
        SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
            ? "https://us-central1-imaginedev-e5fd3.cloudfunctions.net"
            : "https://us-central1-imagine-c6162.cloudfunctions.net"
    }

    // MARK: - Catalogs API (GET /catalogs)
    static var catalogsURL: URL {
        URL(string: cloudFunctionsBase + "/getCatalogs")!
    }

    // MARK: - Meditations API (POST /meditations)
    static var meditationsURL: URL {
        URL(string: cloudFunctionsBase + "/postMeditations")!
    }

    // MARK: - AI Request API (POST /ai/request - unified classify + route + respond)
    static var aiRequestURL: URL {
        URL(string: cloudFunctionsBase + "/postAIRequest")!
    }

    // MARK: - Fractional Plan API (POST /postFractionalPlan)
    static var fractionalPlanURL: URL {
        URL(string: cloudFunctionsBase + "/postFractionalPlan")!
    }
}
