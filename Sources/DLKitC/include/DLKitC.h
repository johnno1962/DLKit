//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/include/DLKitC.h#10 $
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

struct symbol_iterator {
    int next_symbol;
    int symbol_count;
    nlist_t *symbols;
    const char *strings_base;
    intptr_t address_base;
};

extern void init_symbol_iterator(const mach_header_t *header,
                                 struct symbol_iterator *state,
                                 bool isFile);

extern void *self_caller_address(void);
#endif
