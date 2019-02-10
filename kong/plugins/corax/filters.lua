local utils = require "kong.tools.utils"

local filters = {}

function filters.by_request(conf, request)
  local rules = {
    function()
      local method = request.get_method()
      return not utils.table_contains(conf.request_method, method)
    end,
  }
  for _, rule in ipairs(rules) do if rule() then return true end end
  return false
end

function filters.by_response_headers(conf, response)
  local rules = {
    function ()
      local status = response.get_status()
      return not utils.table_contains(conf.response_code, tostring(status))
    end,
    function ()
      local content_type = response.get_header("content-type")
      return not utils.table_contains(conf.content_type, content_type)
    end,
  }
  for _, rule in ipairs(rules) do if rule() then return true end end
  return false
end

return filters
