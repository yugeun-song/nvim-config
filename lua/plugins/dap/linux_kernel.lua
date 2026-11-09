-- Linux kernels in QEMU guests that kbuildlab started, debugged through gdb (lua/features/dap/linux_kernel/).
-- The commands are made with the debugger's others (lua/features/dap/core/init.lua); these load it.
return {
  "mfussenegger/nvim-dap",
  cmd = { "DbgLinuxKernel", "DbgLinuxKernelEarly" },
  keys = {
    {
      "<leader>dq",
      function()
        require("features.dap.linux_kernel.kbuildlab_guests").start()
      end,
      desc = "Debug: attach a kbuildlab guest kernel",
    },
    {
      "<leader>dQ",
      function()
        require("features.dap.linux_kernel.kbuildlab_guests").show_report()
      end,
      desc = "Debug: kbuildlab guests report",
    },
  },
}
