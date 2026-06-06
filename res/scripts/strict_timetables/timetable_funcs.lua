-- timetable_funcs.lua
--
-- Engine thread utilities to actually run the timetables.
local clockFuncs = require "strict_timetables/clock_funcs"
local vehicleUtils = require "strict_timetables/vehicle_utils"
local lineUtils = require "strict_timetables/line_utils"

timetableFuncs = {}

--
-- Clear all vehicle slots when a timetable is disabled.
--
function timetableFuncs.clearVehicles(timetables, line)
  for _, v in pairs(timetables.slotAssignments[line]) do
    timetables.vehicles[v] = nil
    -- Make sure the vehicle won't just wait somewhere forever.
    api.cmd.sendCommand(api.cmd.make.setVehicleManualDeparture(v, false))
  end
  timetables.slotAssignments[line] = nil
end

--
-- Attempt to assign a vehicle to a timetable slot.  This may fail if there are
-- not currently any open slots.
--
function timetableFuncs.tryAssignSlot(timetables, clock, line, vehicle)
  -- If the timetable doesn't exist but is enabled, then just return for now.
  if not timetables.timetable[line] then
    return
  end

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
    local curSlot = timetables.vehicles[vehicle].slot
    if curSlot ~= 0 and timetables.slotAssignments[line][curSlot] ~= nil then
      timetables.slotAssignments[line][curSlot] = nil
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
-- Return true if a vehicle is late.
--
function timetableFuncs.isLate(timetables, depDiff, vehicle, line)
  local maxLate = { min = 30, sec = 0 }
  if timetables.maxLateness[line] then
    maxLate = timetables.maxLateness[line]
  end

  return (depDiff.mins >= (60 - maxLate.min)) or
      (depDiff.mins == (60 - maxLate.min) and
       depDiff.secs >= (60 - maxLate.sec))
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
    local isLate = timetableFuncs.isLate(timetables, d, vehicle, line)

    if vehicleInfo.autoDeparture and (vehicleInfo.stopIndex == 0 or isLate) then
      api.cmd.sendCommand(
          api.cmd.make.setVehicleManualDeparture(vehicle, true))
    end

    -- If a vehicle is more than 30 minutes late, we actually consider it 30
    -- minutes early!
    if d.mins == 0 and d.secs == 0 then
      -- On time: force the vehicle to depart.
      if debug then
        print("StrictTimetables: vehicle " .. tostring(vehicle) ..
            " (" .. vehicleUtils.getName(vehicle) .. ") on line " ..
            tostring(line) .. " (" .. lineUtils.getName(line) .. ") slot " ..
            tostring(timetables.vehicles[vehicle].slot) ..
            " released on-time at " .. clockFuncs.printClock(depTarget) .. ".")
      end
      api.cmd.sendCommand(api.cmd.make.setVehicleShouldDepart(vehicle))
      timetables.vehicles[vehicle].released = true
      timetables.vehicles[vehicle].late = nil
    elseif isLate and not onTimeOnly then
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
          local lateTime = clockFuncs.timeDiff(
              { min = 60 - d.mins, sec = 60 - d.secs },
              { min = 0, sec = 0 })
          if debug then
            print("StrictTimetables: vehicle " .. tostring(vehicle) .. " (" ..
                vehicleUtils.getName(vehicle) .. ") on line " ..
                tostring(line) .. " (" .. lineUtils.getName(line) ..
                ") slot " .. tostring(timetables.vehicles[vehicle].slot) ..
                " leaving late (" .. tostring(lateTime.mins) .. "m" ..
                tostring(lateTime.secs) .. "s) after 10s of loading/unloading.")
          end
          api.cmd.sendCommand(api.cmd.make.setVehicleShouldDepart(vehicle))
          timetables.vehicles[vehicle].released = true
          timetables.vehicles[vehicle].late = lateTime
        end
      elseif isLate then
        -- The stop is not a full load of any sort, and doesn't have a minimum
        -- waiting time, so we can just depend on the game to finish
        -- loading/unloading then send the vehicle on its way.
        local lateTime = clockFuncs.timeDiff(
            { min = d.mins, sec = d.secs }, { min = 0, sec = 0 })
        if debug then
          print("StrictTimetables: vehicle " .. tostring(vehicle) .. " (" ..
              vehicleUtils.getName(vehicle) .. ") on line " ..
              tostring(line) .. " (" .. lineUtils.getName(line) .. ") slot " ..
              tostring(timetables.vehicles[vehicle].slot) ..
              " will leave late (" .. tostring(lateTime.mins) .. "m" ..
              tostring(lateTime.secs) .. "s) after loading and unloading.")
        end
        api.cmd.sendCommand(api.cmd.make.setVehicleManualDeparture(vehicle,
            false))
        timetables.vehicles[vehicle].released = true
        timetables.vehicles[vehicle].late = lateTime
      end
    end
  elseif not vehicleInfo.autoDeparture and
      timetables.vehicles[vehicle].assigned then
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
      -- Sanity check before we start: does the vehicle still exist?
      if timetables.slotAssignments[l] then
        for s, v in pairs(timetables.slotAssignments[l]) do
          if v and not api.engine.entityExists(v) then
            if debug then
              print("StrictTimetables: vehicle " .. tostring(v) ..
                " no longer exists!  Deleting.")
            end
            timetables.slotAssignments[s] = nil
            timetables.vehicles[v] = nil
          end
        end
      end

      local lineInfo = api.engine.getComponent(l, api.type.ComponentType.LINE)

      -- Now iterate over all the vehicles to see if they have a state update.
      for _, v in pairs(vs) do
        -- We only have something to do if the vehicle is at a station.
        local vi = api.engine.getComponent(v,
            api.type.ComponentType.TRANSPORT_VEHICLE)
        if vi.state == api.type.enum.TransportVehicleState.AT_TERMINAL then
