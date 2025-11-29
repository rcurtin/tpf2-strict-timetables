local clockFuncs = require "strict_timetables/clock_funcs"
local timetableWindowFuncs = require "strict_timetables/timetable_window_funcs"

local engineState = {
  -- Timetable information.  This is meant to be read only!  The engine thread
  -- should not make any modifications.
  timetables = {
    hasTimetable = {}, -- Lookup table mapping bools to internal line IDs.
    lineStationHasTimetable = {} -- Lookup table mapping (line ID, station ID)
                                 -- to whether it is timetabled.
  }
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
    -- The rows in the line table.
    lineTableRows = {},
    -- The list of filters that can be applied to the lines.
    filters = nil,
    -- The table holding stations and line information.
    stationTable = nil,
    -- The rows in the station table.
    stationTableRows = {},
    -- The area in the station table that holds unassigned vehicles.
    unassignedVehiclesArea = nil,
    -- The current list of unassigned vehicles.
    unassignedVehicles = {}
  },
  -- Timetable information for each line.
  timetables = {
    hasTimetable = {}, -- Lookup table mapping internal line IDs to bools.
    lineStationHasTimetable = {} -- Lookup table mapping (line ID, station ID)
                                 -- to whether it is timetabled.
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
      clock = clockFuncs.updateClock(clock)
    end,

    guiInit = function()
      print("Initializing the GUI.")
      if not engineState.timetables then
        print("No engine state!!")
      else
        guiState.timetables = engineState.timetables
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
          end
        end
      elseif guiState.timetableWindow.handle:isVisible() then
        -- If the window is open and the station table is being shown, we need
        -- to refresh it (since vehicle move).  We'll do it every 20 ticks.
        guiState.ticksSinceRefresh = (guiState.ticksSinceRefresh + 1) % 20
        if guiState.ticksSinceRefresh == 0 then
          print("attempt to refresh")
          if #guiState.timetableWindow.lineTable:getSelected() == 1 then
            print("a line is selected")
            timetableWindowFuncs.refreshStationTable(guiState,
                -- For whatever reason the UI component is 0-indexed but Lua is
                -- 1-indexed...
                (guiState.timetableWindow.lineTable:getSelected()[1] + 1))
          end
        end
      end

      -- Call any callbacks that are needed from the update.
      for k, v in pairs(guiState.callbacks) do
          print("Going to do a callback!")
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
          engineState.timetables.hasTimetable[param.line] = param.value
        end
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
