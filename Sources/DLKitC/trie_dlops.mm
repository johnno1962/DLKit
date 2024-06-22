//
//  trie_dlops.mm
//  DLKit
//
//  Created by John Holdsworth on 08/04/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/trie_dlops.mm#9 $
//
//  Lookup/traversal of symbols in "exports trie" for trie_dladdr().
//
//

#if DEBUG || !DEBUG_ONLY
#if __has_include(<mach-o/dyld.h>)
#import <Foundation/Foundation.h>
#import "DLKitC.h"
#import <vector>

// Derived from https://github.com/apple-oss-distributions/dyld/blob/main/common/MachOFile.cpp#L2768

/*
 * Copyright (c) 2017 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

static uint64_t read_uleb128(const uint8_t*& p, const uint8_t* end, bool& malformed) {
    uint64_t result = 0;
    int         bit = 0;
    malformed = false;
    do {
        if ( p == end ) {
            malformed = true;
            break;
        }
        uint64_t slice = *p & 0x7f;

        if ( bit > 63 ) {
            malformed = true;
            break;
        }
        else {
            result |= (slice << bit);
            bit += 7;
        }
    }
    while (*p++ & 0x80);
    return result;
}

// Lookup a symbol using the "exports trie" (requires the initial "_").
const void *exportsLookup(const symbol_iterator *state, const char *symbol) {
    return exportsTrieTraverse(state, state->exports_trie, symbol, nullptr, (triecb)0);
}

// Dynamic linker lookup code adapted to perform a complete traversal of the "trie".
const void *exportsTrieTraverse(const symbol_iterator *state, const uint8_t *p,
                                const char *symbol, char *bptr, triecb callback) {
    const uint8_t *start = state->exports_trie;
    const uint8_t *end = start + state->trie_size;
    if (!start)
        return nullptr;
    std::vector<uint32_t> visitedNodeOffsets;
    bool malformed = false;
    while ( p < end ) {
        uint64_t terminalSize = *p++;
        if ( terminalSize > 127 ) {
            // except for re-export-with-rename, all terminal sizes fit in one byte
            --p;
            terminalSize = read_uleb128(/*diag, */p, end, malformed);
            if ( malformed )
                return nullptr;
        }
        if ( (callback || *symbol == '\0') && (terminalSize != 0) ) {
            const uint8_t *ptmp = p;
            (void)read_uleb128(ptmp, end, malformed);
            void *value = (char *)state->header + read_uleb128(ptmp, end, malformed);
            if (!callback)
                return value;
            *bptr = 0;
            callback(value, symbol);
        }
        const uint8_t* children = p + terminalSize;
        if ( children > end ) {
            fprintf(stderr, "malformed trie node, terminalSize=0x%llX extends past end of trie\n", terminalSize);
            return nullptr;
        }
        uint8_t childrenRemaining = *children++;
        p = children;
        uint64_t nodeOffset = 0;
        char *sbptr = bptr;
        for (; childrenRemaining > 0; --childrenRemaining) {
            const char* ss = symbol;
            bptr = sbptr;
            bool wrongEdge = false;
            // scan whole edge to get to next edge
            // if edge is longer than target symbol name, don't read past end of symbol name
            char c = *p;
            while ( c != '\0' ) {
                if (callback)
                    *bptr++ = c;
                else if ( !wrongEdge ) {
                    if ( c != *ss )
                        wrongEdge = true;
                    ++ss;
                }
                ++p;
                c = *p;
            }
            if ( wrongEdge ) {
                // advance to next child
                ++p; // skip over zero terminator
                // skip over uleb128 until last byte is found
                while ( (*p & 0x80) != 0 )
                    ++p;
                ++p; // skip over last byte of uleb128
                if ( p > end ) {
                    fprintf(stderr, "malformed trie node, child node extends past end of trie\n");
                    return nullptr;
                }
            }
            else {
                 // the symbol so far matches this edge (child)
                // so advance to the child's node
                ++p;
                nodeOffset = read_uleb128(/*diag,*/ p, end, malformed);
                if ( malformed )
                    return nullptr;
                if ( (nodeOffset == 0) || ( &start[nodeOffset] > end) ) {
                    fprintf(stderr, "malformed trie child, nodeOffset=0x%llX out of range\n", nodeOffset);
                    return nullptr;
                }
                if (!callback) {
                    symbol = ss;
                    break;
                }
                exportsTrieTraverse(state, &state->exports_trie[nodeOffset], symbol, bptr, callback);
                nodeOffset = 0;
            }
        }
        if ( nodeOffset != 0 ) {
            if ( nodeOffset > (uint64_t)(end-start) ) {
                fprintf(stderr, "malformed trie child, nodeOffset=0x%llX out of range\n", nodeOffset);
                return nullptr;
            }
            // check for cycles
            for (uint32_t aVisitedNodeOffset : visitedNodeOffsets) {
                if ( aVisitedNodeOffset == nodeOffset ) {
                    fprintf(stderr, "malformed trie child, cycle to nodeOffset=0x%llX\n", nodeOffset);
                    return nullptr;
                }
            }
            visitedNodeOffsets.push_back((uint32_t)nodeOffset);
            p = &start[nodeOffset];
        }
        else
            p = end;
    }
    return nullptr;
}
#endif
#endif
