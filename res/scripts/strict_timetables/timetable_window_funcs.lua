-- timetable_window_funcs.lua
--
-- Functionality related to the GUI window that allows a user to set the
-- timetable.

local miscUtils = require "strict_timetables/misc_utils"
local vehicleUtils = require "strict_timetables/vehicle_utils"
local lineUtils = require "strict_timetables/line_utils"
local stationUtils = require "strict_timetables/station_utils"
local clockFuncs = require "strict_timetables/clock_funcs"

timetableWindowFuncs = {}

timetableWindowFuncs.separationList = {30, 20, 15, 12, 10, 7.5, 6, 5, 4, 3, 2.5,
    2, 1.5, 1.2, 1, 0.5}

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
    local enabled = lineUtils.hasEnabledTimetable(l, guiState.timetables)

    -- Check the filters to see if we can add the line.
    if noFilters or (lineType >= 0 and
       guiState.timetableWindow.filters[lineType + 1]:isSelected()) then
      -- TODO: actually return some kind of color code here
      table.insert(newLines, { l, "●", lineName, enabled })
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
        if lineUtils.hasEnabledTimetable(lineData[1], guiState.timetables) then
          guiState.timetables.enabled[lineData[1]] = nil
          buttonImage:setImage("ui/checkbox0.tga", false)
        else
          guiState.timetables.enabled[lineData[1]] = true
          buttonImage:setImage("ui/checkbox1.tga", false)
        end
        -- Send a message to the engine state indicating that this line has been
        -- modified.
        table.insert(guiState.callbacks, function()
            api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
                "strict_timetables.lua",
                "timetable_update",
                "toggle_timetable",
                {
                  line = lineData[1],
                  value = lineUtils.hasEnabledTimetable(lineData[1],
                      guiState.timetables)
                })) end)
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

--
-- Add a timeslot to the timetable for the given line and stop.
-- The default time will be set to 00:00.
--
function timetableWindowFuncs.addTime(guiState, lineId, stopId, slotId)
  if not guiState.timetables.timetable[lineId] then
    guiState.timetables.timetable[lineId] = {}
  end

  if not guiState.timetables.timetable[lineId][slotId] then
    guiState.timetables.timetable[lineId][slotId] = {}
  end

  guiState.timetables.timetable[lineId][slotId][stopId] = { 0, 0 }
  guiState.timetableWindow.stationTableRowsChanged = true
  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "update_time",
          { line = lineId, stop = stopId, slot = slotId,
            mins = 0, secs = 0 })) end)
end

function timetableWindowFuncs.addTimeslot(guiState)
  -- Determine the line that is currently selected.
  if #guiState.timetableWindow.lineTable:getSelected() ~= 1 then
    -- Can't do anything, no line selected.
    return
  end

  local index = guiState.timetableWindow.lineTable:getSelected()[1]
  local lineId = guiState.timetableWindow.lineTableList[
      guiState.timetableWindow.lineTable:getSelected()[1] + 1][1]
  if guiState.timetables.timetable[lineId] then
    table.insert(guiState.timetables.timetable[lineId], {})
  else
    guiState.timetables.timetable[lineId] = {{}}
  end

  -- Enqueue a message to be sent on callback.  If there already is one, then
  -- increment the number of slots to be added.
  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "add_timeslot",
          { line = lineId })) end)
end

function timetableWindowFuncs.removeTimeslot(guiState, slotId)
  -- Determine the line that is currently selected.
  if #guiState.timetableWindow.lineTable:getSelected() ~= 1 then
    -- Can't do anything, no line selected.
    return
  end

  local index = guiState.timetableWindow.lineTable:getSelected()[1]
  local lineId = guiState.timetableWindow.lineTableList[
      guiState.timetableWindow.lineTable:getSelected()[1] + 1][1]

  -- Remove it from the actual timetables.
  if guiState.timetables.timetable[lineId] and
      slotId <= lineUtils.getNumTimetableSlots(lineId, guiState.timetables) then
    -- Remove the entire slot, shifting all later slots left.
    table.remove(guiState.timetables.timetable[lineId], slotId)
  end

  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "remove_timeslot",
          { line = lineId, slot = slotId })) end)
end

