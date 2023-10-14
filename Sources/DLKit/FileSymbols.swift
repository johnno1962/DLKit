//
//  FileSymbols.swift
//  DLKit
//
//  Created by John Holdsworth on 14/10/2023.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/FileSymbols.swift#3 $
//

import Foundation
#if SWIFT_PACKAGE
import DLKitC
#endif

open class FileSymbols: ImageSymbols {

    /// Fake imageNumber for files
    public static var fileNumber: ImageNumber = 1_000_000
    /// Record of paths to images read in rather than loaded
    public static var filePaths = [ImageNumber: String]()

    public let data: NSMutableData

    override open var imageHeader: UnsafePointer<mach_header_t> {
        return data.bytes.assumingMemoryBound(to: mach_header_t.self)
    }
    override open var imageList: [ImageSymbols] {
        return [self]
    }

    public init?(path: String, typeMask: Int32 = ImageSymbols.mask) {
        guard let data = NSMutableData(contentsOfFile: path) else { return nil }
        self.data = data
        super.init(imageNumber: Self.fileNumber, typeMask: typeMask)
        guard imageHeader.pointee.magic == MH_MAGIC_64 else { return nil }
        Self.filePaths[Self.fileNumber] = path
        Self.fileNumber += 1
    }

    open func save() -> Bool {
        return data.write(toFile: imagePath, atomically: true)
    }
}
