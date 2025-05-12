import SwiftUI

// Helper view to detect scroll position changes with enhanced stability
struct ScrollDetectorView: View {
    @Binding var yOffset: CGFloat
    var onScrollDirectionChanged: ((Bool) -> Void)?
    
    // To track previous offset for direction detection
    @State private var previousOffset: CGFloat = 0
    @State private var scrollCount = 0
    @State private var consecutiveScrollsInSameDirection = 0
    @State private var lastDirectionChangeTime = Date()
    
    // Buffer for scroll direction changes
    @State private var scrollDownDistance: CGFloat = 0
    @State private var scrollUpDistance: CGFloat = 0
    @State private var lastReportedDirection: Bool? = nil
    
    // Constants
    private let hideHeaderThreshold: CGFloat = 30
    private let showHeaderThreshold: CGFloat = 15
    
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geo.frame(in: .named("scrollView")).minY
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let threshold: CGFloat = 5 // Minimum change to register as scrolling
                    let now = Date()
                    
                    // Near the top of the scroll view - always show header
                    if value > -20 {
                        // Reset accumulated distances
                        scrollDownDistance = 0
                        scrollUpDistance = 0
                        // Always show header when near top
                        if lastReportedDirection != false {
                            lastReportedDirection = false
                            onScrollDirectionChanged?(false) // Scrolling up = show header
                        }
                        yOffset = value
                        return
                    }
                    
                    // Only look at significant changes to filter out noise
                    if abs(value - previousOffset) > threshold {
                        let isScrollingDown = value < previousOffset
                        let distanceMoved = abs(value - previousOffset)
                        
                        // Add stability check - need consistent direction for several updates
                        let timeSinceLastDirection = now.timeIntervalSince(lastDirectionChangeTime)
                        
                        // Check if direction matches previous direction
                        if scrollCount > 0 && isScrollingDown == (previousOffset > value) {
                            consecutiveScrollsInSameDirection += 1
                        } else {
                            // Direction changed - reset appropriate distance counter
                            if isScrollingDown {
                                scrollUpDistance = 0
                            } else {
                                scrollDownDistance = 0
                            }
                            consecutiveScrollsInSameDirection = 0
                            lastDirectionChangeTime = now
                        }
                        
                        // Accumulate distance in current direction
                        if isScrollingDown {
                            scrollDownDistance += distanceMoved
                        } else {
                            scrollUpDistance += distanceMoved
                        }
                        
                        // Only notify when we have accumulated enough distance in one direction
                        // For scrolling down (hiding header): need more distance
                        // For scrolling up (showing header): need less distance
                        if (isScrollingDown && scrollDownDistance > hideHeaderThreshold && lastReportedDirection != true) {
                            lastReportedDirection = true
                            onScrollDirectionChanged?(true)
                            scrollDownDistance = 0
                        } else if (!isScrollingDown && scrollUpDistance > showHeaderThreshold && lastReportedDirection != false) {
                            lastReportedDirection = false
                            onScrollDirectionChanged?(false)
                            scrollUpDistance = 0
                        }
                        
                        // Update for next comparison
                        previousOffset = value
                        scrollCount += 1
                    }
                    
                    yOffset = value
                }
        }
        .frame(height: 0)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
} 