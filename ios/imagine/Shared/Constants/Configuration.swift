//
//  Configuration.swift
//  Dojo
//
//  Created by Michael Tabachnik on 10/15/24.
//

import Foundation

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

    // MARK: - Server Selection (runtime, from Dev Mode toggle)
    /// Human-readable label for logging: "Production" or "Dev"
    static var serverLabel: String {
        SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
            ? "Dev"
            : "Production"
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
}
