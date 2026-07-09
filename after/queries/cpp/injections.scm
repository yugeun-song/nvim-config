; extends

; Highlight GNU inline-assembly bodies as assembly. Kernel headers (*.h) are
; detected as cpp here, and they are full of inline asm, so mirror the c rules.
((gnu_asm_expression
   assembly_code: (string_literal (string_content) @injection.content))
  (#set! injection.language "asm"))

((gnu_asm_expression
   assembly_code: (concatenated_string (string_literal (string_content) @injection.content)))
  (#set! injection.language "asm"))
