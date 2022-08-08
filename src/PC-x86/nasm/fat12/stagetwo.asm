;;;;;;;;;;;;;;;;;
;; stagetwo.asm - second stage boot loader
;; 
;; v 0.01  Alice Osako 3 June 2002
;; v 0.02  Alice Osako 7 Sept 2006
;;         * restarted project, files place under source control.
;;         * Modifications for FAT12 based loader begun.
;;;Version History (note: build versions not shown) 
;;;pre      - June 2002 to February 2004 - early test versions
;;;               * sets segments, loads image from second sector          
;;;v 0.01 - 28 February 2004 Alice Osako 
;;;              * Code base cleaned up
;;;              * Added BPB data for future FAT12 support
;;;              * renamed "Verbum Boot Loader"
;;;v0.02 - 8 May 2004 Alice Osako
;;;              *  moved existing disk handling into separate functions
;;;v0.03 - 7 Sept 2006 Alice Osako
;;;              * resumed work on project. Placed source files under
;;;                version control (SVN)
;;;v0.04 - 18 April 2016 - restarting project, set up on Github
;;;v0.05 - 16 August 2017 - restructuring project, working on FAT12
;;;              support and better documentation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%include "bios.inc"
%include "consts.inc"
%include "macros.inc"
%include "fat-12.inc"
%include "stage2_parameters.inc"
%include "gdt.inc"
%include "tss.inc"


stage2_base       equ 0x0000            ; the segment:offset to load 
stage2_offset     equ stage2_buffer     ; the second stage into

struc High_Mem_Map
    .base   resq 1
    .length resq 1
    .type   resd 1
    .ext    resd 1
endstruc

mmap_size         equ 20
ext_mmap_size     equ mmap_size + 4

SMAP_Text         equ 0x0534D4150


bits 16
org stage2_offset
section .text

entry:
        write success
        mov ax, stage2_base
        mov gs, ax
        mov ax, stage2_offset
        call print_hex_seg_offset
        write newline

A20_enable:
        write A20_gate_status
        lea di, [bp + stg2_parameters.boot_sig]
        call test_A20
        je .A20_on

    .A20_off:
        write off

    .A20_bios_attempt:
;;; parts of this code based on examples given in the 
;;; A20 page of the OSDev wiki (https://wiki.osdev.org/A20_Line)
        write A20_gate_trying_bios
        mov ax, A20_supported  
        int A20BIOS
        jb .a20_no_bios_support
        cmp ah, 0
        jnz .a20_no_bios_support 
 
        mov ax, A20_status
        int A20BIOS
        jb .a20_no_bios_support     ; couldn't get status
        cmp ah, 0
        jnz .a20_no_bios_support    ; couldn't get status
 
        cmp al, 1
        jz .A20_on                   ; A20 is already activated
 
        mov ax, A20_activate
        int A20BIOS 
        jb .a20_no_bios_support     ; couldn't activate the gate
        cmp ah, 0
        jz .A20_on                   ; couldn't activate the gate
        
    .a20_no_bios_support:
        call test_A20
        je .A20_on

    .a20_failed:
        write no_A20_Gate
        jmp halted

    .A20_on:
        write newline
        write on


;; Attempt to get the full physical memory map for the system
;; this should be done before the move to protected mode
get_mem_maps:
        write low_mem
        int LMBIOS
        mov si, print_buffer
        call print_decimal_word
        write kbytes
        push di
        push bp
        mov di, mem_map_buffer
        call get_hi_memory_map
        mov di, mem_map_buffer
        call print_hi_mem_map
        pop bp
        pop di

        cli

Load_GDT:
        call setGdt_rm


; switch to 32-bit protected mode
promote_pm:
        mov eax, cr0 
        or al, 1       ; set PE (Protection Enable) bit in CR0 (Control Register 0)
        mov cr0, eax

        ; Perform far jump to selector 08h (offset into GDT, pointing at a 32bit PM code segment descriptor) 
        ; to load CS with proper PM32 descriptor)
        jmp system_code_selector:PModeMain


