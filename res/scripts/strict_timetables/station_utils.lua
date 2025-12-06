-- station_utils.lua
--
-- Helper functions to get information about stations.
-- A lot of these are really trivial wrappers around API calls but it at least
-- helps with the organization a bit.

stationUtils = {}

-- Return the name of a station.
function stationUtils.getName(stationGroup)
  local name = api.engine.getComponent(stationGroup,
      api.type.ComponentType.NAME)
  if not name or not name.name then
    return _("unknown station")
  else
    return tostring(name.name)
  end
end

return stationUtils
