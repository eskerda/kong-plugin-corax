local utils = require "kong.tools.utils"
local redis = require "resty.redis"
local tx = require "pl/tablex"
local cjson = require "cjson"

local plugin = require("kong.plugins.base_plugin"):extend()

local kong = kong

plugin.VERSION = '1.0.0'
-- run this plugin after all auth plugins
plugin.PRIORITY = 1101

function plugin:new()
  plugin.super.new(self, "corax")
end

function plugin:init_worker()
  plugin.super.access(self)
end

function plugin:certificate(conf)
  plugin.super.access(self)
end

function plugin:rewrite(conf)
  plugin.super.rewrite(self)
end

function generate_key(conf)
  -- Do we really need an md5 here?
  -- Cons: Breaks locality
  -- Pros: Makes key length deterministic
  local path = kong.request.get_path()
  local host = kong.request.get_host()
  local port = kong.request.get_port()
  local query = kong.request.get_query()
  local method = kong.request.get_method()

  if conf.vary_query_params then
    local keys = tx.intersection(conf.vary_query_params, tx.keys(query))
    query = tx.pairmap(function(_, v) return query[v], v end, keys)
  end

  key = host .. port .. method .. path .. utils.encode_args(query)
  return ngx.md5(key)
end

function redis_connection(conf)
  local red = redis.new()
  local ok, err = red:connect(conf.redis_host, conf.redis_port)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, err
  end
  return red
end

function redis_async_set(conf, key, data)
  -- take a look at rate-imiting/handler.lua
  ngx.timer.at(0, function(premature)
    red = redis_connection(conf)
    red:set(key, data)
  end)
end


function redis_get(conf, key)
  red = redis_connection(conf)
  return red:get(key)
end

function plugin:access(conf)
  plugin.super.access(self)
  local method = kong.request.get_method()

  if not utils.table_contains(conf.request_method, method) then
    kong.response.set_header("X-Cache-Status", "Bypass")
    return
  end


  local key = generate_key(conf)
  local hit = redis_get(conf, key)

  if not hit or hit == ngx.null then
    ngx.ctx.should_cache_response = true
    ngx.ctx.cache_key = key
    kong.response.set_header("X-Cache-Status", "Miss")
    return
  end

  hit = cjson.decode(hit)

  return kong.response.exit(hit.status, hit.body, {
    ["X-Cache-Status"] = "Hit",
  })
end

function plugin:header_filter(conf)
  plugin.super.header_filter(self)
  -- if bypass_response(conf) then
  --   kong.response.set_header("X-Cache-Status", "Bypass")
  --   return
  -- end
end

function plugin:body_filter(conf)
  -- Here be dragons..
  -- Bastardized version from plugins/response-transformer/handler.lua
  plugin.super.body_filter(self)

  if not ngx.ctx.should_cache_response then return end

  local ctx = ngx.ctx
  local chunk, eof = ngx.arg[1], ngx.arg[2]

  ctx.rt_body_chunks = ctx.rt_body_chunks or {}
  ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

  if eof then
    local chunks = table.concat(ctx.rt_body_chunks)
    ngx.arg[1] = chunks
    response = {
      status = kong.response.get_status(),
      body = chunks,
    }
    return redis_async_set(conf, ctx.cache_key, cjson.encode(response))
  else
    ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
    ngx.arg[1] = nil
  end
end

function plugin:log(conf)
  plugin.super.log(self)
end

return plugin
