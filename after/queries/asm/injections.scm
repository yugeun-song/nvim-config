; extends

; tree-sitter-asm parses every #-line as a line_comment ('#' is a GAS comment
; char), but .S/.s go through cpp, so leading #-directives are C.
; #at-line-start? (lua/plugins/asm.lua) keeps trailing '# ...' comments out.
((line_comment) @injection.content
  (#vim-match? @injection.content "\\v^#\\s*(include_next|include|ifdef|ifndef|elifdef|elifndef|elif|else|endif|define|undef|error|warning|pragma|line|import|if)>")
  (#at-line-start? @injection.content)
  (#set! injection.language "c"))
