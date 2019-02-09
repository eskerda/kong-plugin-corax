local utils = require "kong.tools.utils"

local filters = {}

function filters.by_request(conf)
  local rules = {
    function()
      local method = kong.request.get_method()
      return not utils.table_contains(conf.request_method, method)
    end,
  }
  for _, rule in ipairs(rules) do if rule() then return true end end
  return false
end

function filters.by_response_headers(conf)
  local rules = {
    function ()
      local status = kong.response.get_status()
      return not utils.table_contains(conf.response_code, tostring(status))
    end,
    function ()
      local content_type = kong.response.get_header("content-type")
      return not utils.table_contains(conf.content_type, content_type)
    end,
  }
  for _, rule in ipairs(rules) do if rule() then return true end end
  return false
end

return filters
