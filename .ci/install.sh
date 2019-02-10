#!/usr/bin/env bash
set -e

pushd $PLUGIN_PATH
  luarocks make
popd

export LUA_PATH="$PLUGIN_PATH/?.lua;$PLUGIN_PATH/?/init.lua;$LUA_PATH"