--          if debug and timetables.vehicles[v] then
--            print("StrictTimetables: vehicle " .. tostring(v) .. " status: " ..
--                "{ assigned: " .. tostring(timetables.vehicles[v].assigned) ..
--                ", slot " .. tostring(timetables.vehicles[v].slot) ..
--                ", stopIndex " .. tostring(timetables.vehicles[v].stopIndex) ..
--                ", released " .. tostring(timetables.vehicles[v].released) ..
--                " }.")
--          end

          -- If the stop index has changed, then take the appropriate action.
          local firstAssignmentAttempt = false
          if not timetables.vehicles[v] then
            timetables.vehicles[v] = { slot = 0, assigned = false,
                stopIndex = vi.stopIndex, released = false }
            firstAssignmentAttempt = true
          elseif vi.stopIndex ~= timetables.vehicles[v].stopIndex then
            timetables.vehicles[v].stopIndex = vi.stopIndex
            timetables.vehicles[v].released = false
            -- If we're back at the first stop, unassign (we will reassign
            -- momentarily).
            if vi.stopIndex == 0 then
              local oldSlot = timetables.vehicles[v].slot
              if oldSlot ~= 0 and
                  timetables.slotAssignments[l][oldSlot] ~= nil then
                timetables.slotAssignments[l][oldSlot] = nil
              end

              timetables.vehicles[v].slot = 0
              timetables.vehicles[v].assigned = false
            end
            firstAssignmentAttempt = true
          end

          -- If this station is the first, then we have the possibility that
          -- we are able to assign the vehicle to a slot.
          local assignable = (not timetables.vehicles[v]) or
              (timetables.vehicles[v].assigned == false)
          if vi.stopIndex == 0 and assignable then
            -- At the first stop, we always assign the vehicle to the next
            -- available timeslot.
            timetableFuncs.tryAssignSlot(timetables, clock, l, v)
            local slot = timetables.vehicles[v].slot
            if slot == 0 and firstAssignmentAttempt then
              -- No slot is found!  We need to wait until we can be assigned to
              -- something.
              if debug then
                print("StrictTimetables: vehicle " .. tostring(v) .. " (" ..
                    vehicleUtils.getName(v) .. ") on line " .. tostring(l) ..
                    " (" .. lineUtils.getName(l) .. ") has no open slot; " ..
                    "waiting at the first stop until a slot is available.")
              end
              api.cmd.sendCommand(
                  api.cmd.make.setVehicleManualDeparture(v, true))

            elseif debug and slot ~= 0 then
              print("StrictTimetables: vehicle " .. tostring(v) .. " (" ..
                  vehicleUtils.getName(v) .. ") on line " .. tostring(l) ..
                  " (" .. lineUtils.getName(l) .. ") assigned to slot " ..
                  tostring(slot) ..  ".")
            end
          end

          -- Release the vehicle from its station, if the time has come, and
          -- the vehicle is in a slot.  If it is the first stop, then we always
          -- force an on-time departure.
          if not timetables.vehicles[v].released then
            timetableFuncs.releaseIfNeeded(timetables, clock, l, v, vi,
                (vi.stopIndex == 0), debug)
          end
        elseif timetables.vehicles[v] and timetables.vehicles[v].slot then
          -- If the vehicle is returning back to the first stop and will not
          -- make it there in time for the first departure, then yield the slot.
          if timetables.vehicles[v].stopIndex == #lineInfo.stops - 1 and
              timetables.vehicles[v].slot > 0 then
            -- Check the target release time of the first timetabled station.
            local firstTimedStop = 1
            local slot = timetables.vehicles[v].slot
            while firstTimedStop <= #timetables.timetable[l][slot] do
              -- Does this stop have a timetable?
              if timetables.timetable[l][slot][firstTimedStop] ~= nil then
                -- If so, it's the first timed stop.
                break
              end

              firstTimedStop = firstTimedStop + 1
            end
            local d = clockFuncs.timeDiff(clock,
                { min = timetables.timetable[l][slot][firstTimedStop][1],
                  sec = timetables.timetable[l][slot][firstTimedStop][2] })
            local maxLate = { min = 30, sec = 0 }
            if timetables.maxLateness[l] then
              maxLate = timetables.maxLateness[l]
            end

            if ((d.mins == 0 and d.secs < 5) or
                (d.mins >= (60 - maxLate.min)) or
                ((d.mins == (60 - maxLate.min)) and
                 (d.secs >= (60 - maxLate.sec)))) then
              if debug then
                print("StrictTimetables: vehicle " .. tostring(v) .. " (" ..
                    vehicleUtils.getName(v) .. ") on line " .. tostring(l) ..
                    " (" .. lineUtils.getName(l) .. ") is too late to keep " ..
                    "slot " .. tostring(timetables.vehicles[v].slot) .. "; " ..
                    "unassigned.")
              end

              local oldSlot = timetables.vehicles[v].slot
              timetables.slotAssignments[l][oldSlot] = nil
              timetables.vehicles[v] = { slot = 0, assigned = false,
                  stopIndex = 0, released = false }

              -- Check if there are any waiting vehicles who could use the slot.
              if d.mins == 0 and d.secs < 5 then
                for s, vv in pairs(timetables.slotAssignments[l]) do
                  if vv and timetables.vehicles[vv] and
                      timetables.vehicles[vv].stopIndex == 0 and
                      timetables.vehicles[vv].released == false then
                    local f = 1
                    while f <= #timetables.timetable[l][s] do
                      -- Does this stop have a timetable?
                      if timetables.timetable[l][s][f] ~= nil then
                        -- If so, it's the first timed stop.
                        break
                      end

                      f = f + 1
                    end

                    if f <= #timetables.timetable[l][s] then
                      local d2 = clockFuncs.timeDiff(clock,
                        { min = timetables.timetable[l][s][f][1],
                          sec = timetables.timetable[l][s][f][2] })
                      if (d2.mins > 0) or (d2.mins == 0 and d2.secs >= 5) then
                        if debug then
                          print("StrictTimetables: vehicle " .. tostring(v) ..
                              " (" .. vehicleUtils.getName(vv) .. ") on line" ..
                              " " .. tostring(l) .. " (" ..
                              lineUtils.getName(l) .. " will switch to slot " ..
                              tostring(oldSlot) .. " instead of " ..
                              tostring(s) .. ".")
                        end

                        timetables.slotAssignments[l][s] = nil
                        timetables.slotAssignments[l][oldSlot] = vv
                        timetables.vehicles[vv].slot = oldSlot
                        timetables.vehicles[vv].assigned = true
                        break
                      end
                    end
                  end
                end
              end
            end
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
          if timetables.vehicles[v].assigned == true and
              timetables.vehicles[v].stopIndex == 0 and
              timetables.vehicles[v].released == false then
            -- When .assigned is true, we are waiting to release from the first
            -- stop.  So, set it to false, and the next update tick will
            -- re-assign it to an open slot.
            timetables.vehicles[v].assigned = false
            timetables.slotAssignments[line][timetables.vehicles[v].slot] = nil
            timetables.vehicles[v].slot = 0
          elseif timetables.vehicles[v].slot ~= 0 and
              timetables.vehicles[v].slot > #timetables.timetable[line] then
            -- Unassign from a no-longer-existent slot.
            timetables.vehicles[v].slot = 0
            timetables.vehicles[v].late = nil
            timetables.slotAssignments[line][timetables.vehicles[v].slot] = nil
          end
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
