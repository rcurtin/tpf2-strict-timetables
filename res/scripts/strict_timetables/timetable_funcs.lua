-- timetable_funcs.lua
--
-- Engine thread utilities to actually run the timetables.
local clockFuncs = require "strict_timetables/clock_funcs"

timetableFuncs = {}

--
-- Attempt to assign a vehicle to a timetable slot.  This may fail if there are
-- not currently any open slots.
--
function timetableFuncs.tryAssignSlot(timetables, clock, line, vehicle)
  -- Find the next starting timeslot closest to us in time.
  local slot = 1
  local bestDiff = { mins = 60, secs = 0 }
  local bestSlot = 0
  while slot <= #timetables.timetable[line] do
    if timetables.slotAssignments[line] == nil or
        timetables.slotAssignments[line][slot] == nil then
      -- Check the target release time of the first timetabled station.
      local firstTimedStop = 1
      while firstTimedStop <= #timetables.timetable[line][slot] do
        -- Does this stop have a timetable?
        if timetables.timetable[line][slot][firstTimedStop] ~= nil then
            -- If so, it's the first timed stop.
            break
        end

        firstTimedStop = firstTimedStop + 1
      end

      -- We can only proceed if we actually got a first timed stop.
      if firstTimedStop <= #timetables.timetable[line][slot] then
        -- How far away are we from the target time?
        slotTime = { min = timetables.timetable[line][slot][firstTimedStop][1],
                     sec = timetables.timetable[line][slot][firstTimedStop][2] }
        diff = clockFuncs.timeDiff(clock, slotTime)

        if clockFuncs.smallerDiff(diff, bestDiff) then
          bestDiff = diff
          bestSlot = slot
        end
      end
    end

    slot = slot + 1
  end

  -- Yield whatever the old timeslot is.
  if timetables.vehicles[vehicle] then
    if timetables.slotAssignments[line][timetables.vehicles[vehicle].slot] then
      timetables.slotAssignments[line][timetables.vehicles[vehicle].slot] = nil
    end
  end

  if bestSlot ~= 0 then
    -- Assign this vehicle to that slot.
    if not timetables.slotAssignments[line] then
      timetables.slotAssignments[line] = {}
    end
    timetables.slotAssignments[line][bestSlot] = vehicle
    timetables.vehicles[vehicle] = {
        slot = bestSlot,
        assigned = true,
        stopIndex = 0,
        released = false }
  else
    timetables.vehicles[vehicle] = {
        slot = 0,
        assigned = false,
        stopIndex = 0,
        released = false }
  end
end

