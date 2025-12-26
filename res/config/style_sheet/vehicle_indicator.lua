require "tableutil"
local ssu = require "stylesheetutil"

function data()
  local result = { }

  local a = ssu.makeAdder(result)

  a(
    "Vehicle::Late",
    {
      color = { 1.0, 0, 0, 0.5 },
      backgroundColor = { 1.0, 0, 0, 0.5 },
      borderColor = { 1.0, 0, 0, 0.5 },
      borderWidth = { 4, 4, 4, 4 }
    }
  )

  return result
end
