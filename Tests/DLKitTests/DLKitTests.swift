//
//  DLKitTests.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Tests/DLKitTests/DLKitTests.swift#15 $
//

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
        let testClassSwift = "type metadata for DLKitTests.DLKitTests"
        guard let testImage = DLKit.imageMap["DLKitTests"] else {
            XCTFail("Could not locate test image")
            return
        }
        guard let mangled = testImage.mangle(swift: testClassSwift)?.name,
            mangledTestClassSymbol == String(cString: mangled) else {
            XCTFail("Re-mangling test")
            return
        }
        XCTAssertEqual(DLKit.selfImage, testImage, "Images equal")
        for entry in testImage where entry.value != nil {
            print(entry.name.demangled ??
                String(cString: entry.name), entry.value as Any)
        }
        guard let pointer1 = testImage[[mangledTestClassSymbol]][0] else {
            XCTFail("Symbol lookup fails")
            return
        }
        guard testImage.swiftSymbols(withSuffixes: ["CN"])
            .map({ $0.name.demangled }).contains(testClassSwift) else {
                XCTFail("Symbol filter fails")
                return
        }
        guard let pointer2 = DLKit.allImages[mangledTestClassSymbol] else {
            XCTFail("Global symbol lookup fails")
            return
        }
        XCTAssertEqual(pointer1, pointer2, "Pointers equal")
        guard let info = DLKit.allImages[pointer2] else {
            XCTFail("Reverse lookup fails")
            return
        }
        XCTAssertEqual(info.image, testImage, "Images equal")
        XCTAssertEqual(String(cString: info.name),
                       mangledTestClassSymbol, "Symbol names equal")

//        let sui = DLKit.imageMap["SwiftUI"]!
//        XCTAssert(Array(sui.entries).count < sui.trieSymbols()!.count)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
