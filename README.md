# DLKit

### A subscript oriented interface to the symbol tables maintained by the dynamic linker.

DLKit is intended to be a "Swifty" encapsulation of the dynamic linker APIs gleaned from
assorted manual pages and system headers. Loaded images (the main executable
or frameworks) are wrapped in the class `ImageSymbols` which you can use to lookup
symbols or find the symbol at an address less than or equal to a pointer and it's
wrapped image. ImageSymbols instances can also be iterated over in a loop
to find all symbol definitions in that image. Think of them as representing
the image/object file as bi-directional dictionaries.

A couple of `ImageSymbols` subclasses represent groups of images such as
`DLKit.allImages` for all images loaded in an application or `DLKit.appImages`
for this list of images filtered to include only those in the app bundle.

To look up a symbol use the allImages pseudo image:
```
if let pointer = DLKit.allImages["main"] {
```

Or you can find the symbol and wrapped image for an address:
```
if let (name, image) = DLKit.allImages[pointer] else {
```

There is a typealias of `UnsafePointer<CChar>` to `ImageSymbols.SymbolName` 
and an extension on this typealias to `"demangle"` Swift symbols to
the Swift language representation of the symbol. There is also a method 
`mangle` on an image which can "re-mangle" this representation to a
symbol name provided the symbol is defined or referred to in the image.
```
let swift = name.demangled
let name = image.mangle(swift: swift)
```

The subscript operators are settable and you can also "rebind" or "interpose"
a symbol in your application by assigning it to point to a new implementation:
```
DLKit.appImages["function_name"] = new_implementation
```

This "rebinding" works across framework boundaries or inside an application if it has 
been linked with "Other Linker Flags" -Xlinker -interposable and uses facebook's
[fishhook](https://github.com/facebook/fishhook) for rebinding indirect symbols.

$Date: 2024/04/03 $
