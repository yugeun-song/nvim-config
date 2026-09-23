; extends

; Inline asm bodies as assembly. Each string piece is injected on its own so
; concatenated literals still read cleanly.
((gnu_asm_expression
   assembly_code: (string_literal (string_content) @injection.content))
  (#set! injection.language "asm"))

((gnu_asm_expression
   assembly_code: (concatenated_string (string_literal (string_content) @injection.content)))
  (#set! injection.language "asm"))
