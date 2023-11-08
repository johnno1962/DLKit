//
//  Interposing.swift
//  DLKit
//
//  Created by John Holdsworth on 03/03/2023.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/Interposing.swift#5 $
//

#if canImport(Darwin)
#if SWIFT_PACKAGE
import fishhook
#endif

internal extension UnsafeMutablePointer {
    init<IN>(recast: UnsafeMutablePointer<IN>) {
        self = recast.withMemoryRebound(to: Pointee.self, capacity: 1) {$0}
    }
}

extension ImageSymbols {
    public func rebind(mapping: [String: String],
                       scope: UnsafeMutableRawPointer? = DLKit.RTLD_DEFAULT,
                       warn: Bool = true) -> [DLKit.SymbolName] {
        return rebind(symbols: Array(mapping.keys),
                      values: Array(mapping.values),
                      scope: scope, warn: warn)
    }
    public func rebind(symbols: [String], values: [String],
                       scope: UnsafeMutableRawPointer? = DLKit.RTLD_DEFAULT,
                       warn: Bool = true) -> [DLKit.SymbolName] {
        return rebind(names: symbols.map {$0.withCString {$0}}, values:
                        values.map { if let replacement = dlsym(scope, $0) {
                                return replacement
                            }
                            DLKit.logger("""
                                Unable to find replacement for symbol: \($0)
                                """)
                            return nil
                        }, warn: warn)
    }
    public func rebind(symbols: [String], values: [SymbolValue?],
                       warn: Bool = false) -> [DLKit.SymbolName] {
        let names = symbols.map {$0.withCString {$0}}
        return rebind(names: names, values: values, warn: warn)
    }
    public func rebind(names: [DLKit.SymbolName], values: [SymbolValue?],
                       warn: Bool = false) -> [DLKit.SymbolName] {
        var rebindings: [rebinding] = (0..<names.count).compactMap {
            guard $0 < values.count,
                  let replacement = values[$0] else {
                    DLKit.logger("missing replacement at index \($0) for symbol \(String(cString: names[$0]))")
                return nil
            }
            return rebinding(name: names[$0], replacement: replacement, replaced: nil)
        }
        let replaced = rebind(rebindings: &rebindings)
        // If nothing was replaced remind the user to use -interposable.
        if warn && replaced.count == 0 && names.count != 0 {
            DLKit.logger("No symbols replaced, have you added -Xlinker -interposable to your project's \"Other Linker Flags\"?")
        }
        return replaced
    }
    public func rebind(rebindings: inout [rebinding]) -> [DLKit.SymbolName] {
        var replaced = [DLKit.SymbolName]()
        for image in imageNumbers {
            // Have the rebind operation store the previous value
            // to determine when rebindings have been successful.
            for i in 0..<rebindings.count {
                rebindings[i].replaced =
                    UnsafeMutablePointer(recast: &rebindings[i].replaced)
            }
            rebind_symbols_image(
                UnsafeMutableRawPointer(mutating: image.imageHeader),
                image.imageSlide, &rebindings, rebindings.count)
            for i in 0..<rebindings.count {
                if rebindings[i].replaced !=
                    UnsafeMutablePointer(recast: &rebindings[i].replaced) {
                    replaced.append(rebindings[i].name)
                }
            }
        }
        return replaced
    }
}

// Weird subscripting api.
extension ImageSymbols {
    /// Inverse lookup returning image symbol name and wrapped image for an address.
    public subscript (ptr: SymbolValue)
        -> (name: DLKit.SymbolName, image: ImageSymbols)? {
        var info = Dl_info()
        guard dladdr(ptr, &info) != 0,
              let index = imageNumbers.first(where: {
                  info.dli_fname == $0.imageName }) ??
                imageNumbers.first(where: {
                    strcmp(info.dli_fname, $0.imageName) == 0
                }) else { return nil }
        return (info.dli_sname, ImageSymbols(imageNumber: index))
    }
    /// Loook up an individual symbol by name
    public subscript (name: DLKit.SymbolName) -> SymbolValue? {
        get { return self[[name]][0] }
        set (newValue) { self[[name]] = [newValue] }
    }
    /// Loook up an array of symbols
    public subscript (names: [DLKit.SymbolName]) -> [SymbolValue?] {
        get {
            let handle = imageHandle ??
                dlopen(imageName, RTLD_LAZY)
            imageHandle = handle
            return names.map {dlsym(handle, $0)}
        }
        set (newValue) {
            /// Use fishhook to replace references to the named symbol with new values
            /// Works for symbols references across framework boundaries or inside
            /// an image if it has been linked with -Xlinker -interposable.
            _ = rebind(names: names, values: newValue, warn: true)
        }
    }
    /// Array of Strings version of subscript
    public subscript (symbols: [String]) -> [SymbolValue?] {
        get { return self[symbols.map {$0.withCString {$0}}] }
        set (newValue) {
            _ = rebind(symbols: symbols, values: newValue, warn: true)
        }
    }
    /// Array of Strings version of subscript with lookup
    public subscript (symbols: [String]) -> [String] {
        get { return symbols }
        set (newValue) {
            _ = rebind(symbols: symbols, values: newValue, warn: true)
        }
    }
}
#endif