--
-- Release a vehicle if it is waiting.
--
function timetableFuncs.releaseIfNeeded(timetables, clock, line, vehicle,
    vehicleInfo, onTimeOnly, debug)
  -- First determine if the current stop/slot for this vehicle has a timeslot.
  local depTarget = nil
  if timetables.vehicles[vehicle] ~= nil and
      timetables.vehicles[vehicle].slot ~= 0 then
    -- This vehicle is assigned to a slot; but is it currently at a stop that is
    -- timetabled?
    local slotId = timetables.vehicles[vehicle].slot
    local stopIndex = vehicleInfo.stopIndex + 1
    if timetables.timetable[line][slotId][stopIndex] then
      depTarget = { min = timetables.timetable[line][slotId][stopIndex][1],
                    sec = timetables.timetable[line][slotId][stopIndex][2] }
    end
  end

  if depTarget ~= nil then
    -- Disable automatic departure, if it's enabled, and we're waiting.
    local d = clockFuncs.timeDiff(clock, depTarget)
    local maxLate = { min = 30, sec = 0 }
    if timetables.maxLateness[line] then
      maxLate = timetables.maxLateness[line]
    end

    if ((d.mins < maxLate.min) or
        (d.mins == maxLate.min and d.secs < maxLate.sec)) and
        vehicleInfo.autoDeparture then
      api.cmd.sendCommand(
          api.cmd.make.setVehicleManualDeparture(vehicle, true))
    end

    -- If a vehicle is more than 30 minutes late, we actually consider it 30
    -- minutes early!
    if d.mins == 0 and d.secs == 0 then
      -- On time: force the vehicle to depart.
      if debug then
        print("StrictTimetables: vehicle " .. tostring(vehicle) ..
            " on line " .. tostring(line) .. " slot " ..
            tostring(timetables.vehicles[vehicle].slot) ..
            " released on-time at " .. clockFuncs.printClock(depTarget) .. ".")
      end
      api.cmd.sendCommand(api.cmd.make.setVehicleShouldDepart(vehicle))
      if timetables.vehicles[vehicle].stopIndex > 0 then
        -- If we set assigned to false when leaving the first station, then it
        -- is possible that the vehicle will get reassigned to a different slot
        -- before it leaves!
        timetables.vehicles[vehicle].assigned = false
      end
      timetables.vehicles[vehicle].released = true
      timetables.vehicles[vehicle].late = nil
    elseif (d.mins >= (60 - maxLate.min) or
        ((d.mins == (60 - maxLate.min)) and (d.secs >= (60 - maxLate.sec)))) and
        not onTimeOnly then
      -- Here we don't force the train to leave unless it is still loading or
      -- unloading.  If the stop is a full load any/all, or has a minimum stop
      -- time greater than 0s, then we have to force it.  In this case we'll
      -- force the vehicle to leave 10 seconds after it arrived.
      local lineInfo = api.engine.getComponent(line,
          api.type.ComponentType.LINE)
      if lineInfo.stops[vehicleInfo.stopIndex + 1].minWaitingTime > 0 or
          lineInfo.stops[vehicleInfo.stopIndex + 1].loadMode ~=
              api.type.enum.LineLoadMode.LOAD_IF_AVAILABLE then
        -- Check if we have been waiting for at least 10 seconds.
        local currGameTime = math.floor(
            api.engine.getComponent(api.engine.util.getWorld(),
            api.type.ComponentType.GAME_TIME).gameTime / 1000)
        local waitingSecs = currGameTime -
            math.floor(vehicleInfo.doorsTime / 1000000)
        if waitingSecs >= 10 then
          local lateTime = clockFuncs.timeDiff({ min = d.mins, sec = d.secs },
              { min = 0, sec = 0 })
          if debug then
            print("StrictTimetables: vehicle " .. tostring(vehicle) ..
                " on line " .. tostring(line) .. " slot " ..
                tostring(timetables.vehicles[vehicle].slot) ..
                " leaving late (" .. tostring(lateTime.mins) .. "m" ..
                tostring(lateTime.secs) .. "s) after 10s of loading/unloading.")
          end
          api.cmd.sendCommand(api.cmd.make.setVehicleShouldDepart(vehicle))
          timetables.vehicles[vehicle].released = true
          timetables.vehicles[vehicle].late = lateTime
        end
      else
        -- The stop is not a full load of any sort, and doesn't have a minimum
        -- waiting time, so we can just depend on the game to finish
        -- loading/unloading then send the vehicle on its way.
        local lateTime = clockFuncs.timeDiff({ min = d.mins, sec = d.secs },
            { min = 0, sec = 0 })
        if debug then
          print("StrictTimetables: vehicle " .. tostring(vehicle) ..
              " on line " ..  tostring(line) .. " slot " ..
              tostring(timetables.vehicles[vehicle].slot) ..
              " will leave late (" .. tostring(lateTime.mins) .. "m" ..
              tostring(lateTime.secs) .. "s) after loading and unloading.")
        end
        api.cmd.sendCommand(api.cmd.make.setVehicleManualDeparture(vehicle,
            false))
        timetables.vehicles[vehicle].released = true
        timetables.vehicles[vehicle].late = lateTime
      end
      timetables.vehicles[vehicle].assigned = false
    end
  elseif not vehicleInfo.autoDeparture then
    api.cmd.sendCommand(api.cmd.make.setVehicleManualDeparture(vehicle, false))
    timetables.vehicles[vehicle].released = true
  end
end

