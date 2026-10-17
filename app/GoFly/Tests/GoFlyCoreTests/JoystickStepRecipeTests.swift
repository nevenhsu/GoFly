import Foundation
import Testing
import GoFlyCore

@Suite
struct JoystickStepRecipeTests {
    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -0.0, -1,
                      JoystickDisplacement.maximumDistanceMeters.nextUp])
    func rejectsUnsafeTargetStepDistance(distance: Double) {
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        #expect(JoystickTargetStep(targetID: UUID(), coordinate: coordinate,
                                  maximumDistanceMeters: distance) == nil)
    }

    @Test(arguments: [Double.leastNonzeroMagnitude, 1,
                      JoystickDisplacement.maximumDistanceMeters.nextDown,
                      JoystickDisplacement.maximumDistanceMeters])
    func acceptsBoundedDistanceWithoutChangingTarget(distance: Double) throws {
        let id = UUID(), coordinate = GeoCoordinate(latitude: -80, longitude: -179)!
        let step = try #require(JoystickTargetStep(targetID: id, coordinate: coordinate,
                                                 maximumDistanceMeters: distance))
        #expect(step.targetID == id)
        #expect(step.coordinate == coordinate)
        #expect(step.maximumDistanceMeters == distance)
    }
}
