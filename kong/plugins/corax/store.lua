local cjson = require "cjson"
local redis = require "resty.redis"
local tx = require "pl/tablex"
local utils = require "kong.tools.utils"

local redis_connection = function(conf)
  -- XXX: Make better
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

local redis = {
  get = function(conf, key)
    local red = redis_connection(conf)
    return red:get(key)
  end,
  set = function(conf, key, value)
    local red = redis_connection(conf)
    red:set(key, value)
    red:expire(key, conf.cache_ttl)
  end,
}

local store = {}

function store.key(conf, request)
  local path    = request.get_path()
  local host    = request.get_host()
  local port    = request.get_port()
  local query   = request.get_query()
  local method  = request.get_method()
  local headers = request.get_headers()

  if conf.vary_query_params then
    query = tx.intersection(query, tx.makeset(conf.vary_query_params or {}))
  end

  headers = tx.intersection(headers, tx.makeset(conf.vary_headers or {}))
  headers = tx.pairmap(function(k, v) return k .. ":" .. v end, headers)
  headers = table.concat(headers, ",")

  local key_elements = {
    host, port, method, path, utils.encode_args(query), headers,
  }

  key = table.concat(key_elements)
  return ngx.md5(key)
end

function store.set(conf, key, response)
  redis.set(conf, key, cjson.encode(response))
end

function store.get(conf, request)
  local key = store.key(conf, request)
  local hit = redis.get(conf, key)
  if not hit or hit == ngx.null then return false end
  return cjson.decode(hit)
end

return store
