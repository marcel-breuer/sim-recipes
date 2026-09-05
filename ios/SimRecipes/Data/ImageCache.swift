import Foundation

actor ImageCache {
    private let directoryURL: URL
    private let fileManager = FileManager.default

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RecipeImages", isDirectory: true)
    }

    func store(_ data: Data, recipeID: String, imageID: String) throws -> URL {
        let recipeDirectory = directoryURL.appendingPathComponent(recipeID, isDirectory: true)
        try fileManager.createDirectory(at: recipeDirectory, withIntermediateDirectories: true)
        let url = recipeDirectory.appendingPathComponent(imageID)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func cachedURL(recipeID: String, imageID: String) -> URL? {
        let url = directoryURL
            .appendingPathComponent(recipeID, isDirectory: true)
            .appendingPathComponent(imageID)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func remove(recipeID: String) throws {
        let url = directoryURL.appendingPathComponent(recipeID, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
