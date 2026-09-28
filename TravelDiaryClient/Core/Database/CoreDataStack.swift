import CoreData
import Foundation

final class CoreDataStack: @unchecked Sendable {
    static let shared = CoreDataStack()

    @MainActor
    static let preview = CoreDataStack(inMemory: true)

    let logger: Logger
    private let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false, modelName: String = "TravelDiary", storeURL: URL? = nil, logger: Logger = ConsoleLogger()) {
        self.logger = logger
        let container = NSPersistentContainer(name: modelName)
        let description = container.persistentStoreDescriptions.first
        if inMemory {
            description?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let url = storeURL ?? Self.defaultStoreURL()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            description?.url = url
        }
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load CoreData store: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.container = container
    }

    func performBackgroundTask<T: Sendable>(_ work: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
                do {
                    let value = try work(context)
                    if context.hasChanges { try context.save() }
                    continuation.resume(returning: value)
                } catch {
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "TravelDiary", directoryHint: .isDirectory)
            .appending(path: "CoreData", directoryHint: .isDirectory)
            .appending(path: "TravelDiary.sqlite")
    }
}
