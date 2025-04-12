import Foundation

struct AppVersion: Decodable, Equatable {
    let platform: String
    let version: String
    let is_valid: Bool
    let is_latest: Bool
    let notes: String?
} 