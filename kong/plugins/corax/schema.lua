return {
  no_consumer = false,
  fields = {
    response_code = {
      type = "array",
      default = {"200", "201", "301", "401"},
      required = true,
    },
    request_method = {
      type = "array",
      default = {"GET", "POST"},
      required = true,
    },
    content_type = {
      type = "array",
      default = {"application/json", "text/plain"},
      required = true,
    },
    vary_query_params = {
      type = "array",
      required = false,
    },
    vary_headers = {
      type = "array",
      required = false,
    },
    cache_ttl = {
      type = "number",
      default = 300,
      required = true,
    },
    redis_host = {
      type = "string",
      required = true,
      default = "localhost",
    },
    redis_port = {
      type = "number",
      default = 6379,
      required = true,
    },
    redis_database = {
      type = "number",
      default = 0,
      required = true,
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    -- perform any custom verification
    return true
  end
}
