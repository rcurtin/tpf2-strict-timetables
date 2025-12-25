-- clock_funcs.lua: utility functions for dealing with the clock.
local clockFuncs = {}

-- Initialize the clock to 00:00.
function clockFuncs.initClock()
  local time = api.engine.getComponent(api.engine.util.getWorld(),
      api.type.ComponentType.GAME_TIME).gameTime
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
  local time = api.engine.getComponent(api.engine.util.getWorld(),
      api.type.ComponentType.GAME_TIME).gameTime
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
  local t = { clockFuncs.formatTime(clock.min), ":",
      clockFuncs.formatTime(clock.sec) }
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

  return clockGUI
end

--
-- Return the difference (t2 - t1), always assuming that t2 comes *after* t1,
-- even over boundaries.
--
function clockFuncs.timeDiff(t1, t2)
  local diffSecs = 0
  if t1.min > t2.min then
    diffSecs = 60 * (60 - t1.min + t2.min)
  else
    diffSecs = 60 * (t2.min - t1.min)
  end

  if diffSecs == 0 then
    if t1.sec > t2.sec then
      -- We have to assume the difference is nearly an hour.
      diffSecs = 3600 - (t1.sec - t2.sec)
    else
      diffSecs = t2.sec - t1.sec
    end
  else
    -- It's okay if t1.secs > t2.secs, e.g. t1 = 10:15, t2 = 11:00; we already
    -- counted the minute difference, so we just need to subtract the remainder.
    diffSecs = diffSecs + (t2.sec - t1.sec)
  end

  local diffMins = math.floor(diffSecs / 60)

  return { mins = diffMins, secs = diffSecs % 60 }
end

--
-- Return true if t1 represents a smaller interval than t2.
--
function clockFuncs.smallerDiff(t1, t2)
  if t1.mins < t2.mins then
    return true
  elseif t1.mins == t2.mins and t1.secs < t2.secs then
    return true
  else
    return false
  end
end

return clockFuncs