%line 0 pmode.asm
bits 32
PModeMain:
        ; set the segment selectors
        mov ax, system_data_selector
        mov ds, ax
        mov ss, ax
        mov es, ax
        mov fs, ax
        mov gs, ax
        mov esp, 0x90000

        ; clear the video screen
        mov ecx, (80 * 25 * 2)
        mov al, 0
        mov edi, 0x000b8000
        cld
    rep stosb


        mov edi, 0x000b8000
        mov [edi], byte 'K'
        inc edi
        mov [edi], byte '1'
        inc edi
        mov [edi], byte 'e'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'r'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'n'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'e'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'l'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte ' '
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 's'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 't'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'a'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'r'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 't'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'e'
        inc edi
        mov [edi], byte 1
        inc edi
        mov [edi], byte 'd'
        inc edi
        mov [edi], byte 1


;;; halt the CPU
halted:
    .halted_loop:
        hlt
        jmp short .halted_loop


%line 0 a20.asm

bits 16
;;; test_A20 - check to see if the A20 line is enabled
;;; Inputs:
;;;       SI - effective address to test
;;;       DS - data segment of the tested address
;;; Outputs:
;;;       Zero flag - set = A20 on, clear = A20 off
test_A20:
        push ax
        push bx
        push cx
        push dx
        push es

        mov cx, 2
    .test_loop:
        mov ax, 0xFFFF
        mov es, ax
        mov di, si
        add di, 0x10            ; 16 byte difference due to segment spacing
        mov bx, word [ds:si]
        mov dx, word [es:di]
        cmp bx, dx
        mov [ds:si], word 0xDEAD
        mov [es:di], word 0xBEEF
        loopne .test_loop
    .cleanup:
        pop es
        pop dx
        pop cx
        pop bx
        pop ax
        ret


%line 0 hi_mem.asm

