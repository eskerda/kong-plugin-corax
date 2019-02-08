package = "kong-plugin-corax"
version = "0.1.0-1"

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/eskerda/kong-plugin-corax.git",
  tag = "0.1.0"
}

description = {
  summary = "The Amazing Corax goes pew pew.",
  homepage = "http://getkong.org",
  license = "Apache 2.0",
}

dependencies = {

}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.corax.handler"] = "kong/plugins/corax/handler.lua",
    ["kong.plugins.corax.schema"] = "kong/plugins/corax/schema.lua",
  }
}
