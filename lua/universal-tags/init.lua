local M = {}

local supportted_lang = {
  c = require("universal-tags.lang.cpp"),
  cpp = require("universal-tags.lang.cpp"),
}

local ts_parsers = require("nvim-treesitter.parsers")
local ts_utils = require("nvim-treesitter/ts_utils")

local function get_node_string(lines, node)
  local srow, scol, erow, ecol = node:range()
  if srow == erow then
    return string.sub(lines[srow + 1], scol + 1, ecol)
  else
    local s = {}
    table.insert(s, string.sub(lines[srow + 1], scol + 1, -1))
    for i=srow+2,erow do
      table.insert(s, lines[i])
    end
    table.insert(s, string.sub(lines[erow + 1], 1, ecol))
    return table.concat(s, '\n')
  end
end

local function get_node_length(node)
  local _, _, s = node:start()
  local _, _, e = node:end_()
  return e - s
end

local function where_am_i()
  local bufnr = vim.api.nvim_get_current_buf()

  local lang = ts_parsers.ft_to_lang(vim.api.nvim_buf_get_option(bufnr, "filetype"))

  local cfg = supportted_lang[lang]
  if cfg == nil then
    return ""
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local node = ts_utils.get_node_at_cursor()

  local nodes = {}
  while node ~= nil do
    if cfg.is_stop_node(node) then
      nodes = {}
    end
    table.insert(nodes, node)
    node = node:parent()
  end

  local fields = {}
  local leaf = {}
  local leaf_id = -1
  for i=1,#nodes do
    local symbols = cfg.get_symbols(nodes[i])
    if #symbols ~= 0 then
      leaf = symbols
      leaf_id = i
      break
    end
  end
  if leaf_id == -1 then
    return {}
  end
  for i=#nodes,leaf_id+1,-1 do
    local symbols = cfg.get_symbols(nodes[i])
    for _, symbol in ipairs(symbols) do
      if vim.tbl_contains(symbol.child_ids, nodes[i - 1]:id()) then
        for _, tag in ipairs(symbol.tags) do
          table.insert(fields, get_node_string(lines, tag))
        end
        break
      end
    end
  end
  local ret = {}
  for _, symbol in ipairs(leaf) do
    local leaf_tags = {}
    local last_tag = nodes[leaf_id]
    if #(symbol.tags) ~= 0 then
      for _, tag in ipairs(symbol.tags) do
        table.insert(leaf_tags, get_node_string(lines, tag))
        last_tag = tag
      end
      local row, col = last_tag:start()
      if #fields == 0 then
        table.insert(ret, {
          tag = table.concat(leaf_tags, cfg.symbol_sep),
          bufnr = bufnr,
          row = row,
          col = col,
          body_length = get_node_length(nodes[leaf_id]),
        })
      else
        table.insert(ret, {
          tag = table.concat(fields, cfg.symbol_sep) .. cfg.symbol_sep ..
                table.concat(leaf_tags, cfg.symbol_sep),
          row = row,
          col = col,
          body_length = get_node_length(nodes[leaf_id]),
        })
      end
    end
  end
  return ret
end

local function where_am_i_str()
  local r = where_am_i()
  local ret = {}
  for _,i in ipairs(r) do
    table.insert(ret, i.tag)
  end
  return table.concat(ret, ",")
end

local cache_value = ""
function M.cached_where_am_i_str()
	if vim.fn.mode() == 'i' then
		return cache_value
	end

  cache_value = where_am_i_str()

	return cache_value
end

local function get_all_tags_helper(node, bufnr, lines, namespace, cfg)
  local ret = {}
  local child_namespace = {}
  local symbols = cfg.get_symbols(node)
  for _, symbol in ipairs(symbols) do
    local t = namespace
    local last_tag = node
    for _, tag in ipairs(symbol.tags) do
      if t ~= nil then
        t = t .. cfg.symbol_sep .. get_node_string(lines, tag)
      else
        t = get_node_string(lines, tag)
      end
      last_tag = tag
    end
    for _, child_id in ipairs(symbol.child_ids) do
      child_namespace[child_id] = t
    end
    local row, col = last_tag:start()
    table.insert(ret, {
      tag = t,
      bufnr = bufnr,
      row = row,
      col = col,
      body_length = get_node_length(node),
    })
  end
  if not cfg.is_stop_node(node) then
    for n in node:iter_children() do
      vim.list_extend(ret, get_all_tags_helper(n, bufnr, lines, child_namespace[n:id()] or namespace, cfg))
    end
  end
  return ret
end

function M.get_all_tags(bufnr)
  local lang = ts_parsers.ft_to_lang(vim.api.nvim_buf_get_option(bufnr, "filetype"))
  local cfg = supportted_lang[lang]
  if cfg == nil then
    return {}
  end
  local root = vim.treesitter.get_parser(bufnr):parse()[1]:root()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return get_all_tags_helper(root, bufnr, lines, nil, cfg)
end

function M.supportted_bufnr(bufnr)
  local lang = ts_parsers.ft_to_lang(vim.api.nvim_buf_get_option(bufnr, "filetype"))

  local cfg = supportted_lang[lang]

  return cfg ~= nil
end

function M.supportted()
  local bufnr = vim.api.nvim_get_current_buf()
  return M.supportted_bufnr(bufnr)
end

return M
