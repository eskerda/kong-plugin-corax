local cjson = require "cjson"

local store = require "kong.plugins.corax.store"
local redis = require "spec.redis"
local mock_request = require("spec.mocks").request

local PLUGIN_NAME = require("kong.plugins.corax").PLUGIN_NAME

describe(PLUGIN_NAME .. ": (store) ", function()
  describe("key generation", function()
    local conf = {
      route_id = "X0X0",
      vary_query_params = nil,
      vary_headers = nil,
    }

    it("prefixes keys with PLUGIN NAME and route_id", function()
      local args = {"path", "host", "port", {}, "method", {}}
      local req = mock_request(unpack(args))
      local key = store.key(conf, req)
      assert.is_true(key ~= PLUGIN_NAME .. "-" .. conf.route_id .. "-")
    end)

    it("handles a bunch of test cases", function()
      -- Not that useful actually, but manages to signal if we ever change
      -- how we are generating keys accidentally.
      local function gen_args(query, headers)
        return {"path", "host", "port", query, "method", headers}
      end
      local cases = {
        {
          req = gen_args({foo="bar"}, {}),
          vary_headers = nil,
          vary_query_params = nil,
          expected_uid = "e68848ed4dcad4e8c7d6cc5fc2a6600fb6f12aba02fd89664559be6b7cecb482"
        },
        {
          req = gen_args({foo="bar", bar="baz"}, {}),
          vary_headers = nil,
          vary_query_params = nil,
          expected_uid = "9b3c91a9e129fca73cb1fd6bd715fcf883ad5036f6e80c7f3d44b983e3d36f4a"
        },
        {
          req = gen_args({foo="bar", bar="baz"}, {}),
          vary_headers = nil,
          vary_query_params = {"foo"},
          expected_uid = "e68848ed4dcad4e8c7d6cc5fc2a6600fb6f12aba02fd89664559be6b7cecb482"
        },
        {
          req = gen_args({foo="bar", bar="baz"}, {["x-foo-bar"] = "foo"}),
          vary_headers = {"x-foo-bar"},
          vary_query_params = {"foo"},
          expected_uid = "869efd7e7a6e49fcfd6b0c55873510e5d3f6f2aa66f97af76ed327cd9c906804"
        },
      }

      local mock_req, key, prefix, conf
      for _, case in pairs(cases) do
        conf = {
          route_id = "X0X0",
          vary_headers = case.vary_headers,
          vary_query_params = case.vary_query_params,
        }
        mock_req = mock_request(unpack(case.req))
        key = store.key(conf, mock_req)
        prefix = PLUGIN_NAME .. "-" .. conf.route_id
        assert.is_equal(key, prefix .. "-" .. case.expected_uid)
      end
    end)
  end)

  describe("has a redis storage", function()
    local red = redis.connection()
    local conf

    lazy_setup(function()
      redis.flush()
    end)

    before_each(function()
      conf = {
        redis_host = redis.REDIS_HOST,
        redis_port = redis.REDIS_PORT,
        redis_database = redis.REDIS_DATABASE,
        redis_password = "",
        cache_ttl = 1000
      }
    end)

    after_each(function()
      redis.flush()
    end)

    it("stores things", function()
      local expected = {
        some = "easily",
        serializable = { "data", 1, 2, 3 },
      }
      store.set(conf, "some-fancy-key", expected)
      local result = cjson.decode(red:get("some-fancy-key"))
      assert.are.same(expected, result)
    end)

    it("gets things", function()
      local expected = {
        some = "easily",
        serializable = { "data", 1, 2, 3 },
      }
      store.set(conf, "some-fancy-key", expected)
      local result = store.get(conf, "some-fancy-key")
      assert.are.same(expected, result)
    end)

    it("stores things with a ttl", function()
      conf["cache_ttl"] = 0
      store.set(conf, "some-fancy-key", {foo = "bar"})
      assert.are.equal(#redis.keys(red, "some-fancy-key"), 0)
    end)
  end)
end)
