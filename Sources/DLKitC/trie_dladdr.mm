//
//  trie_dladdr.mm
//  DLKit
//
//  Created by John Holdsworth on 08/04/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/trie_dladdr.mm#2 $
//
//  dladdr able to resolve symbols from "exports trie".
//

#if __has_include(<mach-o/dyld.h>)
extern "C" {
#import "DLKitC.h"
}
#include <vector>
#include <map>

template<typename T> static ptrdiff_t equalOrGreater(std::vector<T> &array, T &value) {
    auto it = upper_bound(array.begin(), array.end(), value);
    if (it == array.end())
        return -2;
    return distance(array.begin(), it)-1;
}

class ImageSymbols {
public:
    const char *path;
    const void *header;
    symbol_iterator state;
    std::vector<TrieSymbol> symbols;
    bool isFile;

    ImageSymbols(const char *path, const mach_header_t *header, bool isFile = false) {
        this->path = path;
        this->header = header;
        this->isFile = isFile;
        memset(&this->state, 0, sizeof this->state);
    }
    void trie_populate() {
        /// not initialised, add symbols found in "exports trie"
        char *buffer = (char *)malloc(1000000);
        __block std::map<const void *,TrieSymbol> exists;
        exportsTrieTraverse(&state, state.exports_trie, buffer, buffer,
                            ^(const void *value, const char *name) {
            TrieSymbol entry = {value, strdup(name)};
            if (exists.find(entry.value) == exists.end()) {
                exists[entry.value] = entry;
                symbols.push_back(entry);
            }
        });
        free(buffer);
        sort(symbols.begin(), symbols.end());

        /// Fold in any other legacy symbols found
        for (int sno=0; sno < state.symbol_count; sno++) {
            TrieSymbol entry;
            entry.value = (char *)state.address_base + state.symbols[sno].n_value;
            if (exists.find(entry.value) == exists.end()) {
                entry.name = state.strings_base + state.symbols[sno].n_un.n_strx;
                exists[entry.value] = entry;
                symbols.push_back(entry);
            }
        }

        sort(symbols.begin(), symbols.end());
        
        state.trie_symbols = symbols.data();
        state.trie_symbol_count = symbols.size();
    }
};

static bool operator < (const ImageSymbols &s1, const ImageSymbols &s2) {
    return s1.header < s2.header;
}

static bool operator < (const TrieSymbol &s1, const TrieSymbol &s2) {
    return s1.value < s2.value;
}

static std::vector<ImageSymbols> image_store;

void trie_register(const char *path, const mach_header_t *header) {
    image_store.push_back(ImageSymbols(strdup(path), header, true));
    sort(image_store.begin(), image_store.end());
}

static ImageSymbols *trie_symbols(const void *ptr) {
    /// Maintain data for all loaded images
    if (image_store.size() < _dyld_image_count()) {
        for (uint32_t i=(uint32_t)image_store.size(); i<_dyld_image_count(); i++) {
            image_store.push_back(ImageSymbols(_dyld_get_image_name(i),
                                (mach_header_t *)_dyld_get_image_header(i)));
        }
        sort(image_store.begin(), image_store.end());
    }
    
    /// Find relevant image
    ImageSymbols finder(nullptr, (mach_header_t *)ptr);
    intptr_t imageno = equalOrGreater(image_store, finder);
    if (imageno<0)
        return nullptr;
    
    ImageSymbols &store = image_store[imageno];
    if (!store.state.header)
        init_symbol_iterator((mach_header_t *)store.header, &store.state, store.isFile);
    if (ptr > store.state.image_end)
        return nullptr;
    if (!store.symbols.size())
        store.trie_populate();
    return &store;
}

const symbol_iterator *trie_iterator(const void *header) {
    if (ImageSymbols *store = trie_symbols(header))
        return &store->state;
    return nullptr;
}

int trie_dladdr(const void *ptr, Dl_info *info) {
    ImageSymbols *store = trie_symbols(ptr);
    if (!store)
        return 0;

    /// Find actual symbol
    TrieSymbol finder;
    finder.value = ptr;
    ptrdiff_t found = equalOrGreater(store->symbols, finder);
    if (found < 0)
        return 0;

    /// Populate Dl_info output struct
    TrieSymbol &entry = store->symbols[found];
    info->dli_fbase = const_cast<void *>(store->header);
    info->dli_fname = store->path;
    info->dli_saddr = const_cast<void *>(entry.value);
    info->dli_sname = entry.name;
    if (*info->dli_sname == '_')
        info->dli_sname++;
    return 1;
}

NSArray<NSString *> *trie_stackSymbols() {
    NSMutableArray *out = [NSMutableArray new];
    Dl_info info;
    for (NSValue *caller in [NSThread callStackReturnAddresses]) {
        void *pointer = caller.pointerValue;
        if (trie_dladdr(pointer, &info))
            [out addObject:[NSString stringWithUTF8String:info.dli_sname]];
        else
            [out addObject:[NSString stringWithFormat:@"%p", pointer]];
        
    }
    return out;
}
#endif
