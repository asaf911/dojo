//
//  Authentication+Dependencies.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//

import Foundation

extension Authentication {
    /// Dependencies required by the authentication feature.
    struct Dependencies {
        var emailValidationService: EmailValidationService

        static var live: Self {
            .init(emailValidationService: .live)
        }

        static var preview: Self {
            .init(emailValidationService: .preview)
        }
    }
}
