local cjson = require "cjson"
local redis = require "resty.redis"
local tx = require "pl/tablex"
local utils = require "kong.tools.utils"


local function is_present(str)
  return str and str ~= "" and str ~= ngx.null
end

local redis_connection = function(conf)
  local red = redis:new()
  local sock_opts = {}
  red:set_timeout(conf.redis_timeout)

  -- use a special pool name only if redis_database is set to non-zero
  -- otherwise use the default pool name host:port
  sock_opts.pool = conf.redis_database and
                   conf.redis_host .. ":" .. conf.redis_port ..
                   ":" .. conf.redis_database
  local ok, err = red:connect(conf.redis_host, conf.redis_port,
                              sock_opts)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, err
  end

  if times == 0 then
    if is_present(conf.redis_password) then
      local ok, err = red:auth(conf.redis_password)
      if not ok then
        kong.log.err("failed to auth Redis: ", err)
        return nil, err
      end
    end

    if conf.redis_database ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database

      local ok, err = red:select(conf.redis_database)
      if not ok then
        kong.log.err("failed to change Redis database: ", err)
        return nil, err
      end
    end
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
