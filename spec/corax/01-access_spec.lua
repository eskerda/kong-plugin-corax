local redis = require "resty.redis"
local helpers = require "spec.helpers"
local version = require("version").version

local PLUGIN_NAME = "corax"
local KONG_VERSION = version(select(3, assert(helpers.kong_exec("version"))))

local DEFAULT_ROUTE_HOST           = "test1.com"
local VARY_QUERY_PARAMS_ROUTE_HOST = "test2.com"


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local red = redis:new()

    lazy_setup(function()
      local bp, routes

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
        }
      }

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
      client = helpers.proxy_client()
      local ok, err = red:connect('localhost', '6379')
      assert(ok, err)
    end)

    after_each(function()
      if client then client:close() end
      red:flushall()
    end)

    describe("request", function()
      describe("methods", function()
        it("handles GET", function()
          local r = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = DEFAULT_ROUTE_HOST
            }
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.is.equal("Miss", header_value)
          -- assert some sort of mock that a cache entry has been added
        end)

        it("does not handle PUT", function()
          local r = assert(client:send {
            method = "PUT",
            path = "/request",
            headers = {
              host = DEFAULT_ROUTE_HOST
            }
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Bypass", header_value)
          -- assert that no cache entry has been added
        end)
      end)

      describe("query_params_default", function()
        before_each(function()
          assert(helpers.proxy_client():send {
            method = "GET",
            path = "/request",
            headers = {
              host = DEFAULT_ROUTE_HOST,
            },
            query = { some = "foo", params = "bar" },
          })
        end)

        it("caches all query params for keys when not configured", function()
          local r = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/request",
            headers = {
              host = DEFAULT_ROUTE_HOST,
            },
            query = { some = "foo", params = "bar" },
          })

          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Hit", header_value)
        end)

        it("does not cache a subset of query params", function()
          local r = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = VARY_QUERY_PARAMS_ROUTE_HOST
            },
            query = { some = "foo" },
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Miss", header_value)
        end)

        it("caches different querystring values separately", function()
          local r = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = VARY_QUERY_PARAMS_ROUTE_HOST
            },
            query = { some = "bar", params = "foo" },
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Miss", header_value)
        end)
      end)

      describe("vary_query_params", function()
        before_each(function()
          assert(helpers.proxy_client():send {
            method = "GET",
            path = "/request",
            headers = {
              host = VARY_QUERY_PARAMS_ROUTE_HOST
            },
            query = { some = "foo", params = "bar" },
          })
        end)

        it("caches a superset of vary query params", function()
          local r = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = VARY_QUERY_PARAMS_ROUTE_HOST
            },
            query = { some = "foo", params = "bar", awesome = "baz"},
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Hit", header_value)
        end)

        it("does not cache a subset of vary query params", function()
          local r = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = VARY_QUERY_PARAMS_ROUTE_HOST
            },
            query = { some = "foo" },
          })
          local header_value = assert.response(r).has.header("X-Cache-Status")
          assert.equal("Miss", header_value)
        end)
      end)

    end)

  end)
end
