# Corax [![Build Status](https://travis-ci.org/eskerda/kong-plugin-corax.svg?branch=master)](https://travis-ci.org/eskerda/kong-plugin-corax)

```
redis response caching for the masses
                                                 ,::::.._
                                               ,':::::::::.
                                           _,-'`:::,::(o)::`-,.._
                                        _.', ', `:::::::::;'-..__`.
                                   _.-'' ' ,' ,' ,\:::,'::-`'''
                               _.-'' , ' , ,'  ' ,' `:::/
                         _..-'' , ' , ' ,' , ,' ',' '/::
                 _...:::'`-..'_, ' , ,'  , ' ,'' , ,'::|
              _`.:::::,':::::,'::`-:..'_',_'_,'..-'::,'|
      _..-:::'::,':::::::,':::,':,'::,':::,'::::::,':::;
        `':,'::::::,:,':::::::::::::::::':::,'::_:::,'/
        __..:'::,':::::::--''' `-:,':,':::'::-' ,':::/
   _.::::::,:::.-''-`-`..'_,'. ,',  , ' , ,'  ', `','
 ,::SSt:''''`                 \:. . ,' '  ,',' '_,'
                               ``::._,'_'_,',.-'
                                   \\ \\
                                    \\_\\
                                     \\`-`.-'_
                                  .`-.\\__`. ``
                                     ``-.-._
                                         `
```
Corax is a plugin for Kong that adds upstream response caching using Redis
as an storage backend.

Responses to an upstream request will be cached by Corax when they match based
on request method, response codes and content type. Once cached, requests
matching a cached object will be served from cache instead of going upstream,
until the cached object expires.

## Configuration

| field               | default                          | description                                                           |
|---------------------|:--------------------------------:|-----------------------------------------------------------------------|
| `response_code`     | 200, 201, 301, 401               |                                                                       |
| `request_method`    | `GET, POST`                      |                                                                       |
| `content_type`      | `application/json`, `text/plain` |                                                                       |
| `vary_query_params` |                                  | query string parameters included on key generation. Uses all if empty |
| `vary_headers`      |                                  | request headers included on key generation. Uses none if empty        |
| `cache_ttl`         | 300                              | TTL in seconds                                                        |
| `redis_host`        | `localhost`                      |                                                                       |
| `redis_port`        | 6379                             |                                                                       |
| `redis_password`    |                                  |                                                                       |
| `redis_database`    | 0                                |                                                                       |


## Cache status

Corax sets `X-Cache-Status` depending on:

* `Miss`: The request can be cached but was not found on the cache
* `Hit`: The request has been served from the cache
* `Bypass`: The request has bypassed the cache (configuration)

## Cache control

Corax will happily **ignore** cache control headers defined in [RF7234].

[RF7234]: https://tools.ietf.org/html/rfc7234#section-5.2
