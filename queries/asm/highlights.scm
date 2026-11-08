(block_comment) @comment @spell

; The directive list must match after/queries/asm/injections.scm; "^#%d" must match lua/features/languages/assembly/syntax_highlighting.lua.
((line_comment) @comment @spell
  (#not-vim-match? @comment "\\v^#\\s*(include_next|include|ifdef|ifndef|elifdef|elifndef|elif|else|endif|define|undef|error|warning|pragma|line|import|if)>")
  (#not-lua-match? @comment "^#%d"))

((line_comment) @comment @spell
  (#not-at-line-start? @comment)
  (#not-lua-match? @comment "^#%d"))

(string) @string
