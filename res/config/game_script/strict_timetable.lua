local clockFuncs = require "strict_timetables/clock_funcs"
local timetableWindowFuncs = require "strict_timetables/timetable_window_funcs"

-- The clock is controlled by the engine thread.
-- The GUI thread will receive updates passively when load() is called.
local clock = nil

-- The GUI element for the clock; it is only non-nil on the GUI thread.
local clockGUI = nil

-- The GUI window for setting the timetable.
local timetableWindow = nil

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
        timetableWindow = timetableWindowFuncs.initWindow()
        timetableWindowFuncs.initButton(timetableWindow)
      end

      if clockGUI and clock then
        clockGUI:setText(clockFuncs.printClock(clock))
      end
    end,

    handleEvent = function (src, id, name, param)
      -- nothing to do
      -- Events we want to handle:
      --
      --  * Line added/removed/changed
      print("gui got event: ", tostring(src), tostring(id), tostring(name), tostring(param))
    end
  }
end
