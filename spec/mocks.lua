local request = function(path, host, port, query, method, headers)
  return {
    get_path = function() return path end,
    get_host = function() return host end,
    get_port = function() return port end,
    get_query = function() return query end,
    get_method = function() return method end,
    get_headers = function() return headers end,
  }
end

local response = function(status, headers)
  return {
    get_header = function(key)
      return headers[key]
    end,
    get_status = function() return status end,
  }
end

return {
  request = request,
  response = response
}
