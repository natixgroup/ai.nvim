local gemini = require('ai.gemini.query')
local chatgpt = require('ai.chatgpt.query')

local default_prompts = {
  freeStyle = {
    command = 'AIAsk',
    loading_tpl = 'Loading...',
    prompt_tpl = '${input}',
    result_tpl = '${output}',
    require_input = true,
  },
}

local M = {}
M.opts = {
  gemini_api_key = '',
  chatgpt_api_key = '',
  locale = 'en',
  alternate_locale = 'zh',
  result_popup_gets_focus = false,
}
M.prompts = default_prompts
local win_id

function M.findConfig()
  local path = vim.fn.getcwd()
  while path ~= '/' do
    local config = path .. '/.aiconfig'
    if vim.fn.filereadable(config) == 1 then
      print('Found config at ' .. config)
      -- print the content of the file
      local lines = vim.fn.readfile(config)
      for _, line in ipairs(lines) do
        print(line)
      end
      return
    end
    path = vim.fn.fnamemodify(path, ':h')
  end
  print('Config not found')
end

local function splitLines(input)
  local lines = {}
  local offset = 1
  while offset > 0 do
    local i = string.find(input, '\n', offset)
    if i == nil then
      table.insert(lines, string.sub(input, offset, -1))
      offset = 0
    else
      table.insert(lines, string.sub(input, offset, i - 1))
      offset = i + 1
    end
  end
  return lines
end

local function joinLines(lines)
  local result = ""
  for _, line in ipairs(lines) do
    result = result .. line .. "\n"
  end
  return result
end

local function isEmpty(text)
  return text == nil or text == ''
end

function M.hasLetters(text)
  return type(text) == 'string' and text:match('[a-zA-Z]') ~= nil
end


function M.getSelectedText(esc)
  if esc then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'n', false)
  end
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  -- If the selection has been made under VISUAL mode:
  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, vstart[2] - 1, vstart[3] - 1, vend[2] - 1, vend[3], {})
  if ok then
    return joinLines(lines)
  else
    -- If the selection has been made under VISUAL LINE mode:
    lines = vim.api.nvim_buf_get_lines(0, vstart[2] - 1, vend[2], false)
    return joinLines(lines)
  end
end

function M.close()
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then
    return
  end
  pcall(vim.api.nvim_win_close, win_id, true)
  win_id = nil
end

function M.createPopup(initialContent, width, height)
  M.close()

  local bufnr = vim.api.nvim_create_buf(false, true)

  local update = function(content)
    if content == nil then
      content = ''
    end
    local lines = splitLines(content)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.bo[bufnr].modifiable = false
  end

  win_id = vim.api.nvim_open_win(bufnr, false, {
    relative = 'cursor',
    border = 'single',
    title = 'ai.nvim',
    style = 'minimal',
    width = width,
    height = height,
    row = 1,
    col = 0,
  })
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  update(initialContent)
  if M.opts.result_popup_gets_focus then
    vim.api.nvim_set_current_win(win_id)
  end
  return update
end

function M.fill(tpl, args)
  if tpl == nil then
    tpl = ''
  else
    for key, value in pairs(args) do
      tpl = string.gsub(tpl, '%${' .. key .. '}', value)
    end
  end
  return tpl
end

function M.handle(name, input)
  local def = M.prompts[name]
  local width = vim.fn.winwidth(0)
  local height = vim.fn.winheight(0)
  local args = {
    locale = M.opts.locale,
    alternate_locale = M.opts.alternate_locale,
    input = input,
    input_encoded = vim.fn.json_encode(input),
  }

  local update = M.createPopup(M.fill(def.loading_tpl, args), width - 24, height - 16)
  local prompt = M.fill(def.prompt_tpl, args)

  -- Function to handle both gemini and chatgpt results
  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.gemini_output or '') .. (args.chatgpt_output or '')
    return M.fill(def.result_tpl or '${output}', args)
  end

  gemini.ask(
    prompt,
    {
      handleResult = function(gemini_output) return handleResult(gemini_output, 'gemini_output') end,
      callback = update
    },
    M.opts.gemini_api_key
  )

  chatgpt.ask(
    prompt,
    {
      handleResult = function(chatgpt_output) return handleResult(chatgpt_output, 'chatgpt_output') end,
      callback = update
    },
    M.opts.chatgpt_api_key
  )
end

function M.assign(table, other)
  for k, v in pairs(other) do
    table[k] = v
  end
  return table
end

function M.setup(opts)
  for k, v in pairs(opts) do
    if k == 'prompts' then
      M.prompts = {}
      M.assign(M.prompts, default_prompts)
      M.assign(M.prompts, v)
    elseif M.opts[k] ~= nil then
      M.opts[k] = v
    end
  end


  for k, v in pairs(M.prompts) do
    if v.command then
      vim.api.nvim_create_user_command(v.command, function(args)
        local text = args['args']
        if isEmpty(text) then
          text = M.getSelectedText(true)
        end
        if not v.require_input or M.hasLetters(text) then
          -- delayed so the popup won't be closed immediately
          vim.schedule(function()
            M.handle(k, text)
          end)
        end
      end, { range = true, nargs = '?' })
    end
  end
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  callback = M.close,
})

vim.api.nvim_create_user_command('AIDefineCword', function()
  local text = vim.fn.expand('<cword>')
  if M.hasLetters(text) then
    M.handle('define', text)
  end
end, {})

-- Create a user command "AIFindConfig" to call the function M.findConfig
vim.api.nvim_create_user_command('AIFindConfig', M.findConfig, {})

return M