--
-- Modify a timetable using the spinbox.  This is called as a callback whenever
-- the spinboxes are changed.
--
function timetableWindowFuncs.modifyTimeSpinbox(guiState, lineId, stopId,
    slotId, timeInput, minSpinbox, secSpinbox)
  local mins = tostring(minSpinbox:getValue())
  if minSpinbox:getValue() < 10 then
    mins = "0" .. mins
  end

  local secs = tostring(secSpinbox:getValue())
  if secSpinbox:getValue() < 10 then
    secs = "0" .. secs
  end

  local newText = mins .. ":" .. secs
  if timeInput:getText() ~= newText then
    timeInput:setText(newText, false)
  end

  local numMins = tonumber(mins)
  local numSecs = tonumber(secs)
  if not guiState.timetables.timetable[lineId][slotId][stopId] or
      guiState.timetables.timetable[lineId][slotId][stopId][1] ~= numMins or
      guiState.timetables.timetable[lineId][slotId][stopId][2] ~= numSecs then
    guiState.timetables.timetable[lineId][slotId][stopId] = { numMins, numSecs }
    table.insert(guiState.callbacks, function()
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
            "strict_timetables.lua",
            "timetable_update",
            "update_time",
            { line = lineId, slot = slotId, stop = stopId,
              mins = numMins, secs = numSecs })) end)
  end
end

--
-- Modify a timetable entry using the textbox.  This is called as a callback
-- whenever the text of the text input field is changed.
--
function timetableWindowFuncs.modifyTimeText(guiState, lineId, stopId,
    slotId, timeInput, minSpinbox, secSpinbox)
  local timeText = timeInput:getText()
  if string.len(timeText) == 4 then
    timeText = "0" .. timeText
  end
  local validInput = (string.len(timeText) == 5) and
      (string.sub(timeText, 1, 1) >= '0') and
      (string.sub(timeText, 1, 1) <= '5') and
      (string.sub(timeText, 2, 2) >= '0') and
      (string.sub(timeText, 2, 2) <= '9') and
      (string.sub(timeText, 3, 3) == ':') and
      (string.sub(timeText, 4, 4) >= '0') and
      (string.sub(timeText, 4, 4) <= '5') and
      (string.sub(timeText, 5, 5) >= '0') and
      (string.sub(timeText, 5, 5) <= '9')

  if validInput then
    -- Set the spinbox values too, if needed.
    local mins = tonumber(string.sub(timeText, 1, 2))
    local secs = tonumber(string.sub(timeText, 4, 5))

    if minSpinbox:getValue() ~= mins then
      minSpinbox:setValue(mins)
    end
    if secSpinbox:getValue() ~= secs then
      secSpinbox:setValue(secs)
    end

    if not guiState.timetables.timetable[lineId][slotId][stopId] or
        guiState.timetables.timetable[lineId][slotId][stopId][1] ~= mins or
        guiState.timetables.timetable[lineId][slotId][stopId][2] ~= secs then
      guiState.timetables.timetable[lineId][slotId][stopId] = { mins, secs }
      table.insert(guiState.callbacks, function()
          api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
              "strict_timetables.lua",
              "timetable_update",
              "update_time",
              { line = lineId, slot = slotId, stop = stopId,
                mins = mins, secs = secs })) end)
    end
  else
    -- Reset to the current spinbox values.
    timetableWindowFuncs.modifyTimeSpinbox(guiState, lineId, stopId, slotId,
        timeInput, minSpinbox, secSpinbox)
  end
end

function timetableWindowFuncs.modifyMaxLateSpinbox(guiState, lineId)
  local mins = guiState.timetableWindow.maxLatenessMinSpinbox:getValue()
  if mins < 10 then
    mins = "0" .. tostring(mins)
  else
    mins = tostring(mins)
  end

  local secs = guiState.timetableWindow.maxLatenessSecSpinbox:getValue()
  if secs < 10 then
    secs = "0" .. tostring(secs)
  else
    secs = tostring(secs)
  end

  local newText = mins .. ":" .. secs
  if guiState.timetableWindow.maxLatenessText:getText() ~= newText then
    guiState.timetableWindow.maxLatenessText:setText(newText, false)
  end

  local numMins = tonumber(mins)
  local numSecs = tonumber(secs)
  guiState.timetables.maxLateness[lineId] = { min = numMins, sec = numSecs }
  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "update_max_lateness",
          { line = lineId, min = numMins, sec = numSecs })) end)
end

