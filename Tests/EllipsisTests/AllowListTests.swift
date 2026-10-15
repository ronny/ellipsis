import Testing
@testable import Ellipsis

struct AllowListTests {
    private func recorded(hidden: Set<String>, allowed: Set<String>) -> AllowList {
        var list = AllowList()
        list.record(hidden: hidden, allowed: allowed)
        return list
    }

    @Test func theFirstApplyIsNeeded() {
        #expect(AllowList().needsApply(hidden: ["a"], allowed: ["b"]))
    }

    @Test func theSameRequestIsSkipped() {
        let list = recorded(hidden: ["a"], allowed: ["b", "c"])
        #expect(!list.needsApply(hidden: ["a"], allowed: ["b", "c"]))
    }

    @Test func anAllowedAppThatQuitIsSkipped() {
        let list = recorded(hidden: ["a"], allowed: ["b", "c"])
        #expect(!list.needsApply(hidden: ["a"], allowed: ["b"]))
    }

    @Test func aNewAppIsApplied() {
        let list = recorded(hidden: ["a"], allowed: ["b"])
        #expect(list.needsApply(hidden: ["a"], allowed: ["b", "c"]))
    }

    /// Hiding the set again shrinks the allow-list. That must not pass as
    /// an app that quit.
    @Test func aChangedHiddenSetIsApplied() {
        let list = recorded(hidden: [], allowed: ["a", "b"])
        #expect(list.needsApply(hidden: ["a"], allowed: ["b"]))
    }

    @Test func aClearedListApplies() {
        var list = recorded(hidden: ["a"], allowed: ["b"])
        list.clear()
        #expect(list.needsApply(hidden: ["a"], allowed: ["b"]))
    }
}