--
-- Called at the beginning of every second to handle releasing any vehicles from
-- stations.
--
function timetableFuncs.vehicleUpdate(timetables, clock, debug)
  -- Iterate over all lines.
  local vehicleLineMap =
      api.engine.system.transportVehicleSystem.getLine2VehicleMap()
  for l, vs in pairs(vehicleLineMap) do
    -- Only check vehicles where we have an active timetable.
    if timetables.enabled[l] then
      -- Now iterate over all the vehicles to see if they have a state update.
      for _, v in pairs(vs) do
        -- We only have something to do if the vehicle is at a station.
        local vi = api.engine.getComponent(v,
            api.type.ComponentType.TRANSPORT_VEHICLE)
        if vi.state == api.type.enum.TransportVehicleState.AT_TERMINAL then
          -- If this station is the first, then we have the possibility that
          -- we are able to assign the vehicle to a slot.
          local assignable = (not timetables.vehicles[v]) or
              (timetables.vehicles[v].assigned == false)
          if vi.stopIndex == 0 and assignable then
            -- At the first stop, we always assign the vehicle to the next
            -- available timeslot.
            timetableFuncs.tryAssignSlot(timetables, clock, l, v)
            if debug then
              local slot = timetables.vehicles[v].slot
              if slot ~= 0 then
                print("StrictTimetables: vehicle " .. tostring(v) ..
                    " on line " ..  tostring(l) .. " assigned to slot " ..
                    tostring(slot) ..  ".")
              end
            end
          elseif not timetables.vehicles[v] then
            timetables.vehicles[v] = { slot = 0, assigned = false,
                stopIndex = vi.stopIndex, released = false }
          end

          -- If the stop index has changed, then take the appropriate action.
          if vi.stopIndex ~= timetables.vehicles[v].stopIndex then
            timetables.vehicles[v].stopIndex = vi.stopIndex
            timetables.vehicles[v].released = false
          end

          -- Release the vehicle from its station, if the time has come, and
          -- the vehicle is in a slot.  If it is the first stop, then we always
          -- force an on-time departure.
          if not timetables.vehicles[v].released then
            timetableFuncs.releaseIfNeeded(timetables, clock, l, v, vi,
                (vi.stopIndex == 0), debug)
          end
        end
      end
    end
  end
end

--
-- When the timetable for a line has changed completely, any vehicles waiting at
-- the first stop may need their slots reassigned.
--
function timetableFuncs.resetVehiclesOnLine(timetables, line)
  if timetables.enabled[line] then
    local vehicleLineMap =
        api.engine.system.transportVehicleSystem.getLine2VehicleMap()

    if vehicleLineMap[line] then
      for _, v in pairs(vehicleLineMap[line]) do
        if timetables.vehicles[v] then
          if timetables.vehicles[v].assigned == true then
            -- When .assigned is true, we are waiting to release from the first
            -- stop.  So, set it to false, and the next update tick will
            -- re-assign it to an open slot.
            timetables.vehicles[v].assigned = false
          elseif timetables.vehicles[v].slot ~= 0 then
            -- Unassign from a slot.
            timetables.vehicles[v].slot = 0
            timetables.vehicles[v].late = nil
          end
          timetables.slotAssignments[line][timetables.vehicles[v].slot] = nil
        end
      end
    end
  end
end

--
-- When an entire timeslot is removed, all vehicles on that line assigned to a
-- slot with a greater index must be shifted down, and a vehicle assigned to the
-- removed slot must be reassigned to no slot at all.
--
function timetableFuncs.shiftVehiclesForRemovedSlot(timetables, line, slot)
  if timetables.enabled[line] then
    local vehicleLineMap =
        api.engine.system.transportVehicleSystem.getLine2VehicleMap()

    if vehicleLineMap[line] then
      for _, v in pairs(vehicleLineMap[line]) do
        if timetables.vehicles[v] and
            timetables.vehicles[v].slot == slot then
          -- This vehicle is now unassigned.
          timetables.vehicles[v].slot = 0
          timetables.vehicles[v].assigned = false
          timetables.slotAssignments[line][slot] = nil
        elseif timetables.vehicles[v] and
            timetables.vehicles[v].slot > slot then
          -- The slot needs to be shifted by one.
          timetables.slotAssignments[line][timetables.vehicles[v].slot] = nil
          timetables.vehicles[v].slot = timetables.vehicles[v].slot - 1
          timetables.slotAssignments[line][timetables.vehicles[v].slot] = v
        end
      end
    end
  end
end

return timetableFuncs
