local filters = require "kong.plugins.corax.filters"
local mocks = require "spec.mocks"

local PLUGIN_NAME = require("kong.plugins.corax").PLUGIN_NAME

describe(PLUGIN_NAME .. ": (filters) ", function()
  local conf

  before_each(function()
    conf = {
      request_method = {"GET", "POST"},
      content_type = {"application/json"},
      response_code = {"200", "404"}
    }
  end)

  describe("request filters", function()
    it("filters by request method", function()
      local args = {"path", "host", "port", {}, "FOOBAR", {}}
      local request = mocks.request(unpack(args))
      assert.True(filters.by_request(conf, request))
    end)

    it("allows request method", function()
      local args = {"path", "host", "port", {}, "GET", {}}
      local request = mocks.request(unpack(args))
      assert.False(filters.by_request(conf, request))
    end)
  end)

  describe("response header filters", function()
    local headers = {
      ["content-type"] = "application/json; charset=utf-8",
      ["foo"] = "bar"
    }
    it("filters by status code", function()
      local res = mocks.response(418, headers)
      assert.True(filters.by_response(conf, res))
    end)

    it("allows by status code", function()
      local res = mocks.response(200, headers)
      assert.False(filters.by_response(conf, res))
    end)

    it("filters by content type", function()
      conf.content_type = {"text/plain"}
      local res = mocks.response(200, headers)
      assert.True(filters.by_response(conf, res))
    end)

    it("allows by content type", function()
      local res = mocks.response(200, headers)
      assert.False(filters.by_response(conf, res))
    end)
  end)
end)
