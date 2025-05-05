import Supabase
import SwiftUI

/// Service for accessing Supabase Storage buckets and retrieving images
class SupabaseStorageService {
    static let shared = SupabaseStorageService()
    
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://uetswhrdkmokxtnzsaeq.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVldHN3aHJka21va3h0bnpzYWVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM5MTQ1NjcsImV4cCI6MjA1OTQ5MDU2N30.1ceVlgsfTFJn6EkTitEsH97e6SAatJWsh6gHu8c25z4"
    )
    
    // Cache for downloaded images
    private var imageCache = NSCache<NSString, UIImage>()
    
    private init() {
        // Private init to enforce singleton pattern
        // Configure cache
        imageCache.countLimit = 20
    }
    
    /// Retrieves an image from a Supabase bucket
    /// - Parameters:
    ///   - name: The image name/path
    ///   - bucket: The bucket name where the image is stored
    /// - Returns: The UIImage if found, or nil if there was an error
    func fetchImage(name: String, from bucket: String) async -> UIImage? {
        // Check cache first
        let cacheKey = NSString(string: "\(bucket)_\(name)")
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            print("✅ Using cached image for \(name) from bucket \(bucket)")
            return cachedImage
        }
        
        // List files in bucket for debugging
        #if DEBUG
        Task {
            let files = await listAllFilesInBucket(bucket)
            print("📋 Files in bucket when attempting to fetch \(name): \(files.joined(separator: ", "))")
        }
        #endif
        
        print("🔄 Fetching image \(name) from Supabase bucket \(bucket)...")
        
        do {
            // Construct the path with the bucket and image name
            // Try different path formats if needed
            let imagePaths = [
                name,                               // As provided
                name.lowercased(),                  // Lowercase
                "\(name).png",                      // With PNG extension
                "\(name).jpg",                      // With JPG extension
                "\(name.lowercased()).png",         // Lowercase with PNG
                "\(name.lowercased()).jpg"          // Lowercase with JPG
            ]
            
            for path in imagePaths {
                do {
                    print("🔍 Trying path: \(path)")
                    let data = try await client.storage.from(bucket).download(path: path)
                    
                    if let image = UIImage(data: data) {
                        // Cache the image before returning
                        imageCache.setObject(image, forKey: cacheKey)
                        print("✅ Successfully loaded image with path \(path) from Supabase")
                        return image
                    }
                } catch {
                    // Just continue to the next path
                    print("⚠️ Failed with path \(path): \(error.localizedDescription)")
                    continue
                }
            }
            
            // If we reach here, none of the paths worked
            print("❌ All image path attempts failed for \(name)")
            
        } catch {
            // Handle any errors without specifically checking the type
            if error.localizedDescription.contains("not found") || error.localizedDescription.contains("404") {
                print("⚠️ Image \(name) not found in bucket \(bucket)")
            } else if error.localizedDescription.contains("bucket") {
                print("❌ Bucket \(bucket) not found in Supabase storage")
            } else {
                print("❌ Error fetching image from Supabase: \(error.localizedDescription)")
            }
        }
        
        print("⚠️ Falling back to local image for \(name)")
        return nil
    }
    
    /// Checks if an image exists in a Supabase bucket without downloading it
    /// - Parameters:
    ///   - name: The image name/path to check
    ///   - bucket: The bucket name to check in
    /// - Returns: True if the image exists, false otherwise
    func imageExists(name: String, in bucket: String) async -> Bool {
        do {
            // List objects in the bucket with a path filter to find our file
            let files = try await client.storage.from(bucket).list(path: "")
            print("📋 Files in bucket \(bucket): \(files.map { $0.name }.joined(separator: ", "))")
            
            // Check variations of the filename
            let possibleNames = [
                name,
                name.lowercased(),
                "\(name).png",
                "\(name).jpg",
                "\(name.lowercased()).png",
                "\(name.lowercased()).jpg"
            ]
            
            for file in files {
                for possibleName in possibleNames {
                    if file.name == possibleName {
                        print("✅ Found match: \(file.name) for requested image: \(name)")
                        return true
                    }
                }
            }
            
            print("❌ No matching file found for \(name) in bucket \(bucket)")
            print("💡 Available files: \(files.map { $0.name }.joined(separator: ", "))")
            return false
        } catch {
            print("❌ Error checking if image exists in Supabase: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Debug helper to list all files in a bucket
    /// Should only be used during development
    #if DEBUG
    func listAllFilesInBucket(_ bucket: String) async -> [String] {
        do {
            let files = try await client.storage.from(bucket).list(path: "")
            let fileNames = files.map { $0.name }
            print("📋 Files in bucket \(bucket): \(fileNames.joined(separator: ", "))")
            return fileNames
        } catch {
            print("❌ Error listing files in bucket \(bucket): \(error.localizedDescription)")
            return []
        }
    }
    #endif
} 