-- timetable_window_funcs.lua
--
-- Functionality related to the GUI window that allows a user to set the
-- timetable.

local miscUtils = require "strict_timetables/misc_utils"
local vehicleUtils = require "strict_timetables/vehicle_utils"
local lineUtils = require "strict_timetables/line_utils"
local stationUtils = require "strict_timetables/station_utils"

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
    if noFilters or (lineType >= 0 and
       guiState.timetableWindow.filters[lineType + 1]:isSelected()) then
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
    guiState.timetableWindow.lineTableRows = {}

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
      table.insert(guiState.timetableWindow.lineTableRows, row)
    end

    guiState.timetableWindow.lineTableList = newLines
  elseif #diffKeys > 0 then
    -- We only need to update certain rows in the table.
    for k, i in pairs(diffKeys) do
      guiState.timetableWindow.lineTableList[i] = newLines[i]
      guiState.timetableWindow.lineTableRows[i][1]:setText(newLines[i][2])
      guiState.timetableWindow.lineTableRows[i][2]:setText(newLines[i][3])
      if newLines[i][4] == true then
        guiState.timetableWindow.lineTableRows[i][3]:setContent(
            api.gui.comp.ImageView.new("ui/checkbox1.tga"))
      else
        guiState.timetableWindow.lineTableRows[i][3]:setContent(
            api.gui.comp.ImageView.new("ui/checkbox0.tga"))
      end
    end
  end
end

function timetableWindowFuncs.addTime(guiState, lineId, stopId, slotId)
  print("add time,", tostring(lineId), tostring(stopId), tostring(slotId))
  if not guiState.timetables.timetable[lineId] then
    print("create timetable for line ", tostring(lineId))
    guiState.timetables.timetable[lineId] = {}
  end

  if not guiState.timetables.timetable[lineId][stopId] then
    print("create timetable stop ID ", tostring(stopId))
    guiState.timetables.timetable[lineId][stopId] = {}
  end

  guiState.timetables.timetable[lineId][stopId][slotId] = "test"
  guiState.timetableWindow.stationTableRowsChanged = true
end

function timetableWindowFuncs.modifyTime(guiState, lineId, stopId, slotId,
    timeLabel, hrSpinbox, minSpinbox)

  print("modify time!")
  local hours = tostring(hrSpinbox:getValue())
  if hrSpinbox:getValue() < 10 then
    hours = "0" .. hours
  end

  local mins = tostring(minSpinbox:getValue())
  if minSpinbox:getValue() < 10 then
    mins = "0" .. mins
  end

  timeLabel:setText(hours .. ":" .. mins)

end

