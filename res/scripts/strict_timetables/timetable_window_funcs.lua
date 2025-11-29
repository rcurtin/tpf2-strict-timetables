-- timetable_window_funcs.lua
--
-- Functionality related to the GUI window that allows a user to set the
-- timetable.

timetableWindowFuncs = {}

-- Add all of the lines to the line table, using the states of the given filters
-- to select which lines are displayed.  The existing rows in the line table
-- must be stored in the GUI state because it seems there is no way to recover
-- these from `lineTable` directly.
function timetableWindowFuncs.refreshLines(guiState)

  -- Extract the values of the filters.
  -- 1: bus; 2: tram; 3: rail; 4: water; 5: air
  local noFilters = not guiState.timetableWindow.filters[1]:isSelected() and
                    not guiState.timetableWindow.filters[2]:isSelected() and
                    not guiState.timetableWindow.filters[3]:isSelected() and
                    not guiState.timetableWindow.filters[4]:isSelected() and
                    not guiState.timetableWindow.filters[5]:isSelected()

  local newRows = {}
  for k, l in pairs(api.engine.system.lineSystem.getLines()) do
    local lineName = api.engine.getComponent(l, api.type.ComponentType.NAME)
    local lineLabel = "ERROR" -- used if we can't find a real name for it.
    if lineName and lineName.name then
      lineLabel = lineName.name
    end

    -- Get the type of vehicle on the line.
    local lineType = nil
    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(l)
    if vehicles and vehicles[1] then
      local component = api.engine.getComponent(vehicles[1],
          api.type.ComponentType.TRANSPORT_VEHICLE)
      if component and component.carrier then
        lineType = component.carrier
      end
    end

    -- Check the filters to see if we can add the line.
    local add = noFilters or
      (guiState.timetableWindow.filters[1]:isSelected() and
       lineType == api.type.enum.Carrier["ROAD"]) or
      (guiState.timetableWindow.filters[2]:isSelected() and
       lineType == api.type.enum.Carrier["TRAM"]) or
      (guiState.timetableWindow.filters[3]:isSelected() and
       lineType == api.type.enum.Carrier["RAIL"]) or
      (guiState.timetableWindow.filters[4]:isSelected() and
       lineType == api.type.enum.Carrier["WATER"]) or
      (guiState.timetableWindow.filters[5]:isSelected() and
       lineType == api.type.enum.Carrier["AIR"])
    if add then
      local color = api.gui.comp.TextView.new("●")
      --color:setName("strict_timetable-color-test")
      -- Embed the line ID as the name of the color marker.
      color:setName(tostring(l))

      local buttonImage = api.gui.comp.ImageView.new("ui/checkbox0.tga")
      -- Determine whether or not the line has a timetable.
      if guiState.timetables.hasTimetable[l] then
        buttonImage:setImage("ui/checkbox1.tga", false)
      end

      local button = api.gui.comp.Button.new(buttonImage, true)
      button:setGravity(1, 0.5)
      button:onClick(function()
        if guiState.timetables.hasTimetable[l] then
          guiState.timetables.hasTimetable[l] = nil
          buttonImage:setImage("ui/checkbox0.tga", false)
        else
          guiState.timetables.hasTimetable[l] = true
          buttonImage:setImage("ui/checkbox1.tga", false)
        end
        -- Send a message to the engine state indicating that this line has been
        -- modified.
        table.insert(guiState.callbacks, function()
            api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
                "strict_timetables.lua", "timetable_update", "toggle_timetable",
                { line = l, value = guiState.timetables.hasTimetable[l] }))
        end)
      end)

      table.insert(newRows,
          { color, api.gui.comp.TextView.new(lineLabel), button })
    end
  end

  -- Sort the new table of entries in alphabetical order.
  table.sort(newRows, function(x, y)
      return string.lower(x[2]:getText()) < string.lower(y[2]:getText())
  end)

  -- Only update the table if any entries have changed.
  local anyDifferent = false
  if not guiState.timetableWindow.lineTableRows or
      #newRows ~= #guiState.timetableWindow.lineTableRows then
    anyDifferent = true
  else
    for i, row in pairs(newRows) do
      oldRow = guiState.timetableWindow.lineTableRows[i]
      -- Check the color label.
      if oldRow[1]:getText() ~= row[1]:getText() then
        anyDifferent = true
        break
      end

      -- Check the ID of the line (embedded as the name of the color marker).
      if oldRow[1]:getName() ~= row[1]:getName() then
        anyDifferent = true
        break
      end

      -- Check the name of the line.
      if oldRow[2]:getText() ~= row[2]:getText() then
        anyDifferent = true
        break
      end
    end
  end

  if anyDifferent then
    -- Clear the table.
    guiState.timetableWindow.lineTable:deleteRows(0,
        guiState.timetableWindow.lineTable:getNumRows())

    -- Add all of the new rows, and update the line table (don't create a new
    -- one).
    for i, row in pairs(newRows) do
      guiState.timetableWindow.lineTable:addRow(row)
      guiState.timetableWindow.lineTableRows[i] = row
    end
  end

  return
