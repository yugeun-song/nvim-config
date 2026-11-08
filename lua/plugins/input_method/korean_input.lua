return {
  "korean_input",
  virtual = true,
  -- The langmap and the English switch matter from the first key, which comes after the first screen.
  event = "VeryLazy",
  config = function()
    vim.opt.langmap =
      "ㅁa,ㅠb,ㅊc,ㅇd,ㄷe,ㄹf,ㅎg,ㅗh,ㅑi,ㅓj,ㅏk,ㅣl,ㅡm,ㅜn,ㅐo,ㅔp,ㅂq,ㄱr,ㄴs,ㅅt,ㅕu,ㅍv,ㅈw,ㅌx,ㅛy,ㅋz,ㅃQ,ㅉW,ㄸE,ㄲR,ㅆT,ㅒO,ㅖP"

    -- Windows: through the running indicator watcher's stdin when there is one, starting no process; a failure of the
    -- command is reported in Neovim (lua/features/windows_platform/windows_ime_helper.lua). Elsewhere the command runs
    -- as it always did.
    local win = vim.fn.has("win32") == 1
    local send = win and require("features.windows_platform.windows_ime_helper").send or nil

    local function reset_on(cmd)
      local report = win
          and function(res)
            if res.code ~= 0 then
              require("features.windows_platform.windows_ime_helper").report_exit(
                vim.fs.basename(cmd[1]) .. " " .. (cmd[2] or ""),
                res
              )
            end
          end
        or nil

      -- The switch acts on the foreground window: an InsertLeave while another program has the focus (a timer, a
      -- --remote-send) would switch that program's IME. A terminal without focus reports stays "focused".
      local group = vim.api.nvim_create_augroup("korean_input", { clear = true })
      local is_focused = true

      vim.api.nvim_create_autocmd("FocusLost", {
        group = group,
        callback = function()
          is_focused = false
        end,
      })

      vim.api.nvim_create_autocmd({ "InsertLeave", "FocusGained" }, {
        group = group,
        callback = function(ev)
          is_focused = is_focused or ev.event == "FocusGained"

          if not is_focused then
            return
          end

          if send and send("e") then
            return
          end

          pcall(vim.system, cmd, { stdout = false, stderr = report ~= nil, text = true }, report)
        end,
      })
    end

    local cmd = require("features.input_method.per_os_backends").english_command()

    if cmd then
      reset_on(cmd)
    elseif vim.fn.has("win32") == 1 then
      -- The first start builds windows_ime_helper in the background; the switch begins once it lands.
      require("features.windows_platform.windows_ime_helper").on_ready(function()
        local built = require("features.input_method.per_os_backends").english_command()

        if built then
          reset_on(built)
        end
      end)
    end

    if vim.g.neovide or not (vim.env.TERM or ""):find("^foot") or vim.uv.guess_handle(2) ~= "tty" then
      return
    end

    -- foot's private IME mode: CSI ? 737769 h enables the input method, l disables it.
    local foot_ime = vim.api.nvim_create_augroup("foot_terminal_input_method", { clear = true })

    local function foot_send(seq)
      pcall(vim.fn.chansend, vim.v.stderr, seq)
    end

    vim.api.nvim_create_autocmd("InsertEnter", {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769h")
      end,
    })

    vim.api.nvim_create_autocmd({ "InsertLeave", "VimEnter" }, {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769l")
      end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769h")
      end,
    })
  end,
}
