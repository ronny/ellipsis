import Foundation
import Testing
@testable import Ellipsis

struct ClickDebounceTests {
    private func accepted(_ times: [TimeInterval]) -> [Bool] {
        var debounce = ClickDebounce()
        return times.map { debounce.accept(at: $0) }
    }

    @Test func theFirstClickPasses() {
        #expect(accepted([10]) == [true])
    }

    @Test func aDuplicateWithinTheWindowIsDropped() {
        #expect(accepted([10, 10.001]) == [true, false])
    }

    @Test func aClickAfterTheWindowPasses() {
        #expect(accepted([10, 10.2]) == [true, true])
    }

    @Test func aDroppedClickDoesNotExtendTheWindow() {
        #expect(accepted([10, 10.08, 10.15]) == [true, false, true])
    }
}
