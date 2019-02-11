local tx = require "pl/tablex"
local cjson = require "cjson"
local redis = require "kong.plugins.corax.redis"
local utils = require "kong.tools.utils"
local str = require "resty.string"
local resty_sha256 = require "resty.sha256"

local PLUGIN_NAME = require("kong.plugins.corax").PLUGIN_NAME

local store = {}

local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"

function store.prefix(conf)
  local route_id   = conf.route_id or EMPTY_UUID
  local service_id = conf.service_id or EMPTY_UUID
  return PLUGIN_NAME .. "-" .. route_id .. "-" .. service_id
end

function store.key(conf, request)
  local prefix   = store.prefix(conf)
  local path     = request.get_path()
  local host     = request.get_host()
  local port     = request.get_port()
  local query    = request.get_query()
  local method   = request.get_method()
  local headers  = request.get_headers()

  if conf.vary_query_params then
    query = tx.intersection(query, tx.makeset(conf.vary_query_params or {}))
  end

  local key_elements = {
    host, port, method, path, utils.encode_args(query)
  }

  headers = tx.intersection(headers, tx.makeset(conf.vary_headers or {}))
  headers = tx.pairmap(function(k, v) return k .. ":" .. v end, headers)

  key_elements = tx.insertvalues(key_elements, headers)

  -- Not sure how novel or stupid this idea is. To avoid collision between
  -- key elements, make an md5 of them. ¯\_(ツ)_/¯
  local sha256 = resty_sha256:new()
  tx.reduce(function (memo, elem)
    return memo and sha256:update(ngx.md5(tostring(elem)))
  end, key_elements)
  local hex_digest = str.to_hex(sha256:final())

  return prefix .. "-" .. hex_digest
end

function store.set(conf, key, response)
  redis.set(conf, key, cjson.encode(response))
end

function store.get(conf, key)
  local hit = redis.get(conf, key)
  if not hit or hit == ngx.null then return false end
  return cjson.decode(hit)
end

return store
