local helpers = require "spec.helpers"
local version = require("version").version

local PLUGIN_NAME = require("kong.plugins.corax").PLUGIN_NAME
local KONG_VERSION = version(select(3, assert(helpers.kong_exec("version"))))

local REDIS_HOST     = "127.0.0.1"
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 0

local DEFAULT_ROUTE_HOST           = "test1.com"
local VARY_QUERY_PARAMS_ROUTE_HOST = "test2.com"
local CACHE_LOW_TTL_ROUTE_HOST     = "test3.com"
local VARY_HEADERS_ROUTE_HOST      = "test4.com"
local STATUS_CODES_ROUTE_HOST      = "test5.com"
local CUSTOM_HEADERS_ROUTE_HOST    = "test6.com"


local function cache_is_status(res, status)
  local header_value = assert.response(res).has.header("x-cache-status")
  assert.equal(status, header_value)
end

local function test_is_hit(res)
  cache_is_status(res, "Hit")
end

local function test_is_miss(res)
  cache_is_status(res, "Miss")
end

local function test_is_bypass(res)
  cache_is_status(res, "Bypass")
end

local function redis_connection()
  local redis = require "resty.redis"
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

local redis = {
  connection = redis_connection,
  flush = function()
    local red = redis_connection()
    red:flushall()
    red:close()
  end,
  keys = function(red)
    return red:keys(PLUGIN_NAME .. "-*")
  end
}

local function request(method, url, opts, res_status)
  local client = helpers.proxy_client()
  opts["method"] = method
  opts["path"] = url
  local res, err  = client:send(opts)
  if not res then
    client:close()
    return nil, err
  end

  local body, err = assert.res_status(res_status, res)
  if not body then
    return nil, err
  end

  client:close()

  -- since redis set is happening on a timer, results might be flaky without
  -- sleeping
  ngx.sleep(0.010)

  return res, body
end

local function GET(url, opts, res_status)
  return request("GET", url, opts, res_status)
