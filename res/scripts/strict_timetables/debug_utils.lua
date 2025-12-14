-- debug_utils.lua
--
-- Debugging utilities.
-- Requires lineUtils and stationUtils to already be included.

debugUtils = {}

-- Return two values:
--  * a bool if the keys in new and old differ;
--  * if the bool is false, then a list of which keys have different values
function debugUtils.printTimetables(timetables)
  print("Timetables:")
  print("===========")
  print("")
  local printedAny = false

  for line, slots in pairs(timetables.timetable) do
    -- Skip timetables that aren't enabled.
    if timetables.enabled[line] then
      printedAny = true
      print("Line " .. tostring(line) .. " (" .. lineUtils.getName(line) .. "):")

      if #slots == 0 then
        print("  no timetable slots")
        print("")
      else
        for slot, stops in pairs(slots) do
          local printedSlot = false
          local stationIds = lineUtils.getStationIds(line)
          for stopId, times in pairs(stops) do
            if times ~= nil then
              local station = stationIds[stopId]
              if not printedSlot then
                print("  Slot " .. tostring(slot) .. ":")
              end
              printedSlot = true
              local minDisp = tostring(times[1])
              if times[1] < 10 then
                minDisp = "0" .. minDisp
              end
              local secDisp = tostring(times[2])
              if times[2] < 10 then
                secDisp = "0" .. secDisp
              end
              print("    Station " .. tostring(station) .. " (" ..
                  stationUtils.getName(station) .. "): " ..  minDisp .. ":" ..
                  secDisp .. ".")
            end
          end

          if not printedSlot then
            print("  Slot " .. tostring(slot) .. ": no timetabled stops.")
          end
        end
      end
    end
  end

  -- Are there any enabled but empty timetables?
  for line, enabled in pairs(timetables.enabled) do
    if not timetables.timetable[line] then
      printedAny = true
      print("Line " .. tostring(line) .. " (" .. lineUtils.getName(line) ..
          "): empty timetable.")
    end
  end

  if not printedAny then
    print("(empty: no timetables for any line)")
    print("")
  end
end

return debugUtils
