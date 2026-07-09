; extends

; Highlight GNU inline-assembly bodies as assembly (kernel C is full of them).
; Each string piece is one asm line, injected independently so multi-line and
; adjacent-literal (concatenated) blocks read cleanly.
((gnu_asm_expression
   assembly_code: (string_literal (string_content) @injection.content))
  (#set! injection.language "asm"))

((gnu_asm_expression
   assembly_code: (concatenated_string (string_literal (string_content) @injection.content)))
  (#set! injection.language "asm"))
