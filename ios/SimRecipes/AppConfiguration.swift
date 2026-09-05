import Foundation

enum AppConfiguration {
    static var apiBaseURL: URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            let url = URL(string: value)
        else {
            preconditionFailure("APIBaseURL must be configured in Info.plist")
        }

        return url
    }

    static let communityStandardsURL = URL(string: "https://simrecipes.app/docs/community-standards")!
    static let supportEmailURL = URL(string: "mailto:support@simrecipes.app")!
}
