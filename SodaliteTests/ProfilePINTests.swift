import Foundation
import Testing
@testable import Sodalite

@MainActor
struct ProfilePINTests {

    @Test("A ProfileRef composes the same id the store has always used")
    func refMatchesLegacyComposite() {
        let ref = ProfileRef(serverID: "A", userID: "dad")
        #expect(ref.compositeID == ParentalControlsPreferences.compositeID(serverID: "A", userID: "dad"))
        #expect(ref.id == ref.compositeID)
    }

    @Test("The ref-first store API and the legacy forwarders agree")
    func refAPIMatchesForwarders() {
        let prefs = ParentalControlsPreferences(store: UserDefaults(suiteName: "ProfilePINTests.refAPI")!)
        let ref = ProfileRef(serverID: "A", userID: "mum")
        prefs.setRole(.pinToEnter, for: ref)
        #expect(prefs.role(ref) == .pinToEnter)
        #expect(prefs.role(serverID: "A", userID: "mum") == .pinToEnter)
        prefs.setRole(.pinToLeave, serverID: "A", userID: "mum")
        #expect(prefs.role(ref) == .pinToLeave)
        #expect(prefs.isProtected(ref))
    }
}
