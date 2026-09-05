import XCTest
@testable import SimRecipes

final class SimRecipesTests: XCTestCase {
    func testRootTabsExposeCoreProductSections() {
        XCTAssertEqual(
            AppTab.allCases,
            [.explore, .library, .profile]
        )
    }

    func testOnlyUSBPTPCameraWithX20ModelNameIsCandidate() {
        let camera = CameraDescriptor(
            id: "camera-1",
            name: "FUJIFILM X-S20",
            productKind: "Camera",
            serialNumber: "serial-1",
            transportType: "USB",
            usbVendorID: 1,
            usbProductID: 2,
            supportsPTP: true
        )

        XCTAssertTrue(camera.isX20Candidate)
    }

    func testNameAloneDoesNotQualifyCameraCandidate() {
        let camera = CameraDescriptor(
            id: "camera-1",
            name: "X-S20",
            productKind: "Camera",
            serialNumber: nil,
            transportType: "USB",
            usbVendorID: 0,
            usbProductID: 0,
            supportsPTP: true
        )

        XCTAssertFalse(camera.isX20Candidate)
    }

    func testGetDeviceInfoCommandIsReadOnlyPTPCommand() {
        XCTAssertEqual(
            Array(PTPCommand.getDeviceInfo(transactionID: 1).encoded),
            [12, 0, 0, 0, 1, 0, 1, 16, 1, 0, 0, 0]
        )
    }

    func testPTPResponseHeaderRejectsMalformedResponses() {
        XCTAssertNil(PTPResponseHeader(data: Data(repeating: 0, count: 11)))
        XCTAssertNil(PTPResponseHeader(data: Data(repeating: 0, count: 12)))
    }

    func testPTPResponseHeaderParsesSuccessfulResponse() {
        let response = Data([12, 0, 0, 0, 3, 0, 1, 32, 1, 0, 0, 0])

        XCTAssertEqual(
            PTPResponseHeader(data: response),
            PTPResponseHeader(
                length: 12,
                type: 3,
                responseCode: PTPResponseHeader.successResponseCode,
                transactionID: 1
            )
        )
    }
}
