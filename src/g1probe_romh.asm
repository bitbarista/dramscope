; ===========================================================================
; G1 PROBE -- ROMH half.
;
; An EasyFlash bank is ROML (8 KB) + ROMH (8 KB). In 16K mode ROMH appears at
; $A000; ⚠ IN ULTIMAX IT APPEARS AT $E000-$FFFF, which is why the reset vector
; lives here and not in ROML. It points straight at $8000, because ROML is the
; one window mapped in BOTH modes and so the only safe place to land.
;
; Nothing else is in here. Assembled at $A000; the vectors land at $BFFA-$BFFF,
; which is $FFFA-$FFFF once Ultimax has moved it.
; ===========================================================================
!to "build/g1probe_romh.bin", plain
* = $a000
        !fill $bffa - *, $ff
        !word $8000                     ; NMI
        !word $8000                     ; RESET
        !word $8000                     ; IRQ/BRK
