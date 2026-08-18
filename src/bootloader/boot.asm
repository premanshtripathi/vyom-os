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
ebr_volume_label:               db 'MYOS       '        ; 11 bytes - volume label (padded with spaces)
ebr_system_id:                  db 'FAT12   '           ; 8 bytes - file system type (padded with spaces)


;
; Code goes here
;
                                                                                                                                                               
; Tell the CPU to jump over our functions and start executing at 'main'
start:
    jmp main


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

main:
    ; setup data segments
    mov ax, 0           ; can't writte to ds/es directly, so we use ax as a temporary register
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00      ; stack grows downwards from where we are loaded in memory, so we put it at start of our OS.
                        ; If we put it at the end of our OS, we would overwrite our OS code when we push something to the stack.

    ; read something from floppy disk
    ; BIOS should set Dl to drive number
    mov [ebr_drive_number], dl   ; store drive number in extended boot record (we will use it later when we read from disk)
    mov ax, 1           ; LBA = 1, second sector from disk
    mov cl, 1           ; 1 sector to read
    mov bx, 0x7E00      ; data should be after the bootloader
    call disk_read      ; read 1 sector from disk into memory at 0x7E00

    mov si, msg_hello   ; point si to the string we want to print
    call puts           ; print "Hello, World!" to the screen

    cli             ; Disable interrupts so the CPU doesn't wake up
    hlt             ; halt the CPU (we don't want to continue executing random memory after our code)

;
; Error handlers
;

floppy_error:
    mov si, msg_read_failed
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

msg_hello:              db 'Hello, World!', ENDL, 0 ; null-terminated string (end of string is a null character - \0)
msg_loading:              db 'Loading...', ENDL, 0
msg_read_failed:        db 'Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h