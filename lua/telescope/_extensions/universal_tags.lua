local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
  error "This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)"
end

local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local previewers = require "telescope.previewers"
local sorters = require "telescope.sorters"
local entry_display = require "telescope.pickers.entry_display"
local conf = require("telescope.config").values
local Sorter = require("telescope.sorters").Sorter
local universal_tags = require('universal-tags')

local function gen_from_tag(opts)
  local display_items = {
    { remaining = true },
  }

  local displayer = entry_display.create {
    separator = " ",
    items = display_items,
  }

  local type_highlight = opts.symbol_highlights or treesitter_type_highlight

  local make_display = function(entry)
    local display_columns = {
      entry.text
    }
    return displayer(display_columns)
  end

  return function(entry)
    return {
      valid = true,

      value = entry.tag,
      kind = entry.kind,
      ordinal = entry.tag,
      display = make_display,

      node_text = entry.tag,

      filename = vim.api.nvim_buf_get_name(entry.bufnr),
      -- need to add one since the previewer substacts one
      lnum = entry.row + 1,
      col = entry.col,
      text = entry.tag,
      start = entry.row,
      finish = entry.row,
    }
  end
end

local function sort(sep, prompt, line)
  local MAX_SCORE = 10000000
  local SEP_SCORE = 50000
  local LINK_SCORE = 10000
  local LENGTH_SCORE = 100
  local LINE_LENGTH_SCORE = 1

  local generate_sep = function(sep, str)
    local ret = {}
    for i=1,#str do
      ret[i] = 0
      for _, s in ipairs(sep) do
        if string.sub(str, i, i + #s - 1) == s then
          ret[i] = #s
        end
      end
    end
    return ret
  end
  local generate_chars = function(str)
    local ret = {}
    for i=1,#str do
      ret[i] = string.sub(str, i, i)
    end
    return ret
  end
  local min_with_loc = function(...)
    local r = {MAX_SCORE, nil}
    for _,kv in ipairs{...} do
      if kv[1] < r[1] then
        r = kv
      end
    end
    return r
  end
  local add_with_loc = function(kv, delta)
    return {kv[1] + delta, kv[2]}
  end
  local path_with_loc = function(kv, path)
    return {kv[1], {path, kv[2]}}
  end

  local lower_prompt = generate_chars(string.lower(prompt))
  local lower_line = generate_chars(string.lower(line))
  local prompt_sep = generate_sep(sep, prompt)
  local line_sep = generate_sep(sep, line)
 
  if #prompt == 0 then
    return 1, {}
  end
  local ptr = 1
  for i=1,#line do
    if (line_sep[i] > 0 and prompt_sep[ptr] > 0) or 
        (line_sep[i] == 0 and prompt_sep[ptr] == 0 and
            lower_line[i] == lower_prompt[ptr]) then
      ptr = ptr + 1
      if ptr > #prompt then
        break
      end
    end
  end
  if ptr <= #prompt then
    return -1, {}, {}
  end
  local DP_N = {}
  local DP_Y = {}

  DP_N[#line + 1] = {}
  DP_Y[#line + 1] = {}
  for i = #prompt + 1,1,-1 do
    DP_N[#line + 1][i] = {MAX_SCORE, nil}
    DP_Y[#line + 1][i] = {MAX_SCORE, nil}
  end
  DP_N[#line + 1][#prompt + 1] = {1, nil}
  for i = #line,1,-1 do
    DP_N[i] = {}
    DP_Y[i] = {}
    DP_Y[i][#prompt + 1] = {MAX_SCORE, nil}
    if line_sep[i] > 0 then
      DP_N[i][#prompt + 1] = add_with_loc(DP_N[i + line_sep[i]][#prompt + 1], SEP_SCORE)
    else
      DP_N[i][#prompt + 1] = DP_N[i + 1][#prompt + 1]
    end
  end
  for i = #line,1,-1 do
    for j = #prompt,1,-1 do
      if line_sep[i] > 0 then
        if prompt_sep[j] > 0 then
          DP_Y[i][j] = {MAX_SCORE, nil}
          DP_N[i][j] = add_with_loc(min_with_loc(
              DP_Y[i + line_sep[i]][j],
              DP_N[i + line_sep[i]][j],
              path_with_loc(DP_Y[i + line_sep[i]][j + prompt_sep[j]], i),
              path_with_loc(DP_N[i + line_sep[i]][j + prompt_sep[j]], i)), SEP_SCORE)
        else
          DP_Y[i][j] = {MAX_SCORE, nil}
          DP_N[i][j] = add_with_loc(min_with_loc(
              DP_Y[i + line_sep[i]][j],
              DP_N[i + line_sep[i]][j]), SEP_SCORE)
        end
      else
        if prompt_sep[j] == 0 and lower_line[i] == lower_prompt[j] then
          DP_Y[i][j] = path_with_loc(add_with_loc(min_with_loc(
              DP_Y[i + 1][j + 1],
              DP_N[i + 1][j + 1]), LINK_SCORE), i)
        else
          DP_Y[i][j] = {MAX_SCORE, nil}
        end
        DP_N[i][j] = min_with_loc(DP_Y[i + 1][j], DP_N[i + 1][j])
      end
    end
  end
  local score = {MAX_SCORE}
  for i = #line,1,-1 do
    score = min_with_loc(
        add_with_loc(DP_Y[i][1], LENGTH_SCORE * (#line + 1 - i)),
        add_with_loc(DP_N[i][1], LENGTH_SCORE * (#line + 1 - i)),
        score)
  end
  if score[1] < MAX_SCORE then
    local xscore = score[2]
    local ret = {}
    while xscore ~= nil do
      if line_sep[xscore[1]] > 0 then
        for i=1,line_sep[xscore[1]] do
          table.insert(ret, xscore[1] - 1 + i)
        end
      else
        table.insert(ret, xscore[1])
      end
      xscore = xscore[2]
    end
    return score[1] + LINE_LENGTH_SCORE * #line, ret
  else
    return -1, {}
  end
end

local function all_bufs()
  local ret = {}
  for _,b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(b) ~= 0 and vim.api.nvim_buf_get_name(b) ~= "" then
      table.insert(ret, b)
    end
  end
  return ret
end

local function show(opts)
  opts = opts or {}
  local results = {}

  local bufnrs = all_bufs()
  for _,bufnr in ipairs(bufnrs) do
    vim.list_extend(results, universal_tags.get_all_tags(bufnr))
  end

  pickers.new(opts, {
    prompt_title = "Universal Tags",
    finder = finders.new_table {
      results = results,
      entry_maker = opts.entry_maker or gen_from_tag(opts),
    },
    previewer = conf.grep_previewer(opts),
    sorter = Sorter:new{
      scoring_function = function(_, prompt, line)
        return (sort(opts.sep or {"::", "."}, prompt, line))
      end,
      highlighter = function (_, prompt, line)
        local t = string.match(line, "%s+")
        if t == nil then
          return {}
        end
        local _, pos = string.find(line, t)
        pos = pos + 1
        realline = string.sub(line, pos)
        local _, s = sort({"::", "."}, prompt, realline)
        local ret = {}
        for _,t in ipairs(s) do
          table.insert(ret, t + pos - 1)
        end
        return ret
      end
    },
  }):find()
end

return telescope.register_extension {
  setup = function(ext_config)
  end,
  exports = {
    universal_tags = show,
  },
}
