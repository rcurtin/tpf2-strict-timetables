-- line_utils.lua
--
-- Helper functions to get information about lines.
-- A lot of these are really trivial wrappers around API calls but it at least
-- helps with the organization a bit.

lineUtils = {}

-- Return the current name of a line as a string.
function lineUtils.getName(line)
  local lineName = api.engine.getComponent(line, api.type.ComponentType.NAME)
  if lineName and lineName.name then
    return lineName.name
  else
    return _("unknown line")
  end
end

-- Return the type of the line (as an api.type.enum.Carrier) by inspecting the
-- first vehicle on the line.  If no vehicles are found, we return -1.
function lineUtils.getType(line)
  local lineType = -1
  local vehicles =
      api.engine.system.transportVehicleSystem.getLineVehicles(line)
  if vehicles and vehicles[1] then
    local component = api.engine.getComponent(vehicles[1],
        api.type.ComponentType.TRANSPORT_VEHICLE)
    if component and component.carrier then
      lineType = component.carrier
    end
  end

  return lineType
end

-- Return a list of stations on a line as a list of station IDs.
-- If a station cannot be looked up, it will not be included on the list.
function lineUtils.getStationIds(line)
  local l = api.engine.getComponent(line, api.type.ComponentType.LINE)
  if not l or not l.stops then
    return {}
  end

  local stationIds = {}
  for i, v in pairs(l.stops) do
    local stationGroup = api.engine.getComponent(v.stationGroup,
        api.type.ComponentType.STATION_GROUP)
    if stationGroup and stationGroup.stations and
       v.station < #stationGroup.stations then
      table.insert(stationIds, stationGroup.stations[v.station + 1])
    end
  end

  return stationIds
end

-- Return a list of station groups on a line as a list of station group IDs.
-- If a station cannot be looked up, it will not be included on the list.
function lineUtils.getStationGroupIds(line)
  local l = api.engine.getComponent(line, api.type.ComponentType.LINE)
  if not l or not l.stops then
    return {}
  end

  local stationGroupIds = {}
  for i, v in pairs(l.stops) do
    table.insert(stationGroupIds, v.stationGroup)
  end

  return stationGroupIds
end

--- Return the number of timetable slots that a line has.
function lineUtils.getNumTimetableSlots(line, timetables)
  if not timetables.timetable[line] then
    timetables.timetable[line] = {}
  end
  return #timetables.timetable[line]
end

--- Return whether or not a line has an enabled timetable.
function lineUtils.hasEnabledTimetable(line, timetables)
  if not timetables.enabled[line] then
    return false
  else
    return timetables.enabled[line]
  end
end

return lineUtils

-- Next thoughts:
--    * actually implement timetabling when it's enabled
--    * augment color codes onto the line table
--
-- Later:
--    * annotate vehicle timetable history?
--    * handle when stations change
--
-- Bugs:
--    * default empty window does not show any lines, you have to click filters
