import XCTest
// @testable
import DLKit

final class DLKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        let mangledTestClassSymbol = "$s10DLKitTestsAACN"
        guard let testImage = DLKit.imageMap["DLKitTests"] else {
            XCTFail("Could not locate test image")
            return
        }
        for (name, value) in testImage where value != nil {
            print(name.demangle ?? String(cString: name), value as Any)
        }
        guard let _ = testImage[mangledTestClassSymbol] else {
            XCTFail("Symbol lookup fails")
            return
        }
        guard let pointer = DLKit.allImages[mangledTestClassSymbol] else {
            XCTFail("Global symbol lookup fails")
            return
        }
        guard let (name, image) = DLKit.allImages[pointer] else {
            XCTFail("Reverse lookup fails")
            return
        }
        XCTAssertEqual(image, testImage, "Images equal")
        XCTAssertEqual(String(cString: name),
                       mangledTestClassSymbol, "Symbol names equal")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
