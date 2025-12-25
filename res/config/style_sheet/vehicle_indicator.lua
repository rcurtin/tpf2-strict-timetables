require "tableutil"
local ssu = require "stylesheetutil"

function data()
  local result = { }

  local a = ssu.makeAdder(result)

  a(
    "Vehicle::Late",
    {
      color = { 1.0, 0, 0, 0.5 },
      backgroundColor = { 1.0, 0, 0, 0.5 }
    }
  )

  return result
end
