## HTTP Compatibility Layer - Migration asyncdispatch → Chronos
## =============================================================================
##
## This module provides an HTTP abstraction layer to facilitate migration
## from asyncdispatch to Chronos. The APIs are very different.
##
## Usage:
##   import nimagent/utils/http_compat
##
##   let client = newHttpCompatClient()
##   let response = await client.get(url, headers)
##   echo response.body
##   client.close()
##
## Headers: use seq[(string, string)] everywhere
## =============================================================================

import ./async_compat

when defined(useChronos):
  ## Chronos mode (new)
  import chronos/apps/http/httpclient

  type
    HttpCompatClient* = ref object
      session: HttpSessionRef
      defaultHeaders: seq[(string, string)]

    HttpCompatResponse* = object
      code*: int
      body*: string
      is2xx*: bool

  proc newHttpCompatClient*(defaultHeaders: seq[(string, string)] = @[]): HttpCompatClient =
    ## Creates a Chronos-compatible HTTP client
    HttpCompatClient(
      session: HttpSessionRef.new(),
      defaultHeaders: defaultHeaders
    )

  proc close*(client: HttpCompatClient) =
    ## Closes the client (noop for Chronos, GC handles it)
    return

  proc toChronosHeaders(headers: seq[(string, string)]): seq[HttpHeaderTuple] =
    ## Converts seq[(string, string)] to seq[HttpHeaderTuple] for Chronos
    result = @[]
    for (name, value) in headers:
      result.add((name, value))

  proc get*(client: HttpCompatClient, url: string, headers: seq[(string, string)] = @[]): Future[HttpCompatResponse] {.async.} =
    ## GET request
    var allHeaders = client.defaultHeaders
    for h in headers:
      allHeaders.add(h)
    let headerTuples = toChronosHeaders(allHeaders)
    let requestRes = HttpClientRequestRef.get(client.session, url, headers = headerTuples)
    if requestRes.isErr:
      return HttpCompatResponse(code: 0, body: "", is2xx: false)
    let request = requestRes.get()
    let response = await request.send()
    let bodyBytes = await response.getBodyBytes()
    let bodyStr = cast[string](bodyBytes)
    let code = response.status
    return HttpCompatResponse(code: code, body: bodyStr, is2xx: code >= 200 and code < 300)

  proc post*(client: HttpCompatClient, url: string, body: string, headers: seq[(string, string)] = @[]): Future[HttpCompatResponse] {.async.} =
    ## POST request
    var allHeaders = client.defaultHeaders
    for h in headers:
      allHeaders.add(h)
    let headerTuples = toChronosHeaders(allHeaders)
    let bodyBytes = cast[seq[byte]](body)
    let requestRes = HttpClientRequestRef.post(client.session, url, headers = headerTuples, body = bodyBytes)
    if requestRes.isErr:
      return HttpCompatResponse(code: 0, body: "", is2xx: false)
    let request = requestRes.get()
    let response = await request.send()
    let respBodyBytes = await response.getBodyBytes()
    let respBodyStr = cast[string](respBodyBytes)
    let code = response.status
    return HttpCompatResponse(code: code, body: respBodyStr, is2xx: code >= 200 and code < 300)

else:
  ## asyncdispatch mode (legacy)
  import std/[httpclient, httpcore]

  type
    HttpCompatClient* = ref object
      client: AsyncHttpClient
      defaultHeaders: HttpHeaders

    HttpCompatResponse* = object
      code*: int
      body*: string
      is2xx*: bool

  proc newHttpCompatClient*(defaultHeaders: seq[(string, string)] = @[]): HttpCompatClient =
    ## Creates an asyncdispatch-compatible HTTP client
    let httpHeaders = newHttpHeaders()
    for (k, v) in defaultHeaders:
      httpHeaders[k] = v
    let client = newAsyncHttpClient()
    for k, v in httpHeaders:
      client.headers[k] = v
    HttpCompatClient(client: client, defaultHeaders: httpHeaders)

  proc close*(client: HttpCompatClient) =
    ## Closes the client
    client.client.close()

  proc toHttpHeaders(headers: seq[(string, string)]): HttpHeaders =
    ## Converts seq[(string, string)] to HttpHeaders
    result = newHttpHeaders()
    for (k, v) in headers:
      result[k] = v

  proc get*(client: HttpCompatClient, url: string, headers: seq[(string, string)] = @[]): Future[HttpCompatResponse] {.async.} =
    ## GET request
    let httpHeaders = toHttpHeaders(headers)
    for k, v in client.defaultHeaders:
      client.client.headers[k] = v
    for k, v in httpHeaders:
      client.client.headers[k] = v
    let response = await client.client.get(url)
    let responseBody = await response.body
    return HttpCompatResponse(
      code: int(response.code),
      body: responseBody,
      is2xx: response.code.is2xx
    )

  proc post*(client: HttpCompatClient, url: string, body: string, headers: seq[(string, string)] = @[]): Future[HttpCompatResponse] {.async.} =
    ## POST request
    let httpHeaders = toHttpHeaders(headers)
    for k, v in client.defaultHeaders:
      client.client.headers[k] = v
    for k, v in httpHeaders:
      client.client.headers[k] = v
    let response = await client.client.post(url, body)
    let responseBody = await response.body
    return HttpCompatResponse(
      code: int(response.code),
      body: responseBody,
      is2xx: response.code.is2xx
    )

## =============================================================================
## JSON API Helpers
## =============================================================================

proc newJsonHeaders*(): seq[(string, string)] =
  ## Returns standard JSON headers
  @[("Content-Type", "application/json")]

proc postJson*(
  client: HttpCompatClient,
  url: string,
  jsonBody: string,
  extraHeaders: seq[(string, string)] = newJsonHeaders()
): Future[HttpCompatResponse] {.async.} =
  ## POST with JSON body
  return await client.post(url, jsonBody, extraHeaders)

## =============================================================================
## Compatibility Tests
## =============================================================================

when isMainModule:
  echo "HTTP compat module loaded"
  when defined(useChronos):
    echo "Mode: CHRONOS"
  else:
    echo "Mode: asyncdispatch (legacy)"
