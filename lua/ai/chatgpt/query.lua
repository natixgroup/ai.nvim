local curl = require('plenary.curl')
local query = {}

-- Function in order to escape "%" character
function query.escapePercent(s)
  return string.gsub(s, "%%", "%%%%")
end

function query.formatResult(data)
  local result = '\n# This is ChatGPT answer\n\n'
  result = result .. data.choices[1].message.content .. '\n\n'
  return query.escapePercent(result)
end

function query.askCallback(res, prompt, opts)
  local result
  if res.status ~= 200 then
    if opts.handleError ~= nil then
      result = opts.handleError(res.status, res.body)
    else
      result = 'Error: ChatGPT API responded with the status ' .. tostring(res.status) .. '\n\n' .. res.body
    end
  else
    local data = vim.fn.json_decode(res.body)
    result = query.formatResult(data)
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end

function query.ask(prompt, opts, api_key)
  curl.post('https://api.openai.com/v1/chat/completions',
    {
      raw = {
        { '-H', 'Content-type: application/json' },
        { '-H', 'Authorization: Bearer ' .. api_key }
      },
      body = vim.fn.json_encode(
          {
            model = 'gpt-4-turbo-preview',
            messages = {
              { role = 'user', content = prompt}},
            temperature = 0.7
          }
      ),
      callback = function(res)
        vim.schedule(function() query.askCallback(res, prompt, opts) end)
      end
    })
end

return query
