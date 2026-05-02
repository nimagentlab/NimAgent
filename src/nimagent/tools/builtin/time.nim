## Time Tool - Timestamp Utility
## Useful for logs, reports, timestamps

import ../../utils/async_compat
import ../../utils/json_compat
import ../registry
import std/times

llmTool "Get the current date and time. Returns ISO 8601 formatted timestamp. Useful for logs, reports, and timestamping outputs.":
  proc timeNow(format: string = "ISO8601"): Future[string] {.async.} =
    ## Returns current timestamp
    let now = now()
    case format:
      of "ISO8601":
        return now.format("yyyy-MM-dd'T'HH:mm:sszzz")
      of "RFC2822":
        return now.format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
      of "Unix":
        return $now.toTime().toUnix()
      of "Date":
        return now.format("yyyy-MM-dd")
      of "Time":
        return now.format("HH:mm:ss")
      else:
        return now.format("yyyy-MM-dd HH:mm:ss")