function timetableWindowFuncs.modifyMaxLateText(guiState, lineId)
  local timeText = guiState.timetableWindow.maxLatenessText:getText()
  if string.len(timeText) == 4 then
    timeText = "0" .. timeText
  end
  local validInput = (string.len(timeText) == 5) and
      (string.sub(timeText, 1, 1) >= '0') and
      (string.sub(timeText, 1, 1) <= '5') and
      (string.sub(timeText, 2, 2) >= '0') and
      (string.sub(timeText, 2, 2) <= '9') and
      (string.sub(timeText, 3, 3) == ':') and
      (string.sub(timeText, 4, 4) >= '0') and
      (string.sub(timeText, 4, 4) <= '5') and
      (string.sub(timeText, 5, 5) >= '0') and
      (string.sub(timeText, 5, 5) <= '9')

  if validInput then
    -- Set the spinbox values too, if needed.
    local mins = tonumber(string.sub(timeText, 1, 2))
    local secs = tonumber(string.sub(timeText, 4, 5))

    if guiState.timetableWindow.maxLatenessMinSpinbox:getValue() ~= mins then
      guiState.timetableWindow.maxLatenessMinSpinbox:setValue(mins)
    end
    if guiState.timetableWindow.maxLatenessSecSpinbox:getValue() ~= secs then
      guiState.timetableWindow.maxLatenessSecSpinbox:setValue(secs)
    end

    guiState.timetables.maxLateness[lineId] = { min = mins, sec = secs }
    table.insert(guiState.callbacks, function()
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
            "strict_timetables.lua",
            "timetable_update",
            "update_max_lateness",
            { line = lineId, min = mins, sec = secs })) end)
  else
    -- Reset to the current spinbox values.
    timetableWindowFuncs.modifyMaxLateSpinbox(guiState, lineId)
  end
end

function timetableWindowFuncs.removeTime(guiState, lineId, stopId, slotId)
  if not guiState.timetables.timetable[lineId] then
    return
  end

  if not guiState.timetables.timetable[lineId][stopId] then
    return
  end

  guiState.timetables.timetable[lineId][slotId][stopId] = nil
  guiState.timetableWindow.stationTableRowsChanged = true
  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "remove_time",
          { line = lineId, slot = slotId, stop = stopId })) end)
end

