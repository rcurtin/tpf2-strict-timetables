-- clock_funcs.lua: utility functions for dealing with the clock.
local clockFuncs = {}

-- Initialize the clock to 00:00.
function clockFuncs.initClock()
  local time = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
  if time == nil then
    time = 0
  end

  return {
    min = 0,
    sec = 0,
    refTime = time
  }
end

-- Tick the clock (if necessary).  Note that this is not necessarily called on
-- one-second boundaries!  It is instead called by every game engine update tick
-- (this appears to be every 200ms).
function clockFuncs.updateClock(clock)
  local time = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
  if time and clock then
    local totalSecs = math.floor((time - clock.refTime) / 1000)
    local totalMins = math.floor(totalSecs / 60)

    return {
      min = totalMins % 60,
      sec = totalSecs % 60,
      refTime = clock.refTime
    }
  else
    -- No update to make, we didn't get a time...
    return clock
  end
end

-- Return t as a two-digit string.
function clockFuncs.formatTime(t)
  if t < 10 then
    return "0" .. tostring(t)
  else
    return tostring(t)
  end
end

-- Given the current state of a clock, return the time as a string to be
-- printed.
function clockFuncs.printClock(clock)
  local t = { clockFuncs.formatTime(clock.min), ":", clockFuncs.formatTime(clock.sec) }
  return table.concat(t, "")
end

-- Initialize the GUI elements associated with the clock.
function clockFuncs.initGUI()
  -- First create the pieces for the clock itself.
  local line = api.gui.comp.Component.new("VerticalLine")
  local icon = api.gui.comp.ImageView.new("ui/clock_small.tga")
  clockGUI = api.gui.comp.TextView.new("gameInfo.strict_timetables.clock_label")

  local gameInfoLayout = api.gui.util.getById("gameInfo"):getLayout()
  gameInfoLayout:addItem(line)
  gameInfoLayout:addItem(icon)
  gameInfoLayout:addItem(clockGUI)

  -- Now create a button for the timetable.
  local buttonLabel = gui.textView_create("gameInfo.strict_timetables.button_label", _("timetable"))
  local button = gui.button_create("gameInfo.strict_timetables.button", buttonLabel)
  -- TODO: make the button do something...
  game.gui.boxLayout_addItem("gameInfo.layout", button.id)

  return clockGUI
end

return clockFuncs