-- Fill the station table for a given line index.
-- (The index refers to the row in the line table.)
function timetableWindowFuncs.refreshStationTable(guiState, index)
  -- Mark the station table as visible, if it's not already.
  if guiState.timetableWindow.stationTableVisible == false then
    print(tostring(guiState.timetableWindow.stationTableHeader))
    guiState.timetableWindow.stationTableHeader:addRow({
        guiState.timetableWindow.unassignedVehiclesArea })
    guiState.timetableWindow.stationTableHeader:addRow({
        guiState.timetableWindow.stationTable })
    guiState.timetableWindow.stationTableVisible = true
  end

  -- First get the line that we are referring to from the color marker, where we
  -- embedded the line ID earlier.
  local lineId =
      tonumber(guiState.timetableWindow.lineTableList[index][1])
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
      icon:setGravity(1.0, 0.5)
      table.insert(iconList, icon)
    end

    local newTable = api.gui.comp.Table.new(#iconList + 1, "NONE")
    local unassignedVehiclesText = api.gui.comp.TextView.new(
        _("unassigned vehicles:"))
    unassignedVehiclesText:setMinimumSize(api.gui.util.Size.new(200, 30))
    unassignedVehiclesText:setMaximumSize(api.gui.util.Size.new(200, 30))
    newTable:addRow({ unassignedVehiclesText, table.unpack(iconList) })

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

  -- Now reconstruct the list of stations.  First, determine if we are now
  -- looking at a new line and need to rebuild the station table.
  local numTimetables = lineUtils.getNumTimetableSlots(lineId,
      guiState.timetables)
  local currentNumTimetables =
      guiState.timetableWindow.stationTable:getNumCols() - 3
  if numTimetables ~= currentNumTimetables then
    guiState.timetableWindow.stationTable:deleteRows(0,
        guiState.timetableWindow.stationTable:getNumRows())
    guiState.timetableWindow.stationTable:setNumCols(3 + numTimetables)
    local i = 0
    while i < numTimetables do
      print("set column ", tostring(i))
      guiState.timetableWindow.stationTable:setColWidth(i + 2, 80)
      i = i + 1
    end

    local emptyViews = {}
    while #emptyViews < 2 + numTimetables do
      table.insert(emptyViews, api.gui.comp.TextView.new(""))
      --guiState.timetableWindow.stationTable:setColWidth(1 + #emptyViews, 75)
    end
    local addButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("+"),
      true)
    addButton:setGravity(0.0, 0.0)
    addButton:onClick(function() timetableWindowFuncs.addTimeslot(guiState) end)

    table.insert(emptyViews, addButton)

    guiState.timetableWindow.stationTable:addRow(emptyViews)

    -- MaddButtontation data.
    guiState.timetableWindow.stationTableData = {}
    guiState.timetableWindow.stationTableRows = {}
  end

  local newStations = lineUtils.getStationIds(lineId)
  local newStationGroups = lineUtils.getStationGroupIds(lineId)
  local newStationData = {}
  for i, v in pairs(newStations) do
    table.insert(newStationData,
        { v, newStationGroups[i], stationUtils.getName(newStationGroups[i]) })
  end

  -- Check to see if any station IDs or names have changed.
  anyChanged, changedIndices = miscUtils.differs(
      guiState.timetableWindow.stationTableData, newStationData)
  if anyChanged or guiState.timetableWindow.stationTableRowsChanged then
    print("force rebuild!")
    -- We have to rebuild the table entirely.
    guiState.timetableWindow.stationTable:deleteRows(1,
        guiState.timetableWindow.stationTable:getNumRows())

    -- Add the rows one by one.
    local stationTableRows = {}
    for i, v in pairs(newStationData) do
      local nameLabel = api.gui.comp.TextView.new(v[3])
      nameLabel:setTooltip(v[3])
      local row = { api.gui.comp.TextView.new(tostring(i)),
                    nameLabel }
      -- Add any actual timetable times that we have.
      if guiState.timetables.slots[lineId] then
        local j = 0
        while j < guiState.timetables.slots[lineId] do
          if guiState.timetables.timetable[lineId] and
              guiState.timetables.timetable[lineId][i] ~= nil and
              guiState.timetables.timetable[lineId][i][j] ~= nil then
            print("create selector...")
            local time = api.gui.comp.TextView.new("00:00")
            time:setName("StrictTimetable::TimetableEntry")
            time:setGravity(0.5, 0.5)

            local hrSpinbox = api.gui.comp.SpinBox.new(0, 59, 0)
            hrSpinbox:setGravity(0.0, 0.5)
            print("created spinbox")
            hrSpinbox:getLayout():getItem(0):setVisible(false, false)
            hrSpinbox:setMaximumSize(api.gui.util.Size.new(30, 15))
            hrSpinbox:setName("StrictTimetable::TimetableSpinbox")
            -- apply minimal style to + and - in the spinbox...
            hrSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(0):setName("StrictTimetable::TimetableSpinbox")
            hrSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(0):setName("StrictTimetable::TimetableSpinbox")

            local minSpinbox = api.gui.comp.SpinBox.new(0, 59, 0)
            minSpinbox:setGravity(0.0, 0.5)
            minSpinbox:getLayout():getItem(0):setVisible(false, false)
            minSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(0):setName("StrictTimetable::TimetableSpinbox")
            minSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(0):setName("StrictTimetable::TimetableSpinbox")

            hrSpinbox:onChange(function()
                timetableWindowFuncs.modifyTime(guiState, lineId, i, slotId,
                    time, hrSpinbox, minSpinbox)
            end)
            minSpinbox:onChange(function()
                timetableWindowFuncs.modifyTime(guiState, lineId, i, slotId,
                    time, hrSpinbox, minSpinbox)
            end)

            print("made pieces")
            local removeLabel = api.gui.comp.TextView.new("-")
            removeLabel:setName("StrictTimetable::RemoveButton")
            local removeButton = api.gui.comp.Button.new(removeLabel, true)
            removeButton:setTooltip(_("remove_entry"))
            local t = api.gui.comp.Table.new(4, 'NONE')
            t:addRow({ hrSpinbox, time, minSpinbox, removeButton })
            t:setColWidth(0, 10)
            t:setColWidth(1, 45)
            t:setColWidth(2, 10)
            t:setColWidth(3, 15)
            print("made inner table")
            table.insert(row, t)
            print("done selector")
          else
            local addButton = api.gui.comp.Button.new(
                api.gui.comp.TextView.new("+"), true)
            addButton:setTooltip(_("add_entry"))
            addButton:setGravity(0.5, 0.5)
            local slotId = j
            print("create button with j", tostring(j))
            addButton:onClick(function()
                timetableWindowFuncs.addTime(guiState, lineId, i, slotId)
            end)
            table.insert(row, addButton)
          end

          j = j + 1
        end
      end

      -- Add an empty TextView for the last column (the one that lets you add
      -- more timetables).
      table.insert(row, api.gui.comp.TextView.new(""))
      print("number of elements in row:", tostring(#row))
      guiState.timetableWindow.stationTable:addRow(row)
      table.insert(stationTableRows, row)
    end
    guiState.timetableWindow.stationTableRows = stationTableRows
    guiState.timetableWindow.stationTableData = newStationData
    guiState.timetableWindow.stationTableRowsChanged = false
  elseif #changedIndices > 0 then
    -- Change the labels of the relevant rows.
    for i, v in pairs(changedIndices) do
      guiState.timetableWindow.stationTableRows[v][2]:setText(
          newStationData[v][3])
      guiState.timetableWindow.stationTableRows[v][2]:setTooltip(
          newStationData[v][3])
      guiState.timetableWindow.stationTableData[v] = newStationData[v]
    end
  end
end

function timetableWindowFuncs.addTimeslot(guiState)
  -- Determine the line that is currently selected.
  print("add timeslot")
  if #guiState.timetableWindow.lineTable:getSelected() ~= 1 then
    -- Can't do anything, no line selected.
    print("no line selected...")
    return
  end

  local index = guiState.timetableWindow.lineTable:getSelected()[1]
  print("index", tostring(index))
  print("size of list", tostring(#guiState.timetableWindow.lineTableList))
  local lineId = guiState.timetableWindow.lineTableList[
      guiState.timetableWindow.lineTable:getSelected()[1] + 1][1]
  print("lineId", tostring(lineId))
  print("slots", tostring(guiState.timetables.slots))
  if guiState.timetables.slots and guiState.timetables.slots[lineId] then
    print("there is already something")
    guiState.timetables.slots[lineId] = guiState.timetables.slots[lineId] + 1
    print("incremented to ", guiState.timetables.slots[lineId])
  else
    print("we have nothing yet")
    guiState.timetables.slots[lineId] = 1
    print("incremented to ", guiState.timetables.slots[lineId])
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
  local unassignedVehiclesText = api.gui.comp.TextView.new(
      _("unassigned vehicles:"))
  unassignedVehiclesText:setMinimumSize(api.gui.util.Size.new(200, 30))
  unassignedVehiclesText:setMaximumSize(api.gui.util.Size.new(200, 30))
  local unassignedVehiclesArea = api.gui.comp.ScrollArea.new(
      unassignedVehiclesText, "strict_timetable.UnassignedVehicles")
  unassignedVehiclesArea:setMinimumSize(api.gui.util.Size.new(560, 40))
  unassignedVehiclesArea:setMaximumSize(api.gui.util.Size.new(560, 40))
  guiState.timetableWindow.unassignedVehiclesArea = unassignedVehiclesArea

  local stationTable = api.gui.comp.Table.new(3, "NONE")
  stationTable:setColWidth(0, 35)
  stationTable:setColWidth(1, 200)
  local addButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("+"),
      true)
  addButton:setGravity(0.0, 0.0)
  addButton:onClick(function() timetableWindowFuncs.addTimeslot(guiState) end)

  stationTable:addRow({ api.gui.comp.TextView.new(""),
                        api.gui.comp.TextView.new(""),
                        addButton })

  guiState.timetableWindow.stationTableHeader = stationTableHeader
  guiState.timetableWindow.stationTable = stationTable

  -- The station table needs its own scroll box because there could be many
  -- stations.
  local stationScrollArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("StationScrollArea"),
      "strict_timetable.StationOverview")
  stationScrollArea:setMinimumSize(api.gui.util.Size.new(560, 730))
  stationScrollArea:setMaximumSize(api.gui.util.Size.new(560, 730))
  stationScrollArea:setContent(stationTableHeader)
  guiState.timetableWindow.stationTableVisible = false
  guiState.timetableWindow.stationTableArea = stationScrollArea

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