-- Fill the station table for a given line index.
-- (The index refers to the row in the line table.)
function timetableWindowFuncs.refreshStationTable(guiState, index)
  -- Mark the station table as visible, if it's not already.
  if guiState.timetableWindow.stationTable:isVisible() == false then
    guiState.timetableWindow.stationTable:setVisible(true, true)
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
      if (not guiState.timetables.vehicles[vehicle]) or
          (guiState.timetables.vehicles[vehicle].slot == 0) then
        table.insert(newUnassignedVehicles, {
            vehicle,
            vehicleUtils.getName(vehicle),
            vehicleUtils.getIcon(vehicle),
            vehicleUtils.getStatus(vehicle) })
      end
    end
  end

  -- Sort the vehicles by name.
  table.sort(newUnassignedVehicles, function(x, y)
      return string.lower(x[2]) < string.lower(y[2])
  end)

  -- Check to see if any of the unassigned vehicles have changed.
  local anyChanged, changedIndices = miscUtils.differs(
      guiState.timetableWindow.unassignedVehicles, newUnassignedVehicles)
  if anyChanged then
    -- We need to rebuild the list from scratch.
    local iconList = {}
    for i, v in pairs(newUnassignedVehicles) do
      local icon = api.gui.comp.Button.new(api.gui.comp.ImageView.new(v[3]),
          true)
      local vId = v[1]
      icon:onClick(function()
          api.gui.util.getGameUI():getViewManager():openWindow(vId, true, 0)
      end)
      icon:setTooltip(v[2] .. " (" .. v[4] .. ")")
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
          newUnassignedVehicles[v][2] .. " (" .. newUnassignedVehicles[v][4] ..
          ")")
    end

    guiState.timetableWindow.unassignedVehicles = newUnassignedVehicles
  end

  -- Now reconstruct the list of stations.  First, determine if we are now
  -- looking at a new line and need to rebuild the station table.
  local numTimetables = lineUtils.getNumTimetableSlots(lineId,
      guiState.timetables)
  if numTimetables > 0 then
    guiState.timetableWindow.stationDuplicateTable:setVisible(true, true)
  end
  local currentNumTimetables =
      guiState.timetableWindow.stationTable:getNumCols() - 4
  if numTimetables ~= currentNumTimetables then
    guiState.timetableWindow.stationTable:deleteRows(0,
        guiState.timetableWindow.stationTable:getNumRows())
    guiState.timetableWindow.stationTable:setNumCols(4 + numTimetables)
    local i = 0
    while i <= numTimetables do
      -- All timetable columns have width 90 (including the new one).
      guiState.timetableWindow.stationTable:setColWidth(i + 3, 90)
      i = i + 1
    end

    local assignedVehicleWrappers = {}
    local emptyViews = {
        api.gui.comp.TextView.new(""),
        api.gui.comp.TextView.new(""),
        api.gui.comp.TextView.new("")
    }
    while #emptyViews < 3 + numTimetables do
      local assignedVehicleWrapper = api.gui.comp.Component.new(
          "assigned_vehicle_wrapper")
      assignedVehicleWrapper:setGravity(0.5, 0)
      local assignedVehicleLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
      assignedVehicleWrapper:setLayout(assignedVehicleLayout)
      table.insert(assignedVehicleWrappers, assignedVehicleWrapper)

      local removeLabel = api.gui.comp.TextView.new("-")
      removeLabel:setTooltip(_("remove_slot"))
      local removeButton = api.gui.comp.Button.new(removeLabel, true)
      removeButton:setGravity(0.5, 0)
      local slotId = #emptyViews - 2
      removeButton:onClick(function()
          timetableWindowFuncs.removeTimeslot(guiState, slotId)
      end)

      local wrapper = api.gui.comp.Component.new("slot_header_wrapper")
      local wrapperLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
      wrapperLayout:addItem(assignedVehicleWrapper)
      wrapperLayout:addItem(removeButton)
      wrapper:setLayout(wrapperLayout)
      table.insert(emptyViews, wrapper)
    end
    local addButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("+"),
        true)
    addButton:setGravity(0.5, 0.0)
    addButton:onClick(function() timetableWindowFuncs.addTimeslot(guiState) end)

    table.insert(emptyViews, addButton)

    guiState.timetableWindow.stationTable:addRow(emptyViews)
    guiState.timetableWindow.assignedVehicleWrappers = assignedVehicleWrappers

    -- Reset station data.
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
    -- We have to rebuild the table entirely.
    guiState.timetableWindow.stationTable:deleteRows(1,
        guiState.timetableWindow.stationTable:getNumRows())

    -- Add the rows one by one.
    local stationTableRows = {}
    for i, v in pairs(newStationData) do
      local nameLabel = api.gui.comp.TextView.new(v[3])
      nameLabel:setTooltip(v[3])
      local row = { api.gui.comp.TextView.new(tostring(i)),
                    nameLabel,
                    api.gui.comp.TextView.new("") }
      -- Add any actual timetable times that we have.
      if lineUtils.getNumTimetableSlots(lineId, guiState.timetables) > 0 then
        for j, t in pairs(guiState.timetables.timetable[lineId]) do
          if t[i] ~= nil then
            local mins = t[i][1]
            local secs = t[i][2]

            local minStr = tostring(mins)
            if mins < 10 then
              minStr = "0" .. minStr
            end
            local secStr = tostring(secs)
            if secs < 10 then
              secStr = "0" .. secStr
            end

            local time = api.gui.comp.TextInputField.new(
                "StrictTimetable::TimetableEntry")
            time:setText(minStr .. ":" .. secStr, false)
            time:setGravity(0.5, 0.5)

            local minSpinbox = api.gui.comp.SpinBox.new(0, 59, mins)
            minSpinbox:setGravity(0.0, 0.5)
            minSpinbox:getLayout():getItem(0):setVisible(false, false)
            minSpinbox:setMaximumSize(api.gui.util.Size.new(30, 15))
            minSpinbox:setName("StrictTimetable::TimetableSpinbox")
            -- apply minimal style to + and - in the spinbox...
            minSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(
                0):setName("StrictTimetable::TimetableSpinbox")
            minSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(
                0):setName("StrictTimetable::TimetableSpinbox")

            local secSpinbox = api.gui.comp.SpinBox.new(0, 59, secs)
            secSpinbox:setGravity(0.0, 0.5)
            secSpinbox:getLayout():getItem(0):setVisible(false, false)
            secSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(
                0):setName("StrictTimetable::TimetableSpinbox")
            secSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(
                0):setName("StrictTimetable::TimetableSpinbox")

            -- Set the callbacks for when the user does something to modify the
            -- time.
            local slotId = j
            time:onEnter(function()
                timetableWindowFuncs.modifyTimeText(guiState, lineId, i, slotId,
                    time, minSpinbox, secSpinbox)
            end)
            minSpinbox:onChange(function()
                timetableWindowFuncs.modifyTimeSpinbox(guiState, lineId, i,
                    slotId, time, minSpinbox, secSpinbox)
            end)
            secSpinbox:onChange(function()
                timetableWindowFuncs.modifyTimeSpinbox(guiState, lineId, i,
                    slotId, time, minSpinbox, secSpinbox)
            end)

            local removeLabel = api.gui.comp.TextView.new("-")
            removeLabel:setName("StrictTimetable::RemoveButton")
            local removeButton = api.gui.comp.Button.new(removeLabel, true)
            removeButton:setTooltip(_("remove_entry"))
            removeButton:onClick(function()
                timetableWindowFuncs.removeTime(guiState, lineId, i, slotId)
            end)
            local t = api.gui.comp.Table.new(4, 'NONE')
            t:addRow({ minSpinbox, time, secSpinbox, removeButton })
            t:setColWidth(0, 10)
            t:setColWidth(1, 55)
            t:setColWidth(2, 10)
            t:setColWidth(3, 14)
            table.insert(row, t)
          else
            local addButton = api.gui.comp.Button.new(
                api.gui.comp.TextView.new("+"), true)
            addButton:setTooltip(_("add_entry"))
            addButton:setGravity(0.5, 0.5)
            local slotId = j
            addButton:onClick(function()
                timetableWindowFuncs.addTime(guiState, lineId, i, slotId)
            end)
            table.insert(row, addButton)
          end
        end
      end

      -- Add an empty TextView for the last column (the one that lets you add
      -- more timetables).
      table.insert(row, api.gui.comp.TextView.new(""))
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

  -- Update the assigned vehicles, including their tooltips.
  for slot, a in pairs(guiState.timetableWindow.assignedVehicleWrappers) do
    if guiState.timetables.slotAssignments[lineId] and
        guiState.timetables.slotAssignments[lineId][slot] then
      local av = guiState.timetables.slotAssignments[lineId][slot]

      -- Create the ImageView and button if needed.
      if a:getLayout():getNumItems() == 0 then
        local icon = api.gui.comp.Button.new(api.gui.comp.ImageView.new(
            vehicleUtils.getIcon(av)), true)
        icon:setMaximumSize(api.gui.util.Size.new(26, 26))
        icon:onClick(function()
            api.gui.util.getGameUI():getViewManager():openWindow(av, true, 0)
        end)
        icon:setGravity(0.5, 0.5)
        a:getLayout():addItem(icon)
      else
        -- Make sure we have the right image and callback.
        a:getLayout():getItem(0):getLayout():getItem(0):setImage(
            vehicleUtils.getIcon(av), false)
      end

      -- Now construct the tooltip for the vehicle and make sure the click
      -- callback is accurate.
      a:getLayout():getItem(0):onClick(function()
          api.gui.util.getGameUI():getViewManager():openWindow(av, true, 0)
      end)

      local tooltipStr = vehicleUtils.getName(av) .. " (" ..
          vehicleUtils.getStatus(av) .. "): stop " ..
          tostring(guiState.timetables.vehicles[av].stopIndex + 1) ..
          " of " .. tostring(#guiState.timetableWindow.stationTableRows)
      if not guiState.timetables.vehicles[av].late then
        tooltipStr = tooltipStr .. "."
      else
        tooltipStr = tooltipStr .. "; last departure was " ..
            tostring(guiState.timetables.vehicles[av].late.mins) .. "m" ..
            tostring(guiState.timetables.vehicles[av].late.secs) .. "s late."
      end

      if not guiState.timetables.vehicles[av].released then
        local stopIndex = guiState.timetables.vehicles[av].stopIndex + 1
        local depTarget = nil
        if guiState.timetables.timetable[lineId][slot][stopIndex] then
          depTarget = {
              min = guiState.timetables.timetable[lineId][slot][stopIndex][1],
              sec = guiState.timetables.timetable[lineId][slot][stopIndex][2] }
        end

        if depTarget then
          tooltipStr = tooltipStr .. "  Waiting to depart at " ..
              clockFuncs.printClock(depTarget) .. "."
        else
          tooltipStr = tooltipStr .. "  Departing after loading/unloading."
        end
      end

      a:getLayout():getItem(0):setTooltip(tooltipStr)

      -- Tint the background of the icon, if we are late.
      if guiState.timetables.vehicles[av].late then
        a:setName("Vehicle::Late")
      else
        a:setName("Vehicle::OnTime")
      end
    else
      -- Nothing is assigned to this timeslot, so remove any children of the
      -- wrapper.
      while a:getLayout():getNumItems() > 0 do
        a:getLayout():removeItem(a:getLayout():getItem(0))
      end
    end
  end
end

function timetableWindowFuncs.duplicateTimetable(guiState, duplicateCombobox)
  local index = duplicateCombobox:getCurrentIndex()
  if index == -1 then
    return -- Don't apply anything!
  end

  -- Get the currently selected line that we are making a timetable for.
  local lineId = guiState.timetableWindow.lineTableList[
      guiState.timetableWindow.lineTable:getSelected()[1] + 1][1]
  local numTimetables = lineUtils.getNumTimetableSlots(lineId,
      guiState.timetables)
  if numTimetables == 0 then
    -- If there are no slots for this line, well, nothing to do.
    return
  elseif numTimetables > 1 then
    -- Delete all the other slots and their timetables.
    guiState.timetables.timetable[lineId] = {
        guiState.timetables.timetable[lineId][1] }
  end

  local sep = timetableWindowFuncs.separationList[index + 1]
  local sepMins = math.floor(sep)
  local sepSecs = (sep - sepMins) * 60
  local numSlots = math.floor(60 / sep)

  j = 2
  while j <= numSlots do
    guiState.timetables.timetable[lineId][j] = {}
    for s, t in pairs(guiState.timetables.timetable[lineId][1]) do
      guiState.timetables.timetable[lineId][j][s] = t
    end
    -- Modify the time by adding the right increment.
    k = 1
    -- Get the total number of stations.
    while k <= #lineUtils.getStationIds(lineId) do
      if guiState.timetables.timetable[lineId][1][k] then
        local startMin = guiState.timetables.timetable[lineId][1][k][1]
        local startSec = guiState.timetables.timetable[lineId][1][k][2]

        local newMins = (startMin + (j - 1) * sepMins +
            math.floor((startSec + (j - 1) * sepSecs) / 60)) % 60
        local newSecs = (startSec + ((j - 1) * sepSecs)) % 60

        guiState.timetables.timetable[lineId][j][k] = { newMins, newSecs }
      end
      k = k + 1
    end
    j = j + 1
  end

  -- Send update message to engine thread.
  table.insert(guiState.callbacks, function()
      api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
          "strict_timetables.lua",
          "timetable_update",
          "set_timetable",
          {
            line = lineId,
            timetable = guiState.timetables.timetable[lineId]
          })) end)
  guiState.timetableWindow.stationTableRowsChanged = true
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
  lineHeader:setMaximumSize(api.gui.util.Size.new(250, 50))
  lineHeader:setGravity(-1.0, 0.0)

  local lineTable = api.gui.comp.Table.new(3, 'SINGLE')
  lineTable:setColWidth(0, 28)
  lineTable:setColWidth(1, 178)
  lineTable:setColWidth(2, 30)
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
  lineTableScrollArea:setMinimumSize(api.gui.util.Size.new(250, 60))
  --lineTableScrollArea:setMaximumSize(api.gui.util.Size.new(250, 120))
  lineTableScrollArea:setContent(guiState.timetableWindow.lineTable)
  lineTableScrollArea:setGravity(0.0, -1.0)

  -- Create the station table that gets shown when a line is selected.
  local unassignedVehiclesText = api.gui.comp.TextView.new(
      _("unassigned vehicles:"))
  unassignedVehiclesText:setMinimumSize(api.gui.util.Size.new(200, 30))
  unassignedVehiclesText:setMaximumSize(api.gui.util.Size.new(200, 30))
  local unassignedVehiclesArea = api.gui.comp.ScrollArea.new(
      unassignedVehiclesText, "strict_timetable.UnassignedVehicles")
  unassignedVehiclesArea:setGravity(-1.0, 0.0)
  guiState.timetableWindow.unassignedVehiclesArea = unassignedVehiclesArea

  local stationTable = api.gui.comp.Table.new(4, "NONE")
  stationTable:setColWidth(0, 35)
  stationTable:setColWidth(1, 200)
  stationTable:setGravity(-1.0, 0.0)
  local addButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("+"),
      true)
  addButton:setGravity(0.0, 0.0)
  addButton:onClick(function() timetableWindowFuncs.addTimeslot(guiState) end)

  stationTable:addRow({ api.gui.comp.TextView.new(""),
                        api.gui.comp.TextView.new(""),
                        api.gui.comp.TextView.new(""), -- blank filler
                        addButton })
  guiState.timetableWindow.stationTable = stationTable

  -- The station table needs its own scroll box because there could be many
  -- stations.
  local stationScrollArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("StationScrollArea"),
      "strict_timetable.StationOverview")
  stationScrollArea:setMinimumSize(api.gui.util.Size.new(200, 30))
  stationScrollArea:setContent(stationTable)
  stationScrollArea:setGravity(-1.0, -1.0)

  -- If a station has a timetable, this will be how it is duplicated.
  -- Extra columns are appending for setting the maximum lateness before a
  -- train is considered early.
  local stationDuplicateTable = api.gui.comp.Table.new(8, 'NONE')
  stationDuplicateTable:setGravity(0.0, 0.0)
  local stationDuplicateText = api.gui.comp.TextView.new(_("duplicate_text"))
  local stationDuplicateCombobox = api.gui.comp.ComboBox.new()
  for k, v in ipairs(timetableWindowFuncs.separationList) do
    stationDuplicateCombobox:addItem(v .. " min (" .. 60 / v .. "/h)")
  end
  stationDuplicateCombobox:setGravity(1.0, 0.0)
  local stationDuplicateApplyLabel = api.gui.comp.TextView.new(_("apply"))
  stationDuplicateApplyLabel:setTooltip(_("apply_tooltip"))
  local stationDuplicateApply = api.gui.comp.Button.new(
      stationDuplicateApplyLabel, true)
  stationDuplicateApply:setGravity(1.0, 0.0)
  stationDuplicateApply:onClick(function()
      timetableWindowFuncs.duplicateTimetable(guiState,
          stationDuplicateCombobox)
  end)

  -- Spinbox to set the maximum lateness for a line.
  local maxLatenessText = api.gui.comp.TextView.new(_("max_lateness"))
  maxLatenessText:setTooltip(_("max_lateness_tooltip"))
  local maxLatenessTime = api.gui.comp.TextInputField.new(
      "StrictTimetable::TimetableEntry")
  maxLatenessTime:setText("30:00", false)
  maxLatenessTime:setGravity(0.5, 0.5)
  maxLatenessTime:setMaximumSize(api.gui.util.Size.new(50, 30))
  guiState.timetableWindow.maxLatenessText = maxLatenessTime

  local maxLatenessMinSpinbox = api.gui.comp.SpinBox.new(0, 59, 30)
  maxLatenessMinSpinbox:setGravity(0.0, 0.5)
  maxLatenessMinSpinbox:getLayout():getItem(0):setVisible(false, false)
  maxLatenessMinSpinbox:setName("StrictTimetable::TimetableSpinbox")
  -- apply minimal style to + and - in the spinbox...
  maxLatenessMinSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(
      0):setName("StrictTimetable::TimetableSpinbox")
  maxLatenessMinSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(
      0):setName("StrictTimetable::TimetableSpinbox")
  guiState.timetableWindow.maxLatenessMinSpinbox = maxLatenessMinSpinbox

  local maxLatenessSecSpinbox = api.gui.comp.SpinBox.new(0, 59, 0)
  maxLatenessSecSpinbox:setGravity(0.0, 0.5)
  maxLatenessSecSpinbox:getLayout():getItem(0):setVisible(false, false)
  maxLatenessSecSpinbox:getLayout():getItem(1):getItem(0):getLayout():getItem(
      0):setName("StrictTimetable::TimetableSpinbox")
  maxLatenessSecSpinbox:getLayout():getItem(1):getItem(1):getLayout():getItem(
      0):setName("StrictTimetable::TimetableSpinbox")
  guiState.timetableWindow.maxLatenessSecSpinbox = maxLatenessSecSpinbox

  stationDuplicateTable:addRow({ stationDuplicateText, stationDuplicateCombobox,
      stationDuplicateApply, api.gui.comp.TextView.new(""), maxLatenessText,
      maxLatenessMinSpinbox, maxLatenessTime, maxLatenessSecSpinbox })
  stationDuplicateTable:setVisible(false, false)
  guiState.timetableWindow.stationDuplicateTable = stationDuplicateTable

  local lineWrapper = api.gui.comp.Component.new("line_wrapper")
  lineWrapper:setGravity(0.0, -1.0)
  local lineLayout = api.gui.layout.BoxLayout.new("VERTICAL")
  lineLayout:addItem(lineHeader)
  lineLayout:addItem(lineTableScrollArea)
  lineWrapper:setLayout(lineLayout)

  local stationWrapper = api.gui.comp.Component.new("station_wrapper")
  stationWrapper:setGravity(-1.0, 0.0)
  local stationLayout = api.gui.layout.BoxLayout.new("VERTICAL")
  stationLayout:addItem(unassignedVehiclesArea)
  stationLayout:addItem(stationScrollArea)
  stationLayout:addItem(stationDuplicateTable)
  stationWrapper:setLayout(stationLayout)

  local windowWrapper = api.gui.comp.Component.new("window_wrapper")
  windowWrapper:setGravity(-1.0, -1.0)
  local windowLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
  windowLayout:addItem(lineWrapper)
  windowLayout:addItem(stationWrapper)
  windowWrapper:setLayout(windowLayout)

  local debugText = api.gui.comp.TextView.new("D")
  debugText:setTooltip(_("debug_tooltip"))
  local debugButton = api.gui.comp.ToggleButton.new(debugText)
  debugButton:onToggle(function()
    -- Enqueue a callback for the engine to turn on debug mode.
    api.cmd.sendCommand(api.cmd.make.sendScriptEvent(
        "strict_timetables.lua", "toggle_debug", "", {})) end)

  local window = api.gui.comp.Window.new(_("timetables"), windowWrapper)
  window:addHideOnCloseHandler()
  window:setMovable(true)
  window:setPinButtonVisible(true)
  window:setResizable(true)
  window:setSize(api.gui.util.Size.new(1202, 802))
  window:setPosition(200, 200)
  -- Insert debug button just before the pin.
  window:getLayout():getItem(0):getLayout():insertItem(debugButton, 6)
  window:setVisible(false, false)
  guiState.timetableWindow.handle = window
  guiState.timetableWindow.handle:onVisibilityChange(function()
      if guiState.timetableWindow.handle:isVisible() then
        timetableWindowFuncs.refreshLines(guiState)
        if guiState.timetableWindow.stationTable:isVisible() and
            #guiState.timetableWindow.lineTable:getSelected() == 1 then
          timetableWindowFuncs.refreshStationTable(guiState,
              guiState.timetableWindow.lineTable:getSelected()[1] + 1)
        end
      end
  end)

  -- Now we can set the line table callback.
  lineTable:onSelect(function(i)
    if i >= 0 then
      -- Lua is 1-indexed (and so is lineTableRows), but the comp.Table object
      -- returns 0-indexed selections.  Note that we also need to pre-populate
      -- the maximum lateness value.
      local lineId = tonumber(guiState.timetableWindow.lineTableList[i + 1][1])
      if not guiState.timetables.maxLateness[lineId] then
        guiState.timetables.maxLateness[lineId] = { min = 30, sec = 0 }
      end

      local lateStr = clockFuncs.printClock(
          guiState.timetables.maxLateness[lineId])
      if lateStr ~= guiState.timetableWindow.maxLatenessText:getText() then
        guiState.timetableWindow.maxLatenessText:setText(lateStr)
        guiState.timetableWindow.maxLatenessMinSpinbox:setValue(
            guiState.timetables.maxLateness[lineId].min)
        guiState.timetableWindow.maxLatenessSecSpinbox:setValue(
            guiState.timetables.maxLateness[lineId].sec)
      end
      guiState.timetableWindow.maxLatenessText:onEnter(function()
          timetableWindowFuncs.modifyMaxLateText(guiState, lineId) end)
      guiState.timetableWindow.maxLatenessMinSpinbox:onChange(function()
          timetableWindowFuncs.modifyMaxLateSpinbox(guiState, lineId) end)
      guiState.timetableWindow.maxLatenessSecSpinbox:onChange(function()
          timetableWindowFuncs.modifyMaxLateSpinbox(guiState, lineId) end)

      timetableWindowFuncs.refreshStationTable(guiState, i + 1)
    end
  end)

  return
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
    -- We assume the window has been initialized.
    if guiState.timetableWindow.handle:isVisible() then
      guiState.timetableWindow.handle:setVisible(false, false)
    else
      guiState.timetableWindow.handle:setVisible(true, true)
    end
  end)

  return
end

return timetableWindowFuncs
