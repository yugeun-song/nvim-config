local function detekt_config()
  local root =
    vim.fs.root(0, { "settings.gradle.kts", "settings.gradle", "build.gradle.kts", "build.gradle", "pom.xml", ".git" })
  for _, rel in ipairs(root and { "config/detekt/detekt.yml", "detekt.yml" } or {}) do
    local path = vim.fs.joinpath(root, rel)
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

-- Stock yamllint flags a missing `---` and every line over 80 columns; truthy catches the real YAML 1.1 trap.
local yamllint_fallback =
  "{extends: relaxed, rules: {line-length: disable, truthy: {level: warning, check-keys: false}}}"

-- The same lookup yamllint does, but from the buffer's directory instead of Neovim's cwd.
local function yamllint_config()
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  local path = vim.fs.find({ ".yamllint", ".yamllint.yaml", ".yamllint.yml" }, { upward = true, path = dir })[1]
    or vim.env.YAMLLINT_CONFIG_FILE
  local user =
    vim.fs.joinpath(vim.env.XDG_CONFIG_HOME or vim.fs.joinpath(vim.env.HOME, ".config"), "yamllint", "config")
  if not path and vim.uv.fs_stat(user) then
    path = user
  end
  if path then
    return "-c", path
  end
  return "-d", yamllint_fallback
end

return {
  "mfussenegger/nvim-lint",
  opts = {
    linters_by_ft = {
      kotlin = { "ktlint", "detekt" },
      yaml = { "yamllint" },
    },
    linters = {
      ktlint = {
        -- Without it an INFO line precedes the JSON report on stderr.
        args = { "--log-level=none", "--reporter=json", "--stdin" },
        -- One JVM per run (about 0.7 s): lint on read and save, not on every InsertLeave.
        condition = function()
          return not vim.bo.modified
        end,
      },
      detekt = {
        args = { "--build-upon-default-config", "--config", detekt_config, "--input" },
        -- Stock detekt rules misfire on ordinary code; run only where the project ships a config.
        condition = function()
          return not vim.bo.modified and detekt_config() ~= nil
        end,
      },
      yamllint = {
        args = {
          "--format",
          "parsable",
          function()
            return (yamllint_config())
          end,
          function()
            return select(2, yamllint_config())
          end,
          "-",
        },
      },
    },
  },
}