get_hi_memory_map:
; use the INT 0x15, eax= 0xE820 BIOS function to get a memory map
; note: initially di is 0, be sure to set it to a value so that the BIOS code will not be overwritten. 
;       The consequence of overwriting the BIOS code will lead to problems like getting stuck in `int 0x15`
; inputs: es:di -> destination buffer for 24 byte entries
; outputs: bp = entry count, trashes all registers except esi
; based on code from the OSDev.org wiki (https://wiki.osdev.org/Detecting_Memory_(x86)#Getting_an_E820_Memory_Map)
        zero(bp)                ; use BP to hold count of the entries
        zero(ebx)               ; ebx must be 0 to start
        mov di, mem_map_buffer  ; set the offset for the BIOS to write the list to
        mov eax, stage2_base    
        mov es, eax             ; set the base for the BIOS to write to

    .mem_map_init:
        mov edx, SMAP_Text	; Place "SMAP" into edx for later comparison on eax
        mov [es:di + mmap_size], dword 1 ; force a valid ACPI 3.X entry
        mov ecx, ext_mmap_size
        mov eax, mem_map
        int HMBIOS
        jc short .failed        ; carry set on first call means "unsupported function"
        mov edx, SMAP_Text	; Some BIOSes apparently trash this register?
        cmp eax, edx		; on success, eax must have been reset to "SMAP"
        jne short .failed
        test ebx, ebx		; ebx = 0 implies list is only 1 entry long (worthless)
        je short .failed
        jmp short .jmpin   

    .loop:
        mov [es:di + mmap_size], dword 1 ; force a valid ACPI 3.X entry
        mov ecx, ext_mmap_size
        mov eax, mem_map
        int HMBIOS
        jc short .finish        ; carry set means "end of list already reached"
        mov edx, SMAP_Text	; repair potentially trashed register
    .jmpin:
        jcxz .skip_entry	; skip any 0 length entries
        cmp cl, mmap_size	; got a 24 byte ACPI 3.X response?
        jbe short .no_text
        test byte [es:di + mmap_size], 1	; if so: is the "ignore this data" bit clear?
        je short .skip_entry
    .no_text:
        mov ecx, [es:di + High_Mem_Map.length]	; get lower uint32_t of memory region length
        or ecx, [es:di + High_Mem_Map.length + 4] ; "or" it with upper uint32_t to test for zero
        jz .skip_entry	        ; if length uint64_t is 0, skip entry
        inc bp			; got a good entry: ++count, move to next storage spot
        add di, ext_mmap_size
    .skip_entry:
        test ebx, ebx		; if ebx resets to 0, list is complete
        jne short .loop

    .finish:
        mov [mmap_entries], bp	; store the entry count
        clc			; there is "jc" on end of list to this point, so the carry must be cleared
        ret

    .failed:
        stc
        ret

%line 0 hi_mem_2.asm
;;; print_hi_mem_map - prints the memory table
;;; Inputs:
;;;       BP   = the number of entries found
;;;       [DI] = the memory map table
;;; Outputs:
;;;       screen
;;; Clobbers:
;;;       AX, CX, SI
print_hi_mem_map:
        jc .failed              ; if the interrupt isn't supported, fail
        cmp bp, 0
        jz .failed              ; if there are no valid entries, fail
        write mmap_prologue
        mov si, print_buffer    ; print the description of the section...
        push ax
        mov ax, bp
        call print_decimal_word ; including the number of entries found...
        write mmap_entries_label
        pop ax
        write mmap_headers      ;and the headers for the columns.
        write mmap_separator
        mov cx, bp            ; set the # of entries as the loop index

        push si
        push di
        
    .print_loop:
        ; write each of the structure fields with a spacer separating them
        push di
        add di, High_Mem_Map.base ; print the base value
        call print_hex_qword
        write mmap_space
        pop di
        push di
        add di, High_Mem_Map.length ; print the length value
        call print_hex_qword
        write mmap_space
        pop di
        push di
        add di, High_Mem_Map.type ; use the type value as an index into the array of strings
        mov si, mmap_types        ; get the array head
        mov ax, [di]              ; get the offset
        mov bl, mmap_types_size   ; multiply the offset by the size of the array elements
        imul bl
        add si, ax              ; print the appropriate array element
        call print_str
        write lparen            ; print the actual value of the type in parentheses
        mov si, print_buffer    
        mov ax, [di]
        call print_decimal_word
        write rparen
        write mmap_space
        pop di
        push di
        add di, High_Mem_Map.ext ; print the extended ACPI 3.x value 
        mov ax, [di]
        mov si, print_buffer
        call print_decimal_word
        write newline
        pop di
        add di, ext_mmap_size ; advance to the next entry
        loop .print_loop
        
    .finish:
        pop di
        pop si
        ret
        
    .failed:
        write mmap_failed
        ret



%line 0 aux.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;Auxilliary functions      
%include "simple_text_print_code.inc"
%include "print_hex_code.inc"
%include "print_hex_long_code.inc"
%include "print_decimal_code.inc"
%include "simple_disk_handling_code.inc"
%include "read_fat_code.inc"
%include "read_root_dir_code.inc"
%include "dir_entry_seek_code.inc"
%include "fat_to_file_code.inc"

;;;;;;;;;;;;;;;;;;;;;;;;;
;; data
;;         [section .data]
null                         dd 00000000
lparen                       db '(', NULL
rparen                       db ')', NULL
print_buffer                 resb 32
newline                      db CR, LF, NULL
exit                         db 'System Halted.', CR, LF, NULL
success                      db 'Control successfully transferred to second stage at ', NULL
A20_gate_status              db 'A20 Line Status: ', NULL
on                           db 'on.', CR, LF, NULL
off                          db 'off.', CR, LF, NULL
A20_gate_trying_bios         db 'Attempting to activate A20 line with BIOS... ', NULL
no_A20_Gate                  db 'A20 gate not found.', CR, LF, NULL
mmap_failed                  db 'Could not retrieve memory map.', NULL
low_mem                      db 'Low memory total: ', NULL
kbytes                       db ' KiB', CR, LF, NULL
mmap_prologue                db 'High memory map (', NULL
mmap_entries_label           db ' entries):', CR,LF,NULL
mmap_headers                 db 'Base Address       | Length             | Type                  | Ext.', CR, LF, NULL
mmap_separator               db '----------------------------------------------------------------------------', CR,LF, NULL
mmap_space                   db '     ', NULL

mmap_entries                 resd 1

mmap_types                   db '                ', NULL
                             db 'Free Memory     ', NULL
                             db 'Reserved Memory ', NULL
                             db 'ACPI Reclaimable', NULL
                             db 'ACPI NVS        ', NULL
                             db 'Bad Memory      ', NULL
mmap_types_size              equ 17


mem_map_buffer               resb 16 * ext_mmap_size


%include "init_gdt.inc"
%include "init_tss.inc"
;%include "init_idt.inc"

