import XCTest
@testable import SimRecipes

final class SimRecipesTests: XCTestCase {
    func testRootTabsExposeCoreProductSections() {
        XCTAssertEqual(
            AppTab.allCases,
            [.explore, .library, .profile]
        )
    }
}
