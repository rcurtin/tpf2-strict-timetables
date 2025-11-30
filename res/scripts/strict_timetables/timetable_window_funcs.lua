-- timetable_window_funcs.lua
--
-- Functionality related to the GUI window that allows a user to set the
-- timetable.

local miscUtils = require "strict_timetables/misc_utils"
local vehicleUtils = require "strict_timetables/vehicle_utils"
local lineUtils = require "strict_timetables/line_utils"

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

  local newLines = {}
  for k, l in pairs(api.engine.system.lineSystem.getLines()) do
    local lineName = lineUtils.getName(l)
    local lineType = lineUtils.getType(l)
    local hasTimetable = (guiState.timetables.hasTimetable[l] ~= nil)

    -- Check the filters to see if we can add the line.
    if noFilters or guiState.timetableWindow.filters[lineType]:isSelected() then
      -- TODO: actually return some kind of color code here
      table.insert(newLines, { l, "●", lineName, hasTimetable })
    end
  end

  -- Sort the new table of entries in case-independent alphabetical order (like
  -- the line manager).
  table.sort(newLines, function(x, y)
    return string.lower(x[3]) < string.lower(y[3])
  end)

  local anyDifferent, diffKeys = miscUtils.differs(
      guiState.timetableWindow.lineTableList, newLines)
  if anyDifferent then
    -- We have to rebuild the whole list.
    -- Clear the table.
    guiState.timetableWindow.lineTable:deleteRows(0,
        guiState.timetableWindow.lineTable:getNumRows())

    -- Add all of the new rows, and update the line table (don't create a new
    -- one).
    for i, lineData in pairs(newLines) do
      local buttonPath = "ui/checkbox0.tga"
      if lineData[4] == true then
        buttonPath = "ui/checkbox1.tga"
      end
      local buttonImage = api.gui.comp.ImageView.new(buttonPath)
      local button = api.gui.comp.Button.new(buttonImage, true)
      button:setGravity(1, 0.5)
      button:onClick(function()
        if guiState.timetables.hasTimetable[lineData[1]] then
          guiState.timetables.hasTimetable[lineData[1]] = nil
          buttonImage:setImage("ui/checkbox0.tga", false)
        else
          guiState.timetables.hasTimetable[lineData[1]] = true
          buttonImage:setImage("ui/checkbox1.tga", false)
        end
        -- Send a message to the engine state indicating that this line has been
        -- modified.
        table.insert(guiState.callbacks, function()
            api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
                "strict_timetables.lua", "timetable_update", "toggle_timetable",
                { line = lineData[1],
                  value = guiState.timetables.hasTimetable[lineData[1]] }))
        end)
      end)

      local row = { api.gui.comp.TextView.new(lineData[2]),
                    api.gui.comp.TextView.new(lineData[3]),
                    button }
      guiState.timetableWindow.lineTable:addRow(row)
      guiState.timetableWindow.lineTableRows[i] = row
    end
  elseif #diffKeys > 0 then
    -- We only need to update certain rows in the table.
    for k, i in pairs(diffKeys) do
      guiState.timetableWindow.lineTableRows[i][1]:setText(newLines[i][2])
      guiState.timetableWindow.lineTableRows[i][2]:setText(newLines[i][3])
      if newLines[i][4] == true then
        guiState.timetableWindow.lineTableRows[i][3]:setImage(
            "ui/checkbox1.tga", false)
      else
        guiState.timetableWindow.lineTableRows[i][3]:setImage(
            "ui/checkbox0.tga", false)
      end
    end
  end
end

