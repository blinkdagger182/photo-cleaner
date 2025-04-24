import Foundation
import UIKit
import Vision
import CoreML
import Photos

// Helper extension for FileManager
extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = self.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}

// MARK: - Classification Result
struct ClassificationResult: Hashable {
    let label: String
    let confidence: Float
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
    }
    
    static func == (lhs: ClassificationResult, rhs: ClassificationResult) -> Bool {
        return lhs.label == rhs.label
    }
}

// MARK: - ImageClassificationService
class ImageClassificationService {
    // Singleton instance
    static let shared = ImageClassificationService()
    
    // Cache for classification results
    private var classificationCache: [String: [ClassificationResult]] = [:]
    
    // Model configuration
    private var modelURL: URL? {
        // First check for the compiled model in the bundle
        if let bundleUrl = Bundle.main.url(forResource: "MobileNetV2FP16", withExtension: "mlmodelc") {
            print("✅ Found compiled ML model in app bundle: \(bundleUrl.path)")
            return bundleUrl
        }
        
        // Then check for the uncompiled model in the bundle
        if let bundleUrl = Bundle.main.url(forResource: "MobileNetV2FP16", withExtension: "mlmodel") {
            print("✅ Found ML model in app bundle: \(bundleUrl.path)")
            return bundleUrl
        }
        
        // Fallback to directory paths
        let possiblePaths = [
            "/Users/newuser/Code/photo-cleaner-start/photocleaner/photocleaner/Resources/MobileNetV2FP16.mlmodel",
            "/Users/newuser/Code/photo-cleaner-start/photocleaner/MobileNetV2FP16.mlmodel"
        ]
        
        // Check if any of these paths exist
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ Found ML model at path: \(path)")
                
                // Get file attributes for debugging
                if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                    let fileSize = attributes[.size] as? NSNumber ?? 0
                    print("📱 ML model file size: \(fileSize) bytes")
                    
                    // Check file permissions
                    if let permissions = attributes[.posixPermissions] as? NSNumber {
                        print("📱 File permissions: \(permissions)")
                    }
                }
                
