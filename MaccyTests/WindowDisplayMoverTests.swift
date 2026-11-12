import AppKit
import Testing
@testable import Maccy

@MainActor
struct WindowDisplayMoverTests {
  @Test func preservesSizeAndRelativeCenter() {
    let result = DisplayTransfer.transferredRect(
      window: CGRect(x: 400, y: 300, width: 200, height: 200),
      source: CGRect(x: 0, y: 0, width: 1000, height: 800),
      destination: CGRect(x: -2000, y: 200, width: 2000, height: 1200)
    )
    #expect(result == CGRect(x: -1100, y: 700, width: 200, height: 200))
  }

  @Test func maximizedWindowFollowsDestination() {
    let source = CGRect(x: 0, y: 25, width: 1920, height: 1055)
    let destination = CGRect(x: -1280, y: 100, width: 1280, height: 700)
    #expect(DisplayTransfer.transferredRect(window: source, source: source, destination: destination) == destination)
  }

  @Test func oversizedWindowFitsSmallerDisplay() {
    let destination = CGRect(x: 2000, y: 0, width: 800, height: 600)
    let result = DisplayTransfer.transferredRect(
      window: CGRect(x: 200, y: 100, width: 1200, height: 900),
      source: CGRect(x: 0, y: 0, width: 1800, height: 1200), destination: destination
    )
    #expect(result == destination)
  }

  @Test func screenCoordinatesRoundTrip() {
    let frame = CGRect(x: -1280, y: 1200, width: 800, height: 600)
    let flipped = WindowDisplayMover.flipped(frame, primaryHeight: 1080)
    #expect(flipped.origin == CGPoint(x: -1280, y: -720))
    #expect(WindowDisplayMover.flipped(flipped, primaryHeight: 1080) == frame)
  }

  @Test func spanningWindowUsesLargestIntersection() {
    let screens = [CGRect(x: -1000, y: 0, width: 1000, height: 800),
                   CGRect(x: 0, y: 0, width: 1000, height: 800)]
    #expect(WindowDisplayMover.sourceIndex(window: CGRect(x: -100, y: 100, width: 600, height: 400),
                                          screens: screens) == 1)
    #expect(WindowDisplayMover.sourceIndex(window: .zero, screens: []) == nil)
  }
}
