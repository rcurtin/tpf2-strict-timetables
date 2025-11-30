-- vehicle_utils.lua
--
-- Helper functions to get information about vehicles.
-- A lot of these are really trivial wrappers around API calls but it at least
-- helps with the organization a bit.

vehicleUtils = {}

-- Return the current name of a vehicle as a string.
function vehicleUtils.getName(vehicle)
  local vehicleName = api.engine.getComponent(vehicle,
      api.type.ComponentType.NAME)
  if not vehicleName or not vehicleName.name then
    return "(" .. _("unknown vehicle") .. ")"
  else
    return tostring(vehicleName.name)
  end
end

-- Return the path to an icon image to use for a type of vehicle.
function vehicleUtils.getIcon(vehicle)
  local vehicleInfo = api.engine.getComponent(vehicle,
      api.type.ComponentType.TRANSPORT_VEHICLE)
  local vehicleType = api.type.enum.Carrier["RAIL"] -- default assumption...
  if vehicleInfo and vehicleInfo.carrier then
    vehicleType = vehicleInfo.carrier
  end

  -- Get the icon associated with the vehicle type.
  local imagePath = "ui/icons/game-menu/hud_filter_trains.tga"
  if vehicleType == api.type.enum.Carrier["ROAD"] then
    imagePath = "ui/icons/game-menu/hud_filter_road_vehicles.tga"
  elseif vehicleType == api.type.enum.Carrier["TRAM"] then
    imagePath = "ui/TimetableTramIcon.tga"
  elseif vehicleType == api.type.enum.Carrier["WATER"] then
    imagePath = "ui/icons/game-menu/hud_filter_ships.tga"
  elseif vehicleType == api.type.enum.Carrier["AIR"] then
    imagePath = "ui/icons/game-menu/hud_filter_planes.tga"
  end

  return imagePath
end

-- Return the status of a vehicle as a string.
function vehicleUtils.getStatus(vehicle)
  local vehicleInfo = api.engine.getComponent(vehicle,
      api.type.ComponentType.TRANSPORT_VEHICLE)
  if not vehicleInfo.line then
    return _("not assigned to a line")
  end

  local line = api.engine.getComponent(vehicleInfo.line,
      api.type.ComponentType.LINE)

  if vehicleInfo.userStopped then
    return _("stopped")
  end

  -- Get the name of the station we are heading to or that we are at.
  local nextStationGroupId = line.stops[vehicleInfo.stopIndex + 1].stationGroup
  local nextStationId = line.stops[vehicleInfo.stopIndex + 1].station
  local nextStationGroup = api.engine.getComponent(nextStationGroupId,
      api.type.ComponentType.STATION_GROUP)
  local nextStationName = ""

  if nextStationGroup and nextStationGroup.stations and
      nextStationId < #nextStationGroup.stations then
    nextStationName = api.engine.getComponent(
        nextStationGroup.stations[nextStationId + 1],
        api.type.ComponentType.NAME).name
  end

  if nextStationName == "" then
    if vehicleInfo.state ==
        api.type.enum.TransportVehicleState.AT_TERMINAL then
      return _("stopped at station")
    else
      return _("en route")
    end
  else
    if vehicleInfo.state ==
        api.type.enum.TransportVehicleState.AT_TERMINAL then
      return _("stopped at ") .. nextStationName
    else
      return _("en route to ") .. nextStationName
    end
  end
end

return vehicleUtils
