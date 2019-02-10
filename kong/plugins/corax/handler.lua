local plugin = require("kong.plugins.base_plugin"):extend()

local store = require "kong.plugins.corax.store"
local filters = require "kong.plugins.corax.filters"
local kong = kong

local PLUGIN_NAME    = require("kong.plugins.corax").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.corax").PLUGIN_VERSION

function plugin:new()
  plugin.super.new(self, PLUGIN_NAME)
end

function plugin:access(conf)
  plugin.super.access(self)

  if filters.by_request(conf, kong.request) then
    kong.response.set_header("x-cache-status", "Bypass")
    ngx.ctx.cache_bypass = true
    return
  end

  local key = store.key(conf, kong.request)
  local response = store.get(conf, key)
  if not response then
    kong.response.set_header("x-cache-status", "Miss")
    ngx.ctx.cache_bypass = false
    return
  end

  -- XXX: Possibly filter some headers out from here ?
  -- We are just trusting that kong is overwriting messy headers along
  -- when returning the response
  local headers = response.headers or {}
  headers["x-cache-status"] = "Hit"
  return kong.response.exit(response.status, response.body, headers)
end

function plugin:header_filter(conf)
  plugin.super.header_filter(self)
  if filters.by_response(conf, kong.response) then
    kong.response.set_header("x-cache-status", "Bypass")
    ngx.ctx.cache_bypass = true
    return
  end
end

local function run_store_set(premature, conf, key, response)
  if premature then return end
  return store.set(conf, key, response)
end


function plugin:body_filter(conf)
  -- Here be dragons..
  -- Bastardized version from plugins/response-transformer/handler.lua
  plugin.super.body_filter(self)

  local ctx = ngx.ctx
  local chunk, eof = ngx.arg[1], ngx.arg[2]

  if ctx.cache_bypass then return end

  ctx.rt_body_chunks = ctx.rt_body_chunks or {}
  ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

  if eof then
    local chunks = table.concat(ctx.rt_body_chunks)
    ngx.arg[1] = chunks

    local response = {
      body = chunks,
      status = kong.response.get_status(),
      headers = kong.response.get_headers(),
    }
    local key = store.key(conf, kong.request)

    local ok, err = ngx.timer.at(0, run_store_set, conf, key, response)
    if not ok then
      self.log(ngx.ERR, "failed to create store set timer: ", err)
      return
    end
  else
    ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
    ngx.arg[1] = nil
  end
end

plugin.VERSION = PLUGIN_VERSION
plugin.PRIORITY = 1101    -- handle this plugin after all auth plugins

return plugin