end

-- Fill the station table for a given line index.
-- (The index refers to the row in the line table.)
function timetableWindowFuncs.refreshStationTable(guiState, index)
  -- First get the line that we are referring to from the color marker, where we
  -- embedded the line ID earlier.
  print("Fill station table for index", tostring(index))
  print("Name of table row: ", tostring(guiState.timetableWindow.lineTableRows[index][1]:getName()))
  local lineId =
      tonumber(guiState.timetableWindow.lineTableRows[index][1]:getName())
  print("Line ID: ", tostring(lineId))
  local l = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
  print("Got the line, ", tostring(l))

  -- The first row of the station table contains all of the vehicles that are
  -- not currently assigned to a timeslot.
  local newUnassignedVehicles = {}
  local lineVehiclesMap =
      api.engine.system.transportVehicleSystem.getLine2VehicleMap()
  if lineVehiclesMap and lineVehiclesMap[lineId] then
    for i, vehicle in pairs(lineVehiclesMap[lineId]) do
      local vehicleName = api.engine.getComponent(vehicle,
          api.type.ComponentType.NAME)
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

      -- Get the vehicle's current status: is it stopped at a station?  Or by
      -- the user?  Where is it en route to?
      local vehicleStatus = ""
      if vehicleInfo.userStopped then
        vehicleStatus = _(" (stopped)")
      else
        -- Get the name of the station we are heading to or that we are at.
        local nextStationGroupId =
            l.stops[vehicleInfo.stopIndex + 1].stationGroup
        local nextStationId = l.stops[vehicleInfo.stopIndex + 1].station
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
            vehicleStatus = _(" (stopped at station)")
          else
            vehicleStatus = _(" (en route)")
          end
        else
          if vehicleInfo.state ==
              api.type.enum.TransportVehicleState.AT_TERMINAL then
            vehicleStatus = _(" (stopped at ") .. nextStationName .. ")"
          else
            vehicleStatus = _(" (en route to ") .. nextStationName .. ")"
          end
        end
      end

      print("vehicle status: ", tostring(vehicleStatus))
      vehicleImage = api.gui.comp.ImageView.new(imagePath)
      -- We can't recover the tooltip later for comparison, so set it as the ID
      -- too.  Set the vehicle ID as the name.
      vehicleImage:setName(tostring(vehicle) .. " " ..
          tostring(vehicleName.name) .. vehicleStatus)
      vehicleImage:setTooltip(tostring(vehicleName.name) .. vehicleStatus)
      table.insert(newUnassignedVehicles, vehicleImage)
    end
  else
    -- No vehicles are on this line, so, there is nothing to put in the
    -- unassigned row.
  end

  -- Sort the vehicles by name. (TODO)

  -- Check to see if any of the unassigned vehicles have changed.
  local anyChanged = false
  local anyStatusesChanged = false
  local statusesChanged = {} -- if the vehicles themselves did not change
  if #newUnassignedVehicles ~= #guiState.timetableWindow.unassignedVehicles then
    anyChanged = true
  else
    for i, v in pairs(newUnassignedVehicles) do
      local oldVehicle = guiState.timetableWindow.unassignedVehicles[i]

      local vSplit, _ = string.find(v:getName(), " ", 1, true)
      local oSplit, _ = string.find(oldVehicle:getName(), " ", 1, true)
      if vSplit and vSplit > 1 and oSplit and oSplit > 1 then
        -- Split the strings into components.
        local vId = string.sub(v:getName(), 1, vSplit - 1)
        local oId = string.sub(oldVehicle:getName(), 1, oSplit - 1)

        local vTooltip = string.sub(v:getName(), vSplit + 1)
        local oTooltip = string.sub(oldVehicle:getName(), oSplit + 1)

        if vId ~= oId then
          anyChanged = true -- The vehicle IDs don't match; so rebuild it all.
          break
        elseif vTooltip ~= oTooltip then
          -- The tooltip changed, so we just need to update that.
          anyStatusesChanged = true
          statusesChanged[vId] = i
        end
      else
        anyChanged = true -- Not sure what happened, just force a refresh.
        break
      end
    end
  end

  if anyChanged then
    -- Update the display of unassigned vehicles.
    newTable = api.gui.comp.Table.new(#newUnassignedVehicles + 1, "NONE")
    newTable:addRow({ api.gui.comp.TextView.new(_("unassigned vehicles:")),
        table.unpack(newUnassignedVehicles) })
    guiState.timetableWindow.unassignedVehiclesArea:setContent(newTable)
    guiState.timetableWindow.unassignedVehicles = newUnassignedVehicles
  elseif anyStatusesChanged then
    -- Iterate to find the vehicles we need to update.
    for i, v in pairs(guiState.timetableWindow.unassignedVehicles) do
      local vSplit, _ = string.find(v:getName(), " ", 1, true)
      if vSplit and vSplit > 1 then
        local vId = string.sub(v:getName(), 1, vSplit - 1)
        local si = statusesChanged[vId]
        if si then
          local sSplit, _ = string.find(newUnassignedVehicles[si]:getName())
          if sSplit and sSplit > 1 then
            v:setName(newUnassignedVehicles[si]:getName())
            v:setTooltip(string.sub(newUnassignedVehicles[si]:getName(),
                sSplit + 1))
          end
        end
      end -- Not sure what to do otherwise... just leave it non-updated...
    end
  end

  -- Now reconstruct the list of stations.
  local newStations = {}
  if l and l.stops then
    for k, v in pairs(l.stops) do
      -- Extract the station name.
      local stationNameObject = api.engine.getComponent(v.stationGroup,
        api.type.ComponentType.NAME)
      local stationName = "ERROR" -- used if no name is found.
      if stationNameObject and stationNameObject.name then
        stationName = stationNameObject.name
      end

      -- Column ideas:
      --  * col 1: checkbox if station is timetabled
      --  * col 2: name of station
      --
      table.insert(newStations, {
          api.gui.comp.TextView.new(tostring(stationName)),
          api.gui.comp.TextView.new("test"),
          api.gui.comp.TextView.new("test2"),
          api.gui.comp.TextView.new("test3")
      })
    end
  end

  anyChanged = false
  if #newStations ~= #guiState.timetableWindow.stationTableRows then
    anyChanged = true
  else
    for i, v in pairs(newStations) do
      local oldStation = guiState.timetableWindow.stationTableRows[i]
      if v[1]:getText() ~= oldStation[1]:getText() then
        anyChanged = true
        break
      end
    end
  end

  if anyChanged then
    print("changed entries!")
    -- Clear the table.
    guiState.timetableWindow.stationTable:deleteRows(0,
        guiState.timetableWindow.stationTable:getNumRows())

    -- Add all of the new rows, and update the line table (don't create a new
    -- one).
    for i, row in pairs(newStations) do
      guiState.timetableWindow.stationTable:addRow(row)
      guiState.timetableWindow.stationTableRows[i] = row
    end
  end
end

-- Initialize the window: create all the tabs and other structure that will be
-- filled when clicked.
--
-- Returns a table that has the same schema as 'timetableWindow' described in
-- the main mod file.
function timetableWindowFuncs.initWindow(guiState)
  -- We have to build the components here from the inside to the outside.
  -- So, at the innermost level, let's start with the actual table that contains
  -- the lines.
  local lineHeader = api.gui.comp.Table.new(6, 'None')
  guiState.timetableWindow.filters = {
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_road_vehicles.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/TimetableTramIcon.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_trains.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_ships.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_planes.tga")),
  }
  lineHeader:addRow({ api.gui.comp.TextView.new(_("filter:")),
      table.unpack(guiState.timetableWindow.filters) })

  local lineTable = api.gui.comp.Table.new(3, 'SINGLE')
  lineTable:setColWidth(0, 28)
  lineTable:onSelect(function(i)
    if i >= 0 then
      print("Selected line index ", tostring(i), "!")
      -- Lua is 1-indexed (and so is lineTableRows), but the comp.Table object
      -- returns 0-indexed selections.
      timetableWindowFuncs.refreshStationTable(guiState, i + 1)
    end
  end)
  guiState.timetableWindow.lineTable = lineTable

  -- Set up callbacks for all of the filters.
  for i, f in pairs(guiState.timetableWindow.filters) do
    f:onToggle(function() timetableWindowFuncs.refreshLines(guiState) end)
  end
  -- Rebuild the elements of the table with no filter.
  timetableWindowFuncs.refreshLines(guiState)
  print("done refreshing lines")

  -- Now create a scroll area to wrap the table, since there could be many
  -- lines.
  local lineTableScrollArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("LineOverview"),
      "strict_timetable.LineOverview")
  lineTableScrollArea:setMinimumSize(api.gui.util.Size.new(320, 690))
  lineTableScrollArea:setMaximumSize(api.gui.util.Size.new(320, 690))
  lineTableScrollArea:setContent(guiState.timetableWindow.lineTable)

  -- Create the station table that gets shown when a line is selected.
  local stationTableHeader = api.gui.comp.Table.new(1, 'NONE')
  local unassignedVehiclesArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("Unassigned vehicles"),
      "strict_timetable.UnassignedVehicles")
  unassignedVehiclesArea:setMinimumSize(api.gui.util.Size.new(560, 80))
  unassignedVehiclesArea:setMaximumSize(api.gui.util.Size.new(560, 80))
  guiState.timetableWindow.unassignedVehiclesArea = unassignedVehiclesArea

  local stationTable = api.gui.comp.Table.new(4, 'SINGLE')
  stationTable:setColWidth(0, 40)
  stationTable:setColWidth(1, 120)

  stationTableHeader:addRow({ unassignedVehiclesArea })
  stationTableHeader:addRow({ stationTable })

  guiState.timetableWindow.stationTable = stationTable

  -- The station table needs its own scroll box because there could be many
  -- stations.
  local stationScrollArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("StationScrollArea"),
      "strict_timetable.StationOverview")
  stationScrollArea:setMinimumSize(api.gui.util.Size.new(560, 730))
  stationScrollArea:setMaximumSize(api.gui.util.Size.new(560, 730))
  stationScrollArea:setContent(stationTableHeader)

  -- Next we need a layout to use for the wrapper...
  local lineTabLayout = api.gui.layout.FloatingLayout.new(0, 1)
  lineTabLayout:setId("strict_timetable.lineTabLayout")
  lineTabLayout:setGravity(-1, -1)
  lineTabLayout:addItem(lineHeader, 0, 0)
  lineTabLayout:addItem(lineTableScrollArea, 0, 1)
  lineTabLayout:addItem(stationScrollArea, 0.5, 0)

  -- Next we need a wrapper for the content of the tab.
  local lineTab = api.gui.comp.Component.new("wrapper")
  lineTab:setLayout(lineTabLayout)

  local tabWidget = api.gui.comp.TabWidget.new("NORTH")
  tabWidget:addTab(api.gui.comp.TextView.new(_("lines")), lineTab)
  --tabWidget:onCurrentChanged(function(i)
  --  print("Changed tab to ", tostring(i))
  --  if i == 0 then
  --    timetableWindowFuncs.
  --  end
  --end)

  local window = api.gui.comp.Window.new(_("timetables"), tabWidget)
  window:addHideOnCloseHandler()
  window:setMovable(true)
  window:setPinButtonVisible(true)
  window:setResizable(true)
  window:setSize(api.gui.util.Size.new(1202, 802))
  window:setPosition(200, 200)
  window:setVisible(false, false)
  guiState.timetableWindow.handle = window

  return
end

-- Open the window.
function timetableWindowFuncs.showWindow(window)
  if not window then
    print("Attempted to show window but it was nil!")
  else
    window:setVisible(true, true)
  end
end

-- Create the button on the main GUI (to the right of the clock) that a user can
-- click on to open the timetable window dialog.
function timetableWindowFuncs.initButton(guiState)
  -- Now create a button for the timetable.
  local line = api.gui.comp.Component.new("VerticalLine")
  local buttonLabel = gui.textView_create(
      "gameInfo.strict_timetables.button_label",
      _("timetable"))
  local button = gui.button_create("gameInfo.strict_timetables.button",
      buttonLabel)

  local gameInfoLayout = api.gui.util.getById("gameInfo"):getLayout()
  gameInfoLayout:addItem(line)
  game.gui.boxLayout_addItem("gameInfo.layout", button.id)
  button:onClick(function ()
    local status, err = pcall(timetableWindowFuncs.showWindow,
        guiState.timetableWindow.handle)
    if not status then
      print(err)
    end
  end)

  return
end

return timetableWindowFuncs
