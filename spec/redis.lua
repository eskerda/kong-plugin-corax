local helpers = require "spec.helpers"
local redis = require "resty.redis"

local PLUGIN_NAME = require("kong.plugins.corax").PLUGIN_NAME

local REDIS_HOST     = "127.0.0.1"
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 0

local function redis_connection()
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
  if not ok then
    error("failed to connect to Redis: " .. err)
  end

  if REDIS_PASSWORD and REDIS_PASSWORD ~= "" then
    local ok, err = red:auth(REDIS_PASSWORD)
    if not ok then
      error("failed to connect to Redis: " .. err)
    end
  end

  local ok, err = red:select(REDIS_DATABASE)
  if not ok then
    error("failed to change Redis database: " .. err)
  end
  return red
end

return {
  REDIS_HOST = REDIS_HOST,
  REDIS_PORT = REDIS_PORT,
  REDIS_PASSWORD = REDIS_PASSWORD,
  REDIS_DATABASE = REDIS_DATABASE,
  connection = redis_connection,
  flush = function()
    local red = redis_connection()
    red:flushall()
    red:close()
  end,
  keys = function(red, query)
    query = query or PLUGIN_NAME .. "-*"
    return red:keys(query)
  end,
}
