import Foundation

struct SavedFilterStore {
    private static let key = "simrecipes.discovery.saved-filters"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedRecipeFilter] {
        guard let data = defaults.data(forKey: Self.key),
              let filters = try? JSONDecoder().decode([SavedRecipeFilter].self, from: data)
        else {
            return []
        }
        return filters
    }

    func save(_ filters: [SavedRecipeFilter]) {
        guard let data = try? JSONEncoder().encode(filters) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
