-- Korean input: a Dubeolsik langmap for Normal-mode keys typed in 한글, the IME switched to English on leaving
-- Insert (and on focus), and foot's own IME mode. The indicators are indicator.lua, the per-system commands
-- backends.lua.
local M = {}

local function on_foot()
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    if ui.stdout_tty and (ui.term_name or ""):find("^foot") then
      return true
    end
  end

  return false
end

function M.setup()
  vim.opt.langmap =
    "ㅁa,ㅠb,ㅊc,ㅇd,ㄷe,ㄹf,ㅎg,ㅗh,ㅑi,ㅓj,ㅏk,ㅣl,ㅡm,ㅜn,ㅐo,ㅔp,ㅂq,ㄱr,ㄴs,ㅅt,ㅕu,ㅍv,ㅈw,ㅌx,ㅛy,ㅋz,ㅃQ,ㅉW,ㄸE,ㄲR,ㅆT,ㅒO,ㅖP"

  -- Windows: through the running indicator watcher's stdin when there is one, starting no process; a failure of the
  -- command is reported in Neovim (lua/features/util/windows/ime_helper.lua). Elsewhere the command runs
  -- as it always did.
  local win = vim.fn.has("win32") == 1
  local send = win and require("features.util.windows.ime_helper").send or nil

  local function reset_on(cmds)
    local indicator = require("features.editor.korean_input.indicator")
    local chosen = 1

    -- The switch acts on the foreground window: an InsertLeave while another program has the focus (a timer, a
    -- --remote-send) would switch that program's IME. A terminal without focus reports stays "focused".
    local group = vim.api.nvim_create_augroup("korean_input", { clear = true })
    local is_focused = true

    -- The last working command runs first; a failing one hands over to the next.
    local function switch(i, left)
      local cmd = cmds[i]

      local function done(res)
        if res.code == 0 then
          chosen = i
        else
          if win then
            require("features.util.windows.ime_helper").report_exit(
              vim.fs.basename(cmd[1]) .. " " .. (cmd[2] or ""),
              res
            )
          end

          if left > 1 then
            switch(i % #cmds + 1, left - 1)
          end
        end

        indicator.switch_finished()
      end

      indicator.switch_started()
      local ok, err = pcall(vim.system, cmd, { stdout = false, stderr = win, text = true }, vim.schedule_wrap(done))

      if not ok then
        done({ code = -1, stderr = tostring(err) })
      end
    end

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

        switch(chosen, #cmds)
      end,
    })
  end

  local backends = require("features.editor.korean_input.backends")
  local cmds = backends.english_commands()

  if #cmds > 0 then
    reset_on(cmds)
  elseif win and not backends.remote() then
    -- The first start builds windows_ime_helper in the background; the switch begins once it lands.
    require("features.util.windows.ime_helper").on_ready(function()
      local built = backends.english_commands()

      if #built > 0 then
        reset_on(built)
      end
    end)
  end

  if vim.g.neovide or not on_foot() then
    return
  end

  -- foot's private IME mode: CSI ? 737769 h on, l off. nvim_ui_send never splits the TUI's own sequences.
  local foot_ime = vim.api.nvim_create_augroup("foot_terminal_input_method", { clear = true })

  local function foot_send(seq)
    pcall(vim.api.nvim_ui_send, seq)
  end

  local function ime_off()
    foot_send("\27[?737769l")
  end

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = foot_ime,
    callback = function()
      foot_send("\27[?737769h")
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", { group = foot_ime, callback = ime_off })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = foot_ime,
    callback = function()
      foot_send("\27[?737769h")
    end,
  })

  -- At startup wait for VimEnter; later, switch now.
  if vim.v.vim_did_enter == 0 then
    vim.api.nvim_create_autocmd("VimEnter", { group = foot_ime, once = true, callback = ime_off })
  elseif vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
    ime_off()
  end
end

return M
