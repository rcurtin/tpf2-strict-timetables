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
-- first vehicle on the line.
function lineUtils.getType(line)
  local lineType = api.type.enum.Carrier["RAIL"] -- just an backup...
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

return lineUtils
