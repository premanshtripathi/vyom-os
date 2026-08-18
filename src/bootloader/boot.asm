org 0x7C00
bits 16

; Define a newline character sequence (CRLF - carriage return + line feed) for printing to the screen
%define ENDL 0x0D, 0x0A

;
; FAT12 header
;
jmp short start
nop
bdb_oem:                        db 'MSWIN4.1'           ; 8 bytes OEM name
bdb_bytes_per_sector:           dw 512                  ; 2 bytes - number of bytes per sector
bdb_sectors_per_cluster:        db 1                    ; 1 byte - number of sectors per cluster
bdb_reserved_sectors:           dw 1                    ; 2 bytes - number of reserved sectors
bdb_fat_count:                  db 2                    ; 1 byte - number of FATs
bdb_dir_entries_count:          dw 0E0h                 ; 2 bytes - number of root directory entries
bdb_total_sectors:              dw 2880                 ; 2 bytes - total number of sectors on the disk (for a 1.44MB floppy disk, this is 2880 sectors)
bdb_media_descriptor_type:      db 0F0h                 ; 1 byte - media descriptor type (F0 = 3.5" floppy disk)
bdb_sectors_per_fat:            dw 9                    ; 2 bytes - number of sectors per FAT
bdb_sectors_per_track:          dw 18                   ; 2 bytes - number of sectors per track
bdb_heads:                      dw 2                    ; 2 bytes - number of heads
bdb_hidden_sectors:             dd 0                    ; 4 bytes - number of hidden sectors
bdb_large_sector_count:         dd 0                    ; 4 bytes - large sector count (for disks larger than 32MB)

; extended boot record
ebr_drive_number:               db 0                    ; 1 byte - drive number (0x00 = floppy disk, 0x80 = hard disk, useless for floppy disks)
ebr_reserved:                   db 0                    ; 1 byte - reserved (must be 0)
ebr_signature:                  db 29h                  ; 1 byte - extended boot signature (0x29 = indicates that the next three fields are present)
ebr_volume_id:                  db 12h, 34h, 56h, 78h   ; 4 bytes - volume ID (serial number, can be any value)
ebr_volume_label:               db 'VYOM OS    '        ; 11 bytes - volume label (padded with spaces)
ebr_system_id:                  db 'FAT12   '           ; 8 bytes - file system type (padded with spaces)


;
; Code goes here
;
                                                                                                                                            

start:
    ; setup data segments
    mov ax, 0           ; can't writte to ds/es directly, so we use ax as a temporary register
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00      ; stack grows downwards from where we are loaded in memory, so we put it at start of our OS.
                        ; If we put it at the end of our OS, we would overwrite our OS code when we push something to the stack.

    ; Some BIOSes might start us at 07C0:0000 instead of 0000:7C00, make sure we are in the expected location
    push es
    push word .after
    retf

.after:

    ; read something from floppy disk
    ; BIOS should set Dl to drive number
    mov [ebr_drive_number], dl   ; store drive number in extended boot record (we will use it later when we read from disk)


    ; Show loading message
    mov si, msg_loading   ; point si to the string we want to print
    call puts           ; print "Hello, World!" to the screen

    push es
    mov ah, 08h
    int 13h
    jc floppy_error
    pop es

    and cl, 0x3F    ; remove top 2 bits
    xor ch, ch
    mov[bdb_sectors_per_track], cx      ; sector count

    inc dh
    mov [bdb_heads], dh     ; head count

    ; compute LBA of root directory = reserved + fats * sectors_per_fat
    ; note: this can be hardcoded
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx                              ; ax = (fats * sectors_per_fat)
    add ax, [bdb_reserved_sectors]      ; ax = LBA of root directory
    push ax

    ; compute size of root directory = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                           ; ax *= 32
    xor dx, dx                          ; dx = 0
    div word [bdb_bytes_per_sector]     ; number of sectors we need to read

    test dx, dx                         ; if dx != 0, add 1
    jz .root_dir_after
    inc ax                              ; division remainder != 0, add 1
                                        ; this means we have a sector only partially filled with entries

.root_dir_after:

    ; read root directory
    mov cl, al
    pop ax
    mov bx, buffer                      ; es:bx = buffer
    call disk_read

    ; search for the kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11                  ; compare upto 11 characters
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; kernel not found
    jmp kernel_not_found_error


;
; Notes about some instructions
;

; cmpsb = compare string bytes
;       it compares 2 bytes located in memory at addresses ds:si and es:di
;       si and di are -
;             incremented (when direction flag = 0)
;             decre,emted (when direction flag = 1)
;       comparison is performed similarly to the CMP instruction
;             a subtraction is performed, and the flags are set accordingly
;       cmpsw, cmpsd, cmpsq are equivalent for comparing words, double words and quads respectively.

; repe = repeat while equal
;       repeats a string instruction while the operands are equal (zero flag = 1), or until cx reaches 0
;       cx is decremented on each iteration
;       comparison is performed similarly to the CMP instruction
;             a subtraction is performed, and the flags are set accordingly

.found_kernel:
    ; di should have the address to the entry
    mov ax, [di + 26]       ; first logical cluster field (offset 26)
    mov [kernel_cluster], ax

    ; load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read


    ; read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; Read next cluster
    mov ax, [kernel_cluster]
    ; not nice :( we hardcoded the value (offset). We will need to fix this in future.
    add ax, 31                          ; first_cluster = (kernel_cluster - 2) * sectors_per_cluster + start_sector
                                        ; start_sector = reserved + fats + root_directory_size = 1 + 18 + 14 = 33
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]      ; this add will overflow if kernel.bin file is larger than 64 Kilobytes.
                                        ; in which case, the read file will be corrupted as we will be overriting the first part of it.
                                        ; to fix this issue we will need to detect this case and increment the segment.

    ; compute location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                              ; ax = index of entry in FAT, dx = cluster mod 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                     ; read entry from FAT table at index ax

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                      ; end of chain
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; jump to our kernel
    mov dl, [ebr_drive_number]          ; boot device in dl

    mov ax, KERNEL_LOAD_SEGMENT         ; set segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot             ; should never happen



    ; Since we are in 16-bit Real Mode, we cannot access the memory above the 1 MegaByte limit.
    ;
    ;       Lower Memory = 640 KiB RAM
    ;           Usable in Real Mode -
    ;               Real Mode IVT (Interrupt Vector Table)  - 1 KiB
    ;               BDA (BIOS Data Area)                    - 256 bytes
    ;
    ;           Usable Memory -
    ;               Conventional Memory                     - almost 30 KiB
    ;               Your OS BootSector                      - 512 bytes
    ;               Conventional Memory                     - 480.5 KiB
    ;
    ;           Partially used by the EBDA
    ;               EBDA (Extented BDA)                     - 128 KiB
    ;
    ;       Upper Memory = 384 KiB RAM
    ;           Harware Mapped
    ;               Video Display Memory                    - 128 KiB
    ;
    ;           ROM and hardware mapped / Shadow RAM
    ;               Video BIOS                              - 32 KiB
    ;               BIOS Expensions                         - 160 KiB
    ;               Motherboard BIOS                        - 64 KiB
    ;




    cli             ; Disable interrupts so the CPU doesn't wake up
    hlt             ; halt the CPU (we don't want to continue executing random memory after our code)

;
; Error handlers
;

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0           ; BIOS function 0 - wait for key press
    int 16h             ; call BIOS interrupt 16h to wait for key press
    jmp 0xFFFF:0        ; jump to the beginning of the BIOS (should reboot the computer)

.halt:
    cli                 ; disable interrupts, this way CPU cannot get out of the "halt" state)
    hlt


;
; Prints a string to the screen
; Params:
;   - ds:si - points to the string
;
puts:
; save registers we will modify
    push si
    push ax
    ; push bx

.loop:
    lodsb              ; loads next character in al from the string pointed to by ds:si and increments si
    or al, al           ; verify if next character is null (end of string is a null character - \0)
    jz .done

    mov ah, 0x0e        ; call BIOS Interrupt 0x10, function 0x0e (TTY) to print character in al to screen
    mov bh, 0x00        ; set page number to 0 (we only have one page)
    int 0x10            ; print character in al to screen (TTY)

    jmp .loop

.done:
    ; pop bx
    pop ax
    pop si
    ret


;
; Disk Routines
;

;
; converst an LBA to CHS
; Parameters:
;   - ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number (1-63)
;   - cx [bits 6-15]: cylinder number (0-1023)
;   - dh: head number (0-255)
lba_to_chs:

    push ax
    push dx

    xor dx, dx                          ; clear dx (we will use it to store the head number)
                                        ; dx = 0

    div word [bdb_sectors_per_track]    ; divide LBA by sectors per track to get the cylinder and head number
                                        ; ax = LBA / sectors_per_track
                                        ; dx = LBA % sectors_per_track

    inc dx                              ; increment dx to get the sector number (1-63)
                                        ; dx = (LBA % sectors_per_track) + 1

    mov cx, dx                          ; move the sector number to cx (bits 0-5)
                                        ; cx = sector number

    xor dx, dx                          ; clear dx (we will use it to store the head number)
                                        ; dx = 0

    div word [bdb_heads]                ; divide ax by number of heads to get the cylinder number
                                        ; ax = (LBA / sectors_per_track) / heads
                                        ; dx = (LBA / sectors_per_track) % heads

    mov dh, dl                          ; move the head number to dh
                                        ; dh = head number

    mov ch, al                          ; move the cylinder number to ch
                                        ; ch = cylinder number (lower 8 bits)

    shl ah, 6                           ; shift the upper 2 bits of the cylinder number to the left by 6 to store them in bits 6-7 of ch
                                        ; ah = (cylinder number >> 8) & 0x03
    or cl, ah                           ; put upper 2 bits of cylinder in CL
                                        ; cl = (cylinder number & 0xFF) | ((cylinder number >> 8) & 0x03) << 6

    pop ax                              ; Restore original DX into AX instead of DX to protect our calculated DH (Head). AL now holds the original DL (Drive number).
    mov dl, al                          ; Restore the original drive number into DL. Our calculated DH (Head number) remains completely safe and unmodified.
    pop ax                              ; Pop the last item from the stack to restore the original AX (LBA address).

    ret

;
; Reads sectors from a disk into memory
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors to read (up to 128)
;   - es:bx: memoryaddress where to store read data
;
disk_read:

    push ax                         ; save registers we will modify
    push bx
    push cx
    push dx
    push di

    push cx                         ; temporarily save CL (number of sectors to read)
    call lba_to_chs                 ; compute CHS values from the LBA address in ax
    pop ax                          ; AL = number of sectors to read (up to 128)
    mov ah, 02h                     ; BIOS function 02h - read sectors from disk
    mov di, 3                       ; retry count

.retry:
    pusha                           ; save all registers before calling BIOS interrupt 13h (We don't know what BIOS modifies)
    stc                             ; set carry flag to indicate we want to read from the disk (Some BIOSes don't set it automatically)
    int 13h                         ; call BIOS interrupt 13h to read sectors from disk (Carry Flag cleared = success)
    jnc .done
    
    ; read failed, retry
    popa                            ; restore all registers after calling BIOS interrupt 13h
    call disk_reset                 ; reset the disk controller

    dec di                          ; decrement retry count
    test di, di                     ; check if we have retries left
    jnz .retry                      ; if we have retries left, try again

.fail:
    ; all attempts are exhausted
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                         ; restore registers we modified

    ret

;
; Resets disk controller
; Parameters:
;   - dl: drive number
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret


msg_loading:            db      'Loading...', ENDL, 0   ; null-terminated string (end of string is a null character - \0)
msg_read_failed:        db      'Read from disk failed!', ENDL, 0
msg_kernel_not_found:   db      'KERNEL.BIN not found!', ENDL, 0
file_kernel_bin:        db      'KERNEL  BIN'
kernel_cluster:         dw      0

; we used equ here so no memory will be allocated for the constant
; it will be replaced with the values at assembly time
; this is equivalent to the pre-processor directive #define in C (in which the values are replaced with the constant at compile time)
KERNEL_LOAD_SEGMENT:    equ     0x2000
KERNEL_LOAD_OFFSET:     equ     0

times 510-($-$$) db 0
dw 0AA55h

buffer: