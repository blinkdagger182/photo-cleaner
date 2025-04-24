import CoreData

struct PersistenceController {
    // Shared instance for the app
    static let shared = PersistenceController()
    
    // Preview instance for SwiftUI previews
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    // The persistent container for the application
    let container: NSPersistentContainer
    
    // Initialize with optional in-memory store for previews
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SmartAlbumModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                // Handle the error appropriately in a production app
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        
        // Merge policy to handle conflicts
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // Save context if there are changes
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Handle the error appropriately in a production app
                print("Error saving context: \(error)")
            }
        }
    }
    
    // Helper to create a background context for processing
    func backgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }
} 