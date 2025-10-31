//
//  trie_dladdr.mm
//  DLKit
//
//  Created by John Holdsworth on 08/04/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/trie_dladdr.mm#22 $
//
//  dladdr() able to resolve symbols from "exports trie".
//

#if DEBUG || !DEBUG_ONLY
#if __has_include(<mach-o/dyld.h>)
#import <Foundation/Foundation.h>
#import <os/lock.h>
#import "DLKitC.h"
#include <vector>
#include <string>
#include <map>

static bool operator < (const TrieSymbol &s1, const TrieSymbol &s2) {
    return s1.value < s2.value;
}

template<typename T> static ptrdiff_t equalOrGreater(
                    const std::vector<T> &array, T &value) {
    auto it = upper_bound(array.begin(), array.end(), value);
    return distance(array.begin(), it)-1;
}

class SymbolStore {
    std::vector<TrieSymbol> symbolsByValue;
    std::vector<int> symbolNumbersByName;
public:
    const char *path;
    const void *header;
    symbol_iterator state;
    bool isFile;

    SymbolStore(const char *path, const mach_header_t *header, bool isFile = false) {
        this->path = path;
        this->header = header;
        this->isFile = isFile;
        memset(&state, 0, sizeof state);
    }

    std::vector<TrieSymbol> &trie_populate() {
        if (!symbolsByValue.empty()) return symbolsByValue;
        /// not initialised, add symbols found in "exports trie"
        char *buffer = (char *)malloc(state.trie_size+1);
        __block std::map<const void *,const char *> exists;
        exportsTrieTraverse(&state, state.exports_trie, "", buffer,
                            ^(void *value, const char *name) {
            if (exists[value])
                return;
            TrieSymbol entry = {value, strdup(buffer), -1};
            exists[entry.value] = entry.name;
            symbolsByValue.push_back(entry);
        });
        free(buffer);

        sort(symbolsByValue.begin(), symbolsByValue.end());
        state.trie_symbols = symbolsByValue.data();
        state.trie_symbol_count = symbolsByValue.size();
        legacy_populate();
        return symbolsByValue;
    }

    std::vector<TrieSymbol> &legacy_populate() {
        std::vector<TrieSymbol> legacySyms;

        /// Fold in any other legacy symbols found
        std::map<std::string,int> defined;
        for (int symno=0; symno < state.symbol_count; symno++) {
            if (state.symbols[symno].n_sect == NO_SECT)
                continue; // not definition
            TrieSymbol entry;
            nlist_t &legacy = state.symbols[symno];
            entry.value = (char *)state.address_base + legacy.n_value;
            if (!symbolsByValue.empty())
            if (TrieSymbol *already = triesymWithValue(entry.value, true)) {
                already->symno = symno;
                continue; // from exports trie
            }
            entry.symno = symno;
            entry.name = state.strings_base + legacy.n_un.n_strx;
//            printf("adding %d %x %p %s\n", symno, legacy.n_type, entry.value, entry.name);
            if (!entry.name[0] || defined[entry.name]++)
                continue; // name already recorded
            legacySyms.push_back(entry);
        }

        symbolsByValue.insert(std::end(symbolsByValue),
                              std::begin(legacySyms), std::end(legacySyms));
        sort(symbolsByValue.begin(), symbolsByValue.end());
        state.trie_symbols = symbolsByValue.data();
        state.trie_symbol_count = symbolsByValue.size();

        #if DEBUG
        if (getenv("VERIFY_DLADDR")) {
            int i=0;
            auto &symbols = symbolsByValue;
            for (auto &s : symbols) {
                void *v = trie_dlsym((mach_header_t *)header, s.name);
                if (s.value != v)
                    printf("%ld %d %p %p %s ??%s\n", symbols.size(), i++, s.value, v, strrchr(path, '/'), s.name);
                void *v2 = dlsym(RTLD_DEFAULT, s.name+1);
                if (s.value != v2 && v2)
                    printf("%ld %d %p %p %s\n", symbols.size(), i++, s.value, v2, strrchr(path, '/'));
                Dl_info info;
                trie_dladdr(v, &info);
                if (strcmp(info.dli_sname, s.name+(*s.name == '_')))
                    printf("%s %s %ld %d %p %p %s\n", info.dli_sname, s.name, symbols.size(), i++, s.value, v, strrchr(path, '/'));
            }
        }
        #endif
        return symbolsByValue;
    }

    std::vector<int> &names_populate() {
        if (!symbolNumbersByName.empty()) return symbolNumbersByName;
//        legacy_populate();
        nlist_t *symbols = state.symbols;
        const char *strings = state.strings_base;

        for (auto &s : trie_populate())
            if (s.symno >= 0)
                symbolNumbersByName.push_back(s.symno);

        sort(symbolNumbersByName.begin(), symbolNumbersByName.end(),
             ^(const int &a, const int &b) {
            return strcmp(strings+symbols[a].n_un.n_strx+1,
                          strings+symbols[b].n_un.n_strx+1) < 0;
        });
//        printf("%d %d??\n", this->symbols.size(), names.size());
//        for (int i=0 ; i<names.size(); i++)
//            printf(">> %s\n", strings+symbols[names[i]].n_un.n_strx);
        return symbolNumbersByName;
    }
    
