-- The filetypes clangd's inactive regions come from: the module serves only these, and its spec loads on them.
return vim.list_extend(vim.list_slice(require("features.lang.c").C_FAMILY), { "c.doxygen", "cpp.doxygen" })
