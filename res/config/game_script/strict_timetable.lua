local clockFuncs = require "strict_timetables/clock_funcs"
local timetableWindowFuncs = require "strict_timetables/timetable_window_funcs"
local debugUtils = require "strict_timetables/debug_utils"
local timetableFuncs = require "strict_timetables/timetable_funcs"

local engineState = {
  -- Timetable information.  This is meant to be read only!  The engine thread
  -- should not make any modifications.
  timetables = {
    enabled = {}, -- If enabled[lineId] is true, then the timetable is enabled.
    timetable = {},
    slotAssignments = {}, -- slotAssignments[line][slot] --> vehicle
    vehicles = {}, -- vehicles[v] --> { line, slot, current station }
  },
  -- Whether debugging output is enabled.  Prints the timetable to the log after
  -- every update.
  debug = false
}

-- The clock is controlled by the engine thread.
-- The GUI thread will receive updates passively when load() is called.
local clock = nil

-- State held by the GUI thread.  Members will remain nil on the engine thread.
local guiState = {
  -- The GUI element for the clock.
  clockHandle = nil,
  -- The timetable window and sub-components.
  timetableWindow = {
    -- The handle to the main window.
    handle = nil,
    -- The table object used to list the lines.
    lineTable = nil,
    -- The list of line names in the line table.
    lineTableList = {},
    -- The rows of the line table, for updating.
    lineTableRows = {},
    -- The list of filters that can be applied to the lines.
    filters = nil,
    -- The table holding station and timetable information.
    stationTable = nil,
    -- The table holding information about duplicating timetables.
    stationDuplicateTable = nil,
    -- The area in the station table that holds unassigned vehicles.
    unassignedVehiclesArea = nil,
    -- The list of icons displayed for unassigned vehicles.
    unassignedVehiclesIconList = {},
    -- The current list of unassigned vehicles.
    unassignedVehicles = {},
    -- The Components that hold the assigned vehicle icons.
    assignedVehicleWrappers = {},
    -- The IDs and names of the stations in the station table.
    stationTableData = {},
    -- The rows in the station table.
    stationTableRows = {},
    -- Whether we need to redraw the rows in the station table because something
    -- may have changed.
    stationTableRowsChanged = false
  },
  -- Timetable information for each line.
  timetables = {
    enabled = {}, -- If enabled[lineId] is true, then the timetable is enabled.
    timetable = {},
    slotAssignments = {}
  },
  -- Whether or not the timetable window should always
  -- be refreshed when shown.
  lineManagerOpen = false,
  vehicleManagerOpen = false,
  ticksSinceRefresh = 0,
  -- Callbacks from GUI events that need to be called at the end of a GUI
  -- update.
  callbacks = {},
}

