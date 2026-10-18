import Testing
@testable import TouchGrassCore

@Test func appGroupIdentifierMatchesEntitlements() {
    #expect(AppGroup.identifier == "group.pear.TouchGrass")
}