end

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client = helpers.proxy_client
    local red = redis.connection()

    local route_configs = {
      default = {
        host = DEFAULT_ROUTE_HOST,
        config = {},
      },
      vary_query = {
        host = VARY_QUERY_PARAMS_ROUTE_HOST,
        config = {
          vary_query_params = {"some", "params"},
        }
      },
      low_ttl = {
        host = CACHE_LOW_TTL_ROUTE_HOST,
        config = {
          cache_ttl = 1,
        }
      },
      vary_headers = {
        host = VARY_HEADERS_ROUTE_HOST,
        config = {
          vary_headers = {"some", "headers"}
        }
      },
      status_codes = {
        host = STATUS_CODES_ROUTE_HOST,
        config = {
          response_code = {"418"}
        }
      },
      custom_headers = {
        host = CUSTOM_HEADERS_ROUTE_HOST,
        config = {

        },
        plugins = {
          {
            name = "response-transformer",
            config = {
              add = { headers = {"X-Super-Duper:CustomDuper"} },
            }
          },
        }
      },
    }

    lazy_setup(function()
      local bp, routes

      redis.flush()

      if KONG_VERSION >= version("0.15.0") then
        --
        -- Kong version 0.15.0/1.0.0, new test helpers
        --
        bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })
      else
        --
        -- Pre Kong version 0.15.0/1.0.0, older test helpers
        --
        bp = helpers.get_db_utils(strategy)
      end

      routes = {}
      for name, route_config in pairs(route_configs) do
        routes[name] = bp.routes:insert({
          hosts = { route_config.host },
        })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = routes[name].id },
          config = route_config.config
        }
        for _, plugin in pairs(route_config.plugins or {}) do
          plugin["route"] = { id = routes[name].id }
          bp.plugins:insert(plugin)
        end
      end

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- set the config item to make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,  -- since Kong CE 0.14
        custom_plugins = PLUGIN_NAME,         -- pre Kong CE 0.14
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    after_each(function()
      redis.flush()
    end)

    describe("request", function()
      describe("methods", function()
        it("handles GET", function()
          local r = GET("/request", {
            headers = { host = DEFAULT_ROUTE_HOST }
          }, 200)
          test_is_miss(r)
          assert.are.equal(#redis.keys(red), 1)
        end)

        it("does not handle PUT", function()
          local r = request("PUT", "/request", {
            headers = { host = DEFAULT_ROUTE_HOST }
          }, 200)
          test_is_bypass(r)
          assert.are.equal(#redis.keys(red), 0)
        end)
      end)

      describe("with vary_query_params as default", function()
        before_each(function()
          GET("/request", {
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "foo", params = "bar" },
          }, 200)
          assert.are.equal(#redis.keys(red), 1)
        end)

        it("caches all query params", function()
          local r = GET("/request", {
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "foo", params = "bar" },
          }, 200)
          test_is_hit(r)
          assert.are.equal(#redis.keys(red), 1)
        end)

        it("a subset of the query params produce a new entry", function()
          local r = GET("/request", {
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "foo" },
          }, 200)
          test_is_miss(r)
          assert.are.equal(#redis.keys(red), 2)
        end)

        it("querystring values affect cache key generation", function()
          local r = GET("/request", {
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "bar", params = "foo" },
          }, 200)
          test_is_miss(r)
          assert.are.equal(#redis.keys(red), 2)
        end)
      end)

      describe("with defined vary_query_params and a new entry", function()
        before_each(function()
          assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "foo", params = "bar" },
          })
        end)

        it("a superset of params generate the same signature", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "foo", params = "bar", awesome = "baz"},
          })
          test_is_hit(r)
        end)

        it("a subset of params generate a different signature", function()
          local r = GET("/request", {
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "foo" },
          }, 200)
          test_is_miss(r)
          assert.are.equal(#redis.keys(red), 2)
        end)
      end)

      describe("cache_ttl", function()
        it("expires cache keys in specified cache_ttl", function()
          local r = GET("/request", {
            headers = { host = CACHE_LOW_TTL_ROUTE_HOST },
          }, 200)
          test_is_miss(r)

          assert.are.equal(#redis.keys(red), 1)
          -- Hey, we just made the tests cache_ttl (s) slower!
          ngx.sleep(route_configs.low_ttl.config.cache_ttl)
          assert.are.equal(#redis.keys(red), 0)

          local r2 = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = CACHE_LOW_TTL_ROUTE_HOST },
          })
          test_is_miss(r2)
        end)
      end)

      describe("headers", function()
        it("by default does not take headers into account", function()
          local r = GET("/request", {
            headers = {
              host = DEFAULT_ROUTE_HOST,
              some = "headers",
              more = "headers",
            },
          }, 200)
          local r2 = GET("/request", {
            headers = {
              host = DEFAULT_ROUTE_HOST,
              other = "headers",
              are = "here",
            },
          }, 200)
          test_is_hit(r2)
        end)

        describe("configured vary headers affect key generation", function()
          before_each(function()
            GET("/request", {
              headers = {
                host = VARY_HEADERS_ROUTE_HOST,
                some = "headers",
                headers = "are fun",
              },
            }, 200)
          end)

          it("with the same headers", function()
            local r = GET("/request", {
              headers = {
                host = VARY_HEADERS_ROUTE_HOST,
                some = "headers",
                headers = "are fun",
                other = "do not affect much",
              },
            }, 200)
            test_is_hit(r)
          end)

          it("with completely different headers", function()
            local r = GET("/request", {
              headers = {
                host = VARY_HEADERS_ROUTE_HOST,
                ["not-the-headers"] = "you are looking for",
              },
            }, 200)
            test_is_miss(r)
          end)

          it("with the same headers and different value", function()
            local r = GET("/request", {
              headers = {
                host = VARY_HEADERS_ROUTE_HOST,
                some = "headers",
                headers = "are different",
              },
            }, 200)
            test_is_miss(r)
          end)
        end)
      end)
    end)

    describe("response", function()
      describe("status code #teapot", function()
        it("does not cache non configured status codes", function()
          local r = GET("/status/418", {
            headers = {
              host = DEFAULT_ROUTE_HOST,
            },
          }, 418)
          test_is_bypass(r)
          assert.are.equal(#redis.keys(red), 0)
        end)

        it("caches configured status codes", function()
          local r = GET("/status/418", {
            headers = {
              host = STATUS_CODES_ROUTE_HOST,
            },
          }, 418)
          test_is_miss(r)

          -- Checks that the proxy is returning the same status code
          assert.are.equal(#redis.keys(red), 1)
          local r = GET("/status/418", {
            headers = {
              host = STATUS_CODES_ROUTE_HOST,
            },
          }, 418)
          test_is_hit(r)
        end)
      end)

      it("passes response headers along", function()
        -- Formally content type test also tests this feature.
        GET("/request", {
          headers = {
            host = DEFAULT_ROUTE_HOST,
          },
        }, 200)

        local r = GET("/request", {
          headers = {
            host = DEFAULT_ROUTE_HOST,
          },
        }, 200)
        test_is_hit(r)
        local header_value = assert.response(r).has.header("x-powered-by")
        assert.equal("mock_upstream", header_value)
      end)
    end)
  end)
end