    TrieSymbol *triesymWithValue(void *value, bool exact) {
        TrieSymbol entry = {value};
        auto &symbols = trie_populate();
        ptrdiff_t already = equalOrGreater(symbols, entry);
        if (already<0 || already>=symbols.size() ||
            (exact && symbols[already].value != value))
            return nullptr;
        return &symbols[already];
    }
};

static bool operator < (const SymbolStore &s1, const SymbolStore &s2) {
    return s1.header < s2.header;
}

static os_unfair_lock store_lock = OS_UNFAIR_LOCK_INIT;
static std::vector<SymbolStore> image_store;
static unsigned nFileSymbols;

void trie_register(const char *path, const mach_header_t *header) {
    os_unfair_lock_lock(&store_lock);
    image_store.push_back(SymbolStore(strdup(path), header, true));
    sort(image_store.begin(), image_store.end());
    nFileSymbols++;
    os_unfair_lock_unlock(&store_lock);
}

static SymbolStore *trie_symbols(const void *ptr) {
    os_unfair_lock_lock(&store_lock);

    /// Maintain data for all loaded images
    unsigned alreadyStored = (int)image_store.size()-nFileSymbols;
    if (alreadyStored < _dyld_image_count()) {
        for (unsigned i=alreadyStored; i<_dyld_image_count(); i++) {
            image_store.push_back(SymbolStore(_dyld_get_image_name(i),
                             (mach_header_t *)_dyld_get_image_header(i)));
        }
        sort(image_store.begin(), image_store.end());
    }

    /// Find relevant image
    SymbolStore finder(nullptr, (mach_header_t *)ptr);
    intptr_t imageno = equalOrGreater(image_store, finder);

    os_unfair_lock_unlock(&store_lock);
    if (imageno<0)
        return nullptr;

    SymbolStore &store = image_store[imageno];
    if (!store.state.header)
        init_symbol_iterator((mach_header_t *)store.header, &store.state, store.isFile);
    if (ptr > store.state.image_end)
        return nullptr;
    return &store;
}

const symbol_iterator *trie_iterator(const void *header) {
    if (const SymbolStore *store = trie_symbols(header))
        return &store->state;
    return nullptr;
}

int trie_dladdr(const void *value, Dl_info *info) {
    return trie_dladdr2(value, info, nullptr);
}

int trie_dladdr2(const void *ptr, Dl_info *info, nlist_t **sym) {
    SymbolStore *store = trie_symbols(ptr);
    info->dli_fname = "Image not found";
    info->dli_fbase = nullptr;
    info->dli_sname = "Symbol not found";
    info->dli_saddr = nullptr;
    if (!store)
        return 0;

    info->dli_fbase = const_cast<void *>(store->header);
    info->dli_fname = store->path;

    /// Find first symbol <= ptr
    TrieSymbol *found = store->triesymWithValue(const_cast<void *>(ptr), false);
    if (!found)
        return 0;

    /// Populate Dl_info output struct
    info->dli_saddr = found->value;
    info->dli_sname = found->name;
    if (*info->dli_sname == '_')
        info->dli_sname++;
    if (sym && found->symno >= 0)
        *sym = &store->state.symbols[found->symno];
    return 1;
}

static void *legacy_dlsym(SymbolStore *store, const char *symbol, nlist_t **sym)
{   const auto &names = store->names_populate();
    const char *strings = store->state.strings_base;
    nlist_t *symbols = store->state.symbols;
    for (int i=1; i>=0; i--) {
        int low = 0, high = (int)names.size()-1;
        while (low <= high) {
            int mid = low + (high - low) / 2;
            nlist_t &legacy = symbols[names[mid]];
            int cmp = strcmp(symbol+i, strings+legacy.n_un.n_strx+1);
            if (cmp < 0)
                high = mid - 1;
            else if (cmp > 0)
                low = mid + 1;
            else {
//                printf("FOUND %d %s\n", mid, symbol);
                if (sym)
                    *sym = &legacy;
                return (char *)store->state.address_base + legacy.n_value;
            }
        }
    }
    
    return nullptr;
}

void *slow_dlsym2(const mach_header_t *image, const char *symbol, nlist_t **sym)
{
    return legacy_dlsym(trie_symbols(image), symbol, sym);
}

void *trie_dlsym(const mach_header_t *image, const char *symbol) {
    return trie_dlsym2(image, symbol, nullptr);
}

void *trie_dlsym2(const mach_header_t *image, const char *symbol, nlist_t **sym)
{
    if (SymbolStore *store = trie_symbols(image)) {
        if (void *found = exportsLookup(&store->state, symbol)) {
            if (sym)
                if (TrieSymbol *triesym = store->triesymWithValue(found, true))
                    if (triesym->symno >= 0)
                        *sym = &store->state.symbols[triesym->symno];
            return found;
        }

        return legacy_dlsym(store, symbol, sym);
    }

    return nullptr;
}

NSArray/* <NSString *>*/ *trie_stackSymbols() {
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
#endif
