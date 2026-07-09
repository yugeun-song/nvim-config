; extends

; tree-sitter-asm treats every #-line as a (line_comment) because '#' is a GAS
; line-comment char. But .S/.s files are run through cpp first, so #-directives
; are real C preprocessor syntax. Inject the C grammar into directive lines only.
;
; #at-line-start? (registered in lua/plugins/asm.lua) keeps this to line-leading
; '#' directives, so trailing '# ...' asm comments and /* */ blocks stay comments.
((line_comment) @injection.content
  (#vim-match? @injection.content "\\v^#\\s*(include_next|include|ifdef|ifndef|elifdef|elifndef|elif|else|endif|define|undef|error|warning|pragma|line|import|if)>")
  (#at-line-start? @injection.content)
  (#set! injection.language "c"))
