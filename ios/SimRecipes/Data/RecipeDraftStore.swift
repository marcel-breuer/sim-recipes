import Foundation

@MainActor
final class RecipeDraftStore {
    private let defaults: UserDefaults
    private let key = "recipe-drafts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ draft: RecipeDraft) throws {
        var drafts = try loadAll()
        drafts[draft.storageKey] = draft
        defaults.set(try JSONEncoder().encode(drafts), forKey: key)
    }

    func draft(id: String) throws -> RecipeDraft? {
        try loadAll()[id]
    }

    func delete(id: String) throws {
        var drafts = try loadAll()
        drafts.removeValue(forKey: id)
        defaults.set(try JSONEncoder().encode(drafts), forKey: key)
    }

    private func loadAll() throws -> [String: RecipeDraft] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return try JSONDecoder().decode([String: RecipeDraft].self, from: data)
    }
}

private extension RecipeDraft {
    var storageKey: String {
        id ?? "new"
    }
}
