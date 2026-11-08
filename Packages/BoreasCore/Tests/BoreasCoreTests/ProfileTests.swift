import Testing
import Foundation
@testable import BoreasCore

let silent = Curve(points: [.init(celsius: 55, fraction: 0), .init(celsius: 95, fraction: 1)])

@Test func belowFirstPoint() { #expect(silent.fraction(at: 30) == 0) }
@Test func interpolates() { #expect(silent.fraction(at: 75) == 0.5) }
@Test func aboveLastPoint() { #expect(silent.fraction(at: 100) == 1) }
@Test func multiSegment() {
    let c = Curve(points: [.init(celsius: 40, fraction: 0.15), .init(celsius: 60, fraction: 0.5), .init(celsius: 80, fraction: 1)])
    #expect(abs(c.fraction(at: 50) - 0.325) < 1e-9)
}
@Test func builtIns() {
    let p = BuiltInProfiles.all()
    #expect(p.map(\.builtIn) == [.automatic, .silent, .performance])
    #expect(p[0].rules.isEmpty)
    #expect(p[1].rules.map(\.source) == [.group(.cpu)])
    #expect(p[1].rules[0].curve == silent)
    #expect(Set(p[2].rules.map(\.source)) == [.group(.cpu), .group(.gpu)])
    #expect(p[2].rules.allSatisfy { $0.curve.points.map(\.celsius) == [40, 60, 80] && $0.curve.points.map(\.fraction) == [0.15, 0.5, 1.0] })
}
@Test func builtInsDeterministic() {
    #expect(BuiltInProfiles.all() == BuiltInProfiles.all())
    #expect(BuiltInProfiles.all().map(\.id) == [BuiltInProfiles.automaticID, BuiltInProfiles.silentID, BuiltInProfiles.performanceID])
    #expect(BuiltInProfiles.all().map(\.name) == ["Automatic", "Silent", "Performance"])
}
@Test func codableRoundTrip() throws {
    let p = BuiltInProfiles.all()[2]
    #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)) == p)
}
@Test func sensorRefRoundTrip() throws {
    let r = Rule(id: UUID(), source: .sensor(SensorID("smc:TCMb")), curve: silent)
    #expect(try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(r)) == r)
    for ref in [SensorSourceRef.sensor(SensorID("hid:PMU tdie1")), .group(.gpu)] {
        #expect(try JSONDecoder().decode(SensorSourceRef.self, from: JSONEncoder().encode(ref)) == ref)
    }
}
@Test func sensorRefJSONShape() throws {
    func json(_ ref: SensorSourceRef) throws -> [String: String]? {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(ref)) as? [String: String]
    }
    #expect(try json(.group(.cpu)) == ["kind": "group", "value": "cpu"])
    #expect(try json(.sensor(SensorID("smc:TC0P"))) == ["kind": "sensor", "value": "smc:TC0P"])
    let decoded = try JSONDecoder().decode(SensorSourceRef.self, from: Data(#"{"kind":"group","value":"gpu"}"#.utf8))
    #expect(decoded == .group(.gpu))
}
@Test func sensorRefRejectsUnknownShapes() {
    for bad in [#"{"kind":"group","value":"toaster"}"#, #"{"kind":"blob","value":"x"}"#, #"{"group":{"_0":"cpu"}}"#] {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SensorSourceRef.self, from: Data(bad.utf8)) }
    }
}
@Test func behaviorMissingKeysDecode() throws {
    let b = try JSONDecoder().decode(ProfileBehavior.self, from: Data(#"{"hysteresisC":5}"#.utf8))
    #expect(b == ProfileBehavior(smoothing: true, hysteresisC: 5, releaseToAppleBelowMin: false))
    #expect(try JSONDecoder().decode(ProfileBehavior.self, from: Data("{}".utf8)) == ProfileBehavior())
}
@Test func malformedCurves() {
    #expect(Curve(points: []).fraction(at: 50) == 0)
    #expect(Curve(points: [.init(celsius: 50, fraction: 0.4)]).fraction(at: 10) == 0.4)
    #expect(silent.fraction(at: .nan) == 0)
    let unsorted = Curve(points: [.init(celsius: 95, fraction: 1), .init(celsius: 55, fraction: 0)])
    #expect(unsorted.fraction(at: 75) == 0.5)
    #expect(Curve(points: [.init(celsius: 0, fraction: -1), .init(celsius: 10, fraction: 2)]).fraction(at: 5) == 0.5)
    #expect(Curve(points: [.init(celsius: 0, fraction: 5)]).fraction(at: 5) == 1)
    let dup = Curve(points: [.init(celsius: 50, fraction: 0), .init(celsius: 50, fraction: 1)])
    #expect(dup.fraction(at: 50).isFinite)
}
