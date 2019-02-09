local redis = require "resty.redis"
local helpers = require "spec.helpers"
local version = require("version").version

local PLUGIN_NAME = "corax"
local KONG_VERSION = version(select(3, assert(helpers.kong_exec("version"))))

local DEFAULT_ROUTE_HOST           = "test1.com"
local VARY_QUERY_PARAMS_ROUTE_HOST = "test2.com"
local CACHE_LOW_TTL_ROUTE_HOST     = "test3.com"


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


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client = helpers.proxy_client
    local red = redis:new()
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
    }

    lazy_setup(function()
      local bp, routes

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

    before_each(function()
      local ok, err = red:connect('localhost', '6379')
      assert(ok, err)
    end)

    after_each(function()
      red:flushall()
    end)

    describe("request", function()
      describe("methods", function()
        it("handles GET", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = DEFAULT_ROUTE_HOST }
          })
          test_is_miss(r)
          -- assert some sort of mock that a cache entry has been added
        end)

        it("does not handle PUT", function()
          local r = assert(client():send {
            method = "PUT",
            path = "/request",
            headers = { host = DEFAULT_ROUTE_HOST }
          })
          test_is_bypass(r)
          -- assert that no cache entry has been added
        end)
      end)

      describe("with vary_query_params as default", function()
        before_each(function()
          assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "foo", params = "bar" },
          })
        end)

        it("caches all query params", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = DEFAULT_ROUTE_HOST },
            query = { some = "foo", params = "bar" },
          })
          test_is_hit(r)
        end)

        it("a subset of the query params produce a new entry", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "foo" },
          })
          test_is_miss(r)
        end)

        it("querystring values affect cache key generation", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "bar", params = "foo" },
          })
          test_is_miss(r)
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
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = VARY_QUERY_PARAMS_ROUTE_HOST },
            query = { some = "foo" },
          })
          test_is_miss(r)
        end)
      end)

      describe("cache_ttl", function()
        it("expires cache keys in specified cache_ttl", function()
          local r = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = CACHE_LOW_TTL_ROUTE_HOST },
          })
          test_is_miss(r)

          -- Hey, we just made the tests cache_ttl (s) slower!
          ngx.sleep(route_configs.low_ttl.config.cache_ttl)

          local r2 = assert(client():send {
            method = "GET",
            path = "/request",
            headers = { host = CACHE_LOW_TTL_ROUTE_HOST },
          })
          test_is_miss(r2)
        end)
      end)

    end)

  end)
end
