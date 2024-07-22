//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/include/DLKitC.h#16 $
//
//  Provides state for a symbol table iterator.
//

#if __has_include(<mach-o/dyld.h>)
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/arch.h>
#import <mach-o/getsect.h>
#import <mach-o/nlist.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct nlist_64 nlist_t;
typedef uint64_t sectsize_t;
#define getsectdatafromheader_f getsectdatafromheader_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct nlist nlist_t;
typedef uint32_t sectsize_t;
#define getsectdatafromheader_f getsectdatafromheader
#endif

typedef struct { const void *value; const char *name; } TrieSymbol;
typedef void (^triecb)(const void *value, const char *name);

typedef struct {
    const mach_header_t *header;
    const void *image_end;
    intptr_t file_slide;
    
    nlist_t *symbols;
    uint32_t symbol_count;
    intptr_t address_base;
    const char *strings_base;
    
    const uint8_t *exports_trie;
    uint32_t trie_size;
    TrieSymbol *trie_symbols;
    size_t trie_symbol_count;

    segment_command_t *segments[99];
} symbol_iterator;

#if __cplusplus
extern "C" {
#endif
extern void *self_caller_address(void);
extern void init_symbol_iterator(const mach_header_t *header,
                                 symbol_iterator *state,
                                 bool isFile);

#ifndef DLKit_C
//#import <Foundation/Foundation.h>
@class NSArray, NSString;
extern NSArray/*<NSString *>*/ *trie_stackSymbols();
#endif
extern int trie_dladdr(const void *value, Dl_info *info);
extern void *trie_dlsym(const mach_header_t *image, const char *symbol);
extern const symbol_iterator *trie_iterator(const void *header);
extern void trie_register(const char *path, const mach_header_t *header);
extern const void *exportsLookup(const symbol_iterator *state, const char *symbol);
extern const void *exportsTrieTraverse(const symbol_iterator *state, const uint8_t *p,
                                       const char *buffer, char *bptr, triecb cb);
#endif
#if __cplusplus
}
#endif
