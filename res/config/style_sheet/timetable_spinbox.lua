require "tableutil"
local ssu = require "stylesheetutil"

function data()
  local result = { }

  local a = ssu.makeAdder(result)

  a(
    "StrictTimetable::TimetableSpinbox",
    {
      margin = { 0, 0, 0, 0 },
      padding = { 0, 0, 0, 0 },
      fontSize = 8
    }
  )

  a(
    "StrictTimetable::RemoveButton",
    {
      margin = { 0, 0, 0, 0 },
      padding = { 0, 5, 0, 5 }
    }
  )

  a(
    "StrictTimetable::TimetableEntry",
    {
      padding = { 0, 2, 0, 2 },
      margin = { 0, 0, 0, 0 }
    }
  )

  return result
end
