//
//  DLKit.c
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKitC/DLKitC.c#19 $
//
//  Provides state for a symbol table iterator.
//

#if DEBUG || !DEBUG_ONLY
#if __has_include(<mach-o/dyld.h>)
#define DLKit_C
#include "DLKitC.h"
#include <string.h>

// Derived from: https://stackoverflow.com/questions/20481058/find-pathname-from-dlopen-handle-on-osx
// Imagine trying to write this in Swift. Would it be at all clearer??

void init_symbol_iterator(const mach_header_t *header,
                          symbol_iterator *state,
                          bool isFile) {
    state->header = header;
    segment_command_t *seg_text = NULL;
    segment_command_t *seg_linkedit = NULL;
    struct symtab_command *symtab = NULL;
    struct load_command *cmd =
        (struct load_command *)((intptr_t)header + sizeof(mach_header_t)), *cmd0 = cmd;
    uint64_t textUnslidVMAddr = 0;
    uint64_t linkeditUnslidVMAddr = 0;
    uint64_t linkeditFileOffset = 0;
    for (uint32_t i = 0, segno = 0; i < header->ncmds; i++,
         cmd = (struct load_command *)((intptr_t)cmd + cmd->cmdsize)) {
        switch(cmd->cmd) {
            case LC_SEGMENT:
            case LC_SEGMENT_64: {
                segment_command_t *segment = (segment_command_t *)cmd;
                state->image_end = (char *)header + segment->fileoff + segment->filesize;
                if (segno < sizeof state->segments / sizeof state->segments[0])
                    state->segments[segno++] = segment;
                if (!strcmp(((segment_command_t *)cmd)->segname, SEG_TEXT)) {
                    seg_text = (segment_command_t *)cmd;
                    textUnslidVMAddr = seg_text->vmaddr;
                }
                else if (!strcmp(((segment_command_t *)cmd)->segname, SEG_LINKEDIT)) {
                    seg_linkedit = (segment_command_t *)cmd;
                    linkeditUnslidVMAddr = seg_linkedit->vmaddr;
                    linkeditFileOffset   = seg_linkedit->fileoff;
                }
                break;
            }

            case LC_SYMTAB: {
                symtab = (struct symtab_command *)cmd;
                state->symbol_count = symtab->nsyms;
                state->file_slide = isFile ? 0 : ((intptr_t)seg_linkedit->vmaddr -
                    (intptr_t)seg_text->vmaddr) - seg_linkedit->fileoff;
                state->symbols = (nlist_t *)((intptr_t)header +
                                             (symtab->symoff + state->file_slide));
                state->strings_base = (const char *)header +
                                           (symtab->stroff + state->file_slide);
                if (seg_text)
                    state->address_base = (intptr_t)header - seg_text->vmaddr;
            }
        }
    }

    cmd = cmd0;
    uint32_t fileOffset = ~0U;
    for (uint32_t i = 0; i < header->ncmds; i++,
         cmd = (struct load_command *)((intptr_t)cmd + cmd->cmdsize)) {
        switch(cmd->cmd) {
            case LC_DYLD_INFO:
            case LC_DYLD_INFO_ONLY: {
                const struct dyld_info_command *dyldInfo =
                    (const struct dyld_info_command*)cmd;
                fileOffset = dyldInfo->export_off;
                state->trie_size = dyldInfo->export_size;
                break;
            }
            case LC_DYLD_EXPORTS_TRIE: {
                const struct linkedit_data_command* linkeditCmd =
                    (const struct linkedit_data_command*)cmd;
                fileOffset = linkeditCmd->dataoff;
                state->trie_size = linkeditCmd->datasize;
                break;
            }
        }
    }
        
    if (fileOffset != ~0U)
        state->exports_trie = (uint8_t *)header + (uint32_t)(isFile ? fileOffset :
            (fileOffset - linkeditFileOffset) + (linkeditUnslidVMAddr - textUnslidVMAddr));
}

void *self_caller_address(void) {
    return __builtin_return_address(1);
}
#endif
#endif
