-- What an installed Mason package still needs to run, beyond what its installer needed: any one of each list.
-- :checkhealth config warns from it; on Windows, lua/plugins/lsp/mason.lua skips
-- what lacks its runtime.
return {
  source = { npm = { "node" }, gem = { "ruby" }, nuget = { "dotnet" }, composer = { "php" } },
  package = {
    detekt = { "java" },
    ["elixir-ls"] = { "elixir" },
    elp = { "erl" },
    expert = { "elixir" },
    jdtls = { "java" },
    ["js-debug-adapter"] = { "node" },
    ["julia-lsp"] = { "julia" },
    ["kotlin-lsp"] = { "java" },
    ktlint = { "java" },
  },
}
