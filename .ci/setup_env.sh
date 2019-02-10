#!/usr/bin/env bash
set -e

KONG_PATH_DOWNLOAD="$DOWNLOAD_CACHE/kong-$KONG_VERSION"
KONG_PATH="$DOWNLOAD_CACHE/kong-$KONG_VERSION"

if [ ! "$(ls -A $KONG_PATH_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -s -S -L https://github.com/Kong/kong/archive/$KONG_VERSION.tar.gz | tar xz
  popd
fi

source $KONG_PATH/.ci/setup_env.sh

pushd $KONG_PATH
  make dev
popd

export LUA_PATH="$KONG_PATH/?.lua;$KONG_PATH/?/init.lua;$LUA_PATH"
export KONG_PATH=$KONG_PATH
