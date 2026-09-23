; extends

; Same as c/injections.scm: kernel *.h headers are detected as cpp.
((gnu_asm_expression
   assembly_code: (string_literal (string_content) @injection.content))
  (#set! injection.language "asm"))

((gnu_asm_expression
   assembly_code: (concatenated_string (string_literal (string_content) @injection.content)))
  (#set! injection.language "asm"))
