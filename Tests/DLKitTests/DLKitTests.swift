import XCTest
// @testable
import DLKit

final class DLKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        print(DLKit.mainImage)
        let mangledTestClassSymbol = "$s10DLKitTestsAACN"
        guard let testImage = DLKit.imageMap["DLKitTests"] else {
            XCTFail("Could not locate test image")
            return
        }
        XCTAssertEqual(DLKit.selfImage, testImage, "Images equal")
        for (name, value) in DLKit.mainImage where value != nil {
            print(name.demangle ?? String(cString: name), value as Any)
        }
        guard let pointer1 = testImage[[mangledTestClassSymbol]][0] else {
            XCTFail("Symbol lookup fails")
            return
        }
        guard let pointer2 = DLKit.allImages[mangledTestClassSymbol] else {
            XCTFail("Global symbol lookup fails")
            return
        }
        XCTAssertEqual(pointer1, pointer2, "Pointers equal")
        guard let (name, image) = DLKit.allImages[pointer2] else {
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