-- Fill the station table for a given line index.
-- (The index refers to the row in the line table.)
function timetableWindowFuncs.refreshStationTable(guiState, index)
  -- First get the line that we are referring to from the color marker, where we
  -- embedded the line ID earlier.
  local lineId =
      tonumber(guiState.timetableWindow.lineTableRows[index][1]:getName())
  local l = api.engine.getComponent(lineId, api.type.ComponentType.LINE)

  -- The first row of the station table contains all of the vehicles that are
  -- not currently assigned to a timeslot.
  local newUnassignedVehicles = {}
  local lineVehiclesMap =
      api.engine.system.transportVehicleSystem.getLine2VehicleMap()
  if lineVehiclesMap and lineVehiclesMap[lineId] then
    for i, vehicle in pairs(lineVehiclesMap[lineId]) do
      table.insert(newUnassignedVehicles, {
          vehicleUtils.getName(vehicle),
          vehicleUtils.getIcon(vehicle),
          vehicleUtils.getStatus(vehicle) })
    end
  else
    -- No vehicles are on this line, so, there is nothing to put in the
    -- unassigned row.
  end

  -- Sort the vehicles by name.
  table.sort(newUnassignedVehicles, function(x, y)
      return string.lower(x[1]) < string.lower(y[1])
  end)

  -- Check to see if any of the unassigned vehicles have changed.
  local anyChanged, changedIndices = miscUtils.differs(
      guiState.timetableWindow.unassignedVehicles, newUnassignedVehicles)
  if anyChanged then
    -- We need to rebuild the list from scratch.
    local iconList = {}
    for i, v in pairs(newUnassignedVehicles) do
      local icon = api.gui.comp.ImageView.new(v[2])
      icon:setTooltip(v[1] .. " (" .. v[3] .. ")")
      table.insert(iconList, icon)
    end

    local newTable = api.gui.comp.Table.new(#iconList + 1, "NONE")
    newTable:addRow({ api.gui.comp.TextView.new(_("unassigned vehicles:")),
        table.unpack(iconList) })

    guiState.timetableWindow.unassignedVehicles = newUnassignedVehicles
    guiState.timetableWindow.unassignedVehiclesIconList = iconList
    guiState.timetableWindow.unassignedVehiclesArea:setContent(newTable)
  elseif #changedIndices > 0 then
    for i, v in pairs(changedIndices) do
      guiState.timetableWindow.unassignedVehiclesIconList[v]:setTooltip(
          newUnassignedVehicles[v][1] .. " (" .. newUnassignedVehicles[v][3] ..
          ")")
    end

    guiState.timetableWindow.unassignedVehicles = newUnassignedVehicles
  end

  -- Now reconstruct the list of stations.
  --local newStations = {}
  --if l and l.stops then
  --  for k, v in pairs(l.stops) do
  --    -- Extract the station name.
  --    local stationNameObject = api.engine.getComponent(v.stationGroup,
  --      api.type.ComponentType.NAME)
  --    local stationName = "ERROR" -- used if no name is found.
  --    if stationNameObject and stationNameObject.name then
  --      stationName = stationNameObject.name
  --    end

  --    -- Insert the station group ID and name.
  --    table.insert(newStations, { v.stationGroup, 

  --    -- Column ideas:
  --    --  * col 1: name of station
  --    --
  --    table.insert(newStations, {
  --        api.gui.comp.TextView.new(tostring(stationName)),
  --        api.gui.comp.TextView.new("test"),
  --        api.gui.comp.TextView.new("test2"),
  --        api.gui.comp.TextView.new("test3")
  --    })
  --  end
  --end

  --anyChanged = false
  --if #newStations ~= #guiState.timetableWindow.stationTableRows then
  --  anyChanged = true
  --else
  --  for i, v in pairs(newStations) do
  --    local oldStation = guiState.timetableWindow.stationTableRows[i]
  --    if v[1]:getText() ~= oldStation[1]:getText() then
  --      anyChanged = true
  --      break
  --    end
  --  end
  --end

  --if anyChanged then
  --  print("changed entries!")
  --  -- Clear the table.
  --  guiState.timetableWindow.stationTable:deleteRows(0,
  --      guiState.timetableWindow.stationTable:getNumRows())

  --  -- Add all of the new rows, and update the line table (don't create a new
  --  -- one).
  --  for i, row in pairs(newStations) do
  --    guiState.timetableWindow.stationTable:addRow(row)
  --    guiState.timetableWindow.stationTableRows[i] = row
  --  end
  --end
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
      -- These are in the same order as enum.Carrier.
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_road_vehicles.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_trains.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/TimetableTramIcon.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_planes.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_ships.tga"))
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