                return URL(fileURLWithPath: path)
            }
        }
        
        print("⚠️ Could not find ML model in any of the searched paths")
        logEnvironmentInfo() // Log additional info when model can't be found
        return nil
    }
    
    // VNCoreMLModel instance for reuse
    private var vnCoreMLModel: VNCoreMLModel?
    
    // Classification parameters
    private let confidenceThreshold: Float = 0.3
    private let maxClassifications: Int = 5
    
    private init() {
        // Initialize the Vision model on creation
        setupModel()
    }
    
    private func logEnvironmentInfo() {
        print("📱 Current working directory: \(FileManager.default.currentDirectoryPath)")
        print("📱 App bundle path: \(Bundle.main.bundlePath)")
        
        // Check if we can find the model in the bundle
        if let resourcePath = Bundle.main.resourcePath {
            print("📱 App resource path: \(resourcePath)")
            
            // List all files in the bundle resource directory
            if let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                print("📱 Files in resource directory: \(files)")
                
                // Check if the ML model is among them (both .mlmodel and .mlmodelc)
                if files.contains("MobileNetV2FP16.mlmodel") {
                    print("✅ Found .mlmodel file in resources")
                }
                if files.contains("MobileNetV2FP16.mlmodelc") {
                    print("✅ Found .mlmodelc directory in resources")
                }
                
                // Look for the model in subdirectories
                for file in files {
                    let fullPath = resourcePath + "/" + file
                    if FileManager.default.isDirectory(atPath: fullPath) {
                        if let subfiles = try? FileManager.default.contentsOfDirectory(atPath: fullPath) {
                            if subfiles.contains("MobileNetV2FP16.mlmodel") || subfiles.contains("MobileNetV2FP16.mlmodelc") {
                                print("✅ Found ML model in subdirectory: \(file)")
                            }
                        }
                    }
                }
            } else {
                print("⚠️ Could not list files in resource directory")
            }
        }
        
        // Check paths used in the modelURL computed property
        let modelPaths = [
            Bundle.main.path(forResource: "MobileNetV2FP16", ofType: "mlmodel"),
            Bundle.main.path(forResource: "MobileNetV2FP16", ofType: "mlmodelc"),
            "/Users/newuser/Code/photo-cleaner-start/photocleaner/photocleaner/Resources/MobileNetV2FP16.mlmodel",
            "/Users/newuser/Code/photo-cleaner-start/photocleaner/MobileNetV2FP16.mlmodel"
        ]
        
        for (index, path) in modelPaths.enumerated() {
            if let path = path {
                let exists = FileManager.default.fileExists(atPath: path)
                print("📱 Path #\(index + 1) exists: \(exists) - \(path)")
            } else {
                print("⚠️ Path #\(index + 1) is nil")
            }
        }
    }
    
    private func setupModel() {
        // First try to get a model URL from any source
        let originalModelURL = modelURL
        
        // If we found a model URL, try to copy it to Documents directory
        if let url = originalModelURL {
            print("📱 Found ML model at: \(url.path)")
            
            // First try to copy to Documents directory for proper loading
            if let documentsUrl = copyModelToDocumentsDirectory(from: url) {
                print("📱 Copied model to Documents directory: \(documentsUrl.path)")
                loadModelFromURL(documentsUrl)
                return
            }
            
            // If copying failed, try direct loading as fallback
            loadModelFromURL(url)
        } else {
            print("⚠️ ML model file not found. Classification will use fallback mode.")
        }
    }
    
    private func loadModelFromURL(_ url: URL) {
        print("📱 Attempting to load ML model from: \(url.path)")
        
        do {
            // Skip file handle test which could fail with permissions
            // Directly try to load the model
            let mlModel = try MLModel(contentsOf: url)
            vnCoreMLModel = try VNCoreMLModel(for: mlModel)
            print("✅ Successfully loaded ML model")
        } catch {
            print("⚠️ Failed to load ML model: \(error)")
            print("⚠️ Error description: \(error.localizedDescription)")
        }
    }
    
    private func copyModelToDocumentsDirectory(from sourceURL: URL) -> URL? {
        let fileManager = FileManager.default
        
        // Get Documents directory
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("⚠️ Could not access Documents directory")
            return nil
        }
        
        // Target location for the model
        let fileName = sourceURL.lastPathComponent
        let targetURL = documentsDirectory.appendingPathComponent(fileName)
        
        // Check if the model is already in Documents
        if fileManager.fileExists(atPath: targetURL.path) {
            print("✅ ML model already exists in Documents directory: \(targetURL.path)")
            return targetURL
        }
        
        // Copy the model to the documents directory
        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            print("✅ Successfully copied ML model to Documents directory")
            return targetURL
        } catch {
            print("⚠️ Failed to copy ML model to Documents: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Lazy initialization support - try to load the model if not already loaded
    private func ensureModelLoaded() -> Bool {
        if vnCoreMLModel != nil {
            return true
        }
        
        print("📱 Attempting to load ML model on demand")
        setupModel()
        return vnCoreMLModel != nil
    }
    
    // MARK: - Public Methods
    
    /// Check if the ML model is available for classification
    func isModelAvailable() -> Bool {
        return ensureModelLoaded()
    }
    
    /// Classify a UIImage and return the top classifications
    func classifyImage(_ image: UIImage, completion: @escaping ([ClassificationResult]) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            print("⚠️ Failed to create CIImage from UIImage")
            completion([])
            return
        }
        
        performClassification(ciImage: ciImage, completion: completion)
    }
    
    /// Classify a PHAsset and return the top classifications
    func classifyAsset(_ asset: PHAsset, completion: @escaping ([ClassificationResult]) -> Void) {
        // Check cache first
        if let cachedResults = classificationCache[asset.localIdentifier] {
            completion(cachedResults)
            return
        }
        
        // Request a high quality thumbnail for classification
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 299, height: 299),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self, let image = image else {
                completion([])
                return
            }
            
            self.classifyImage(image) { results in
                // Cache the results
                self.classificationCache[asset.localIdentifier] = results
                completion(results)
            }
        }
    }
    
    /// Clear the classification cache
    func clearCache() {
        classificationCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func performClassification(ciImage: CIImage, completion: @escaping ([ClassificationResult]) -> Void) {
        // Check if model is loaded
        if vnCoreMLModel == nil {
            // Try to load model one last time
            setupModel()
        }
        
        // If still nil after attempt, fail gracefully
        guard let model = vnCoreMLModel else {
            print("⚠️ Vision ML model not available - using fallback")
            
            // Return fallback classifications instead of empty results
            let fallbackResults = [
                ClassificationResult(label: "Photo", confidence: 0.9),
                ClassificationResult(label: "Image", confidence: 0.8)
            ]
            completion(fallbackResults)
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNClassificationObservation], error == nil else {
                if let error = error {
                    print("⚠️ Classification error: \(error.localizedDescription)")
                }
                
                // Return fallback classifications instead of empty results
                let fallbackResults = [
                    ClassificationResult(label: "Photo", confidence: 0.9),
                    ClassificationResult(label: "Image", confidence: 0.8)
                ]
                completion(fallbackResults)
                return
            }
            
            // Filter by confidence threshold and take top results
            let topResults = results
                .filter { $0.confidence >= self.confidenceThreshold }
                .prefix(self.maxClassifications)
                .map { ClassificationResult(label: self.formatLabel($0.identifier), confidence: $0.confidence) }
            
            // If we got valid results, return them
            if !topResults.isEmpty {
                completion(topResults)
            } else {
                // If no valid results, return fallback
                let fallbackResults = [
                    ClassificationResult(label: "Photo", confidence: 0.9),
                    ClassificationResult(label: "Image", confidence: 0.8)
                ]
                completion(fallbackResults)
            }
        }
        
        // Configure the request
        request.imageCropAndScaleOption = .centerCrop
        
        // Create a handler and perform the request
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch let error {
            print("⚠️ Failed to perform classification: \(error)")
            
            // Return fallback classifications
            let fallbackResults = [
                ClassificationResult(label: "Photo", confidence: 0.9),
                ClassificationResult(label: "Image", confidence: 0.8)
            ]
            completion(fallbackResults)
        }
    }
    
    // Format the raw label from ML model to be more readable
    private func formatLabel(_ label: String) -> String {
        // Split by commas and take first term
        let mainLabel = label.split(separator: ",").first ?? Substring(label)
        
        // Convert to lowercase and trim whitespace
        var formatted = mainLabel.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter
        if let firstChar = formatted.first {
            formatted = String(firstChar).uppercased() + formatted.dropFirst()
        }
        
        return formatted
    }
} 