local clockFuncs = require "strict_timetables/clock_funcs"

-- The clock is controlled by the engine thread.
-- The GUI thread will receive updates passively when load() is called.
local clock = nil

-- The GUI element for the clock; it is only non-nil on the GUI thread.
local clockGUI = nil

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
      if not clockGUI then
        clockGUI = clockFuncs.initGUI()
      end

      if clockGUI and clock then
        clockGUI:setText(clockFuncs.printClock(clock))
      end
    end,

    handleEvent = function (src, id, name, param)
      -- nothing to do
    end
  }
end