function data()
  return {
    save = function ()
      if clock == nil then
        clock = clockFuncs.initClock()
      end

      return { clock = clock, timetables = engineState.timetables }
    end,

    load = function (loadedState)
      -- On the very first load *only*, set the timetable state.
      -- Past this point, it will be managed entirely by the GUI thread.
      if loadedState and not loadedState.timetables then
        print("Did not get a timetable!!")
      end

      if not clock and loadedState and loadedState.timetables then
        print("Loading saved timetable!")
        engineState.timetables = loadedState.timetables

        if not engineState.timetables.timetable then
          engineState.timetables.timetable = {}
        end

        if not engineState.timetables.slotAssignments then
          engineState.timetables.slotAssignments = {}
        end

        if not engineState.timetables.vehicles then
          engineState.timetables.vehicles = {}
        else
          -- Temporary: make sure we have everything.
          for v, _ in pairs(engineState.timetables.vehicles) do
            if not engineState.timetables.vehicles[v].stopIndex then
              engineState.timetables.vehicles[v].stopIndex = 0
            end
            if not engineState.timetables.vehicles[v].released then
              engineState.timetables.vehicles[v].released = false
            end
          end
        end

        if not engineState.timetables.enabled then
          engineState.timetables.enabled = {}
        end

        -- Initialize variable in case it wasn't saved in the last save.
        if engineState.debug == nil then
          engineState.debug = false
        end

        print(" - Loaded timetable size: " ..
            tostring(#engineState.timetables.timetable))
      end

      -- If we are in the GUI thread, always overwrite any loaded vehicles and
      -- slot assignments, since the engine thread sets them.
      if guiState.timetables then
        if loadedState.timetables and loadedState.timetables.slotAssignments then
          guiState.timetables.slotAssignments = loadedState.timetables.slotAssignments
        end
        if loadedState.timetables and loadedState.timetables.vehicles then
          guiState.timetables.vehicles = loadedState.timetables.vehicles
        end
      end

      -- Update clock state if it was serialized.
      if loadedState and loadedState.clock then
        clock = loadedState.clock
      end
    end,

    update = function()
      if clock == nil then
        clock = clockFuncs.initClock()
      end

      -- Tick the time counter if needed.
      local lastClock = { min = clock.min, sec = clock.sec }
      clock = clockFuncs.updateClock(clock)

      -- Update all vehicles, but only the first time this callback happens
      -- during this second.
      if lastClock.sec ~= clock.sec then
        timetableFuncs.vehicleUpdate(engineState.timetables, clock,
            engineState.debug)
      end
    end,

    guiInit = function()
      print("Initializing the GUI.")
      if not engineState.timetables then
        print("No engine state!!")
      else
        guiState.timetables = engineState.timetables
        if not guiState.timetables.timetable then
          guiState.timetables.timetable = {}
        end
      end
    end,

    guiUpdate = function()
      -- Initialize the clock display if needed.
      if not guiState.clockHandle then
        guiState.clockHandle = clockFuncs.initGUI()
        -- Initialize the array of rows so it can be modified in-place by
        -- subsequent function calls.a
        timetableWindowFuncs.initWindow(guiState)
        timetableWindowFuncs.initButton(guiState)
      end

      if guiState.clockHandle and clock then
        guiState.clockHandle:setText(clockFuncs.printClock(clock))
      end

      -- If we could be modifying lines or vehicles, we need to refresh the
      -- timetable window.
      if guiState.timetableWindow.handle:isVisible() and
         (guiState.lineManagerOpen or guiState.vehicleManagerOpen) then
        -- Only refresh every 5 GUI ticks.
        guiState.ticksSinceRefresh = (guiState.ticksSinceRefresh + 1) % 5
        if guiState.ticksSinceRefresh == 0 then
          timetableWindowFuncs.refreshLines(guiState)
          if #guiState.timetableWindow.lineTable:getSelected() == 1 then
            timetableWindowFuncs.refreshStationTable(guiState,
                -- For whatever reason the UI component is 0-indexed but Lua is
                -- 1-indexed...
                (guiState.timetableWindow.lineTable:getSelected()[1] + 1))
          elseif guiState.timetableWindow.stationTable:isVisible() then
            -- No station is selected, so disable the station table.
            guiState.timetableWindow.stationTable:setVisible(false, false)
          end
        end
      elseif guiState.timetableWindow.handle:isVisible() then
        -- If the window is open and the station table is being shown, we need
        -- to refresh it (since vehicle move).  We'll do it every 20 ticks.
        guiState.ticksSinceRefresh = (guiState.ticksSinceRefresh + 1) % 20
        if guiState.ticksSinceRefresh == 0 then
          if #guiState.timetableWindow.lineTable:getSelected() == 1 then
            timetableWindowFuncs.refreshStationTable(guiState,
                -- For whatever reason the UI component is 0-indexed but Lua is
                -- 1-indexed...
                (guiState.timetableWindow.lineTable:getSelected()[1] + 1))
          elseif guiState.timetableWindow.stationTable:isVisible() then
            -- No station is selected, so disable the station table.
            guiState.timetableWindow.stationTable:setVisible(false, false)
          end
        end
      end

      -- Call any callbacks that are needed from the update.
      for k, v in pairs(guiState.callbacks) do
          v()
      end
      guiState.callbacks = {}
    end,

    handleEvent = function (src, id, name, param)
      -- Receive messages from the GUI thread on the engine thread.  These are
      -- updates to the timetable.
      if src ~= "strict_timetables.lua" then
        return
      end

      if id == "timetable_update" then
        if name == "toggle_timetable" then
          print("Engine: toggle timetable for line " ..
              tostring(param.line) .. ": " .. tostring(param.value) .. ".")
          if param.value == true then
            engineState.timetables.enabled[param.line] = param.value
          else
            engineState.timetables.enabled[param.line] = nil -- Remove when false.
          end
          print("Engine: toggle complete.")

        elseif name == "add_timeslot" then
          if not engineState.timetables.timetable[param.line] then
            engineState.timetables.timetable[param.line] = {{}}
          else
            table.insert(engineState.timetables.timetable[param.line], {})
          end

          print("Engine: set number of timetable slots for line " ..
              tostring(param.line) ..  " to " ..
              tostring(lineUtils.getNumTimetableSlots(param.line,
                  engineState.timetables)) .. ".")

        elseif name == "remove_timeslot" then
          if not engineState.timetables.timetable[param.line] then
            return -- Invalid message...?
          end

          if param.slot <= lineUtils.getNumTimetableSlots(param.line,
              engineState.timetables) then
            table.remove(engineState.timetables.timetable[param.line],
                param.slot)
          end

          print("Engine: remove slot " .. tostring(param.slot) .. " from " ..
              "timetables for line " .. tostring(param.line) .. ".")

          timetableFuncs.shiftVehiclesForRemovedSlot(engineState.timetables,
              param.line, param.slot)

        elseif name == "update_time" then
          if not engineState.timetables.timetable[param.line] then
            engineState.timetables.timetable[param.line] = {}
          end

          if not engineState.timetables.timetable[param.line][param.slot] then
            engineState.timetables.timetable[param.line][param.slot] = {}
          end

          engineState.timetables.timetable[param.line][param.slot][param.stop] =
              { param.mins, param.secs }
          print("Engine: set slot " .. tostring(param.slot) .. " stop " ..
              tostring(param.stop) .. " on line " .. tostring(param.line) ..
              " to " .. tostring(param.mins) .. "m" .. tostring(param.secs) ..
              "s.")

          -- Any assigned vehicles that are waiting will simply start getting a
          -- different target departure time in the update step.

        elseif name == "remove_time" then
          if not engineState.timetables.timetable[param.line] then
            return
          elseif not engineState.timetables.timetable[
              param.line][param.slot] then
            return
          else
            engineState.timetables.timetable[
                param.line][param.slot][param.stop] = nil
          end
          print("Engine: remove slot " .. tostring(param.slot) .. " stop " ..
              tostring(param.stop) .. " on " .. tostring(param.line) .. ".")

          -- Any assigned vehicles that are waiting will simply start getting
          -- nil for the target departure time in the update step, at which
          -- point they will be released.

        elseif name == "set_timetable" then
          engineState.timetables.timetable[param.line] = param.timetable
          print("Engine: set timetable for line " .. tostring(param.line) .. ".")

          -- If we overwrote the timetable, any vehicles waiting on the first
          -- release may need to be re-assigned.
          timetableFuncs.resetVehiclesOnLine(engineState.timetables, param.line)
        end

      elseif id == "toggle_debug" then
        if engineState.debug then
          print("Engine: toggle debug mode off.")
          engineState.debug = false
        else
          print("Engine: toggle debug mode on.")
          engineState.debug = true
        end
      end

      if engineState.debug then
        debugUtils.printTimetables(engineState.timetables)
      end
    end,

    guiHandleEvent = function (id, name, param)
      if id == "menu.lineManager" and name == "toggleButton.toggle" then
        -- When the line manager window is open, we always refresh.
        guiState.lineManagerOpen = param
      end

      if id == "menu.vehicleManager" and name == "toggleButton.toggle" then
        -- When the vehicle manager window is open, we always refresh.
        guiState.vehicleManagerOpen = param
      end
    end
  }
end

-- Features to implement:
--  * notifications when a vehicle departs late?
--  * allow configurable maximum lateness for a line
