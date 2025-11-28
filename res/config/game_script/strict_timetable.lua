local clockFuncs = require "strict_timetables/clock_funcs"
local timetableWindowFuncs = require "strict_timetables/timetable_window_funcs"

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
    lineTableRows = nil,
    -- The list of filters that can be applied to the lines.
    filters = nil
  },
  -- Whether or not the timetable window should always
  -- be refreshed when shown.
  alwaysRefresh = false,
  ticksSinceRefresh = 0
}

function data()
  return {
    save = function ()
      if clock == nil then
        clock = clockFuncs.initClock()
      end

      return { clock = clock }
    end,

    load = function (loadedState)
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

    guiUpdate = function()
      -- Initialize the clock display if needed.
      if not guiState.clockHandle then
        guiState.clockHandle = clockFuncs.initGUI()
        -- Initialize the array of rows so it can be modified in-place by
        -- subsequent function calls.
        guiState.timetableWindow.lineTableRows = {}
        guiState.timetableWindow = timetableWindowFuncs.initWindow(
            guiState.timetableWindow.lineTableRows) -- lineTableRows will be set
        timetableWindowFuncs.initButton(guiState.timetableWindow.handle)
      end

      if guiState.clockHandle and clock then
        guiState.clockHandle:setText(clockFuncs.printClock(clock))
      end

      -- If we could be modifying lines or vehicles, we need to refresh the
      -- timetable window.
      if guiState.timetableWindow.handle:isVisible() and
         guiState.alwaysRefresh then
        -- Only refresh every 5 GUI ticks.
        guiState.ticksSinceRefresh = (guiState.ticksSinceRefresh + 1) % 5
        if guiState.ticksSinceRefresh == 0 then
          timetableWindowFuncs.refreshLines(guiState.timetableWindow.lineTable,
              guiState.timetableWindow.filters,
              guiState.timetableWindow.lineTableRows)
        end
      end
    end,

    handleEvent = function (src, id, name, param)
      -- Nothing to do here.  (Maybe later we will send some messages.)
    end,

    guiHandleEvent = function (id, name, param)
      if id == "menu.lineManager" and name == "toggleButton.toggle" then
        -- When the line manager window is open, we always refresh.
        guiState.alwaysRefresh = param
      end

      if id == "menu.vehicleManager" and name == "toggleButton.toggle" then
        -- When the vehicle manager window is open, we always refresh.
        guiState.alwaysRefresh = param
      end
    end
  }
end
