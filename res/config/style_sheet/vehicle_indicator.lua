require "tableutil"
local ssu = require "stylesheetutil"

function data()
  local result = { }

  local a = ssu.makeAdder(result)

  a(
    "StrictTimetables::LateVehicle",
    {
      color = { 1.0, 0, 0, 0.5 },
      backgroundColor = { 1.0, 0, 0, 0.5 },
      borderColor = { 1.0, 0, 0, 0.5 },
      borderWidth = { 4, 4, 4, 4 }
    }
  )
  a(
    "StrictTimetables::OnTimeVehicle",
    {
      color = { 0, 0, 0, 0 },
      backgroundColor = { 0, 0, 0, 0 },
      borderColor = { 0, 0, 0, 0 },
      borderWidth = { 0, 0, 0, 0 }
    }
  )

  return result
end
