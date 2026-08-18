org 0x0
bits 16

; Define a newline character sequence (CRLF - carriage return + line feed) for printing to the screen
%define ENDL 0x0D, 0x0A


start:
    ; print hello world message
    mov si, msg_hello   ; point si to the string we want to print
    call puts           ; print "Hello, World!" to the screen

.halt:
    cli
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

.loop:
    lodsb              ; loads next character in al from the string pointed to by ds:si and increments si
    or al, al           ; verify if next character is null (end of string is a null character - \0)
    jz .done

    mov ah, 0x0e        ; call BIOS Interrupt 0x10, function 0x0e (TTY) to print character in al to screen
    mov bh, 0x00        ; set page number to 0 (we only have one page)
    int 0x10            ; print character in al to screen (TTY)

    jmp .loop

.done:
    pop ax
    pop si
    ret


msg_hello: db 'Hello, World!', ENDL, 0  ; null-terminated string (end of string is a null character - \0)