-- Registering a program by path (lua/features/util/tool_paths/init.lua); loaded on first use. PATH
-- gets the shims from init.lua.
return {
  "registered_programs",
  virtual = true,
  cmd = "ToolPath",
  keys = {
    {
      "<leader>uX",
      function()
        require("features.util.tool_paths").pick()
      end,
      desc = "Tool Paths",
    },
  },
  config = function()
    vim.api.nvim_create_user_command("ToolPath", function(args)
      local tp = require("features.util.tool_paths")
      local name, path = args.fargs[1], args.fargs[2]

      if args.bang and name then
        local ok, err = tp.unregister(name)

        vim.notify(ok and (name .. " unregistered") or err, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
      elseif name and path then
        local ok, err = tp.register(name, table.concat(vim.list_slice(args.fargs, 2), " "))

        vim.notify(
          ok and ("%s -> %s"):format(name, (tp.read() or {})[name]) or err,
          ok and vim.log.levels.INFO or vim.log.levels.ERROR
        )
      elseif name then
        tp.prompt(name)
      else
        tp.pick()
      end
    end, {
      bang = true,
      nargs = "*",
      complete = function(_, line)
        local before = line:match("^%S+%s+(.*)$") or ""

        if before:find("%s") then
          return vim.fn.getcompletion(before:match("%S+$") or "", "file")
        end

        return vim.tbl_filter(function(n)
          return vim.startswith(n, before)
        end, require("features.util.tool_paths").names())
      end,
      desc = "Register a program by path: ToolPath [name [path]], ToolPath! name unregisters",
    })
  end,
}
