-- timetable_window_funcs.lua
--
-- Functionality related to the GUI window that allows a user to set the
-- timetable.

timetableWindowFuncs = {}

-- Add all of the lines to the line table, using the states of the given filters
-- to select which lines are displayed.  The existing rows in the line table
-- must be passed in because it seems there is no way to recover these from
-- `lineTable` directly.
--
-- Note that this will mutate lineTableRows if any changes are detected!
function timetableWindowFuncs.refreshLines(lineTable, filters, lineTableRows)

  -- Extract the values of the filters.
  -- 1: bus; 2: tram; 3: rail; 4: water; 5: air
  local noFilters = not filters[1]:isSelected() and
                    not filters[2]:isSelected() and
                    not filters[3]:isSelected() and
                    not filters[4]:isSelected() and
                    not filters[5]:isSelected()

  local newRows = {}
  for k, l in pairs(api.engine.system.lineSystem.getLines()) do
    local lineName = api.engine.getComponent(l, api.type.ComponentType.NAME)
    local lineLabel = "ERROR" -- used if we can't find a real name for it.
    if lineName and lineName.name then
      lineLabel = lineName.name
    end

    -- Get the type of vehicle on the line.
    local lineType = nil
    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(l)
    if vehicles and vehicles[1] then
      local component = api.engine.getComponent(vehicles[1], api.type.ComponentType.TRANSPORT_VEHICLE)
      if component and component.carrier then
        lineType = component.carrier
      end
    end

    -- Check the filters to see if we can add the line.
    local add = noFilters or
      (filters[1]:isSelected() and lineType == api.type.enum.Carrier["ROAD"]) or
      (filters[2]:isSelected() and lineType == api.type.enum.Carrier["TRAM"]) or
      (filters[3]:isSelected() and lineType == api.type.enum.Carrier["RAIL"]) or
      (filters[4]:isSelected() and lineType == api.type.enum.Carrier["WATER"]) or
      (filters[5]:isSelected() and lineType == api.type.enum.Carrier["AIR"])
    if add then
      local color = api.gui.comp.TextView.new("●")
      --color:setName("strict_timetable-color-test")

      local buttonImage = api.gui.comp.ImageView.new("ui/checkbox0.tga")
      -- TODO: make it checked if we have a timetable
      local button = api.gui.comp.Button.new(buttonImage, true)
      button:setGravity(1, 0.5)
      button:onClick(function()
        buttonImage:setImage("ui/checkbox1.tga", false)
      end)

      table.insert(newRows, { color, api.gui.comp.TextView.new(lineLabel), button })
    end
  end

  -- Sort the new table of entries in alphabetical order.
  table.sort(newRows, function(x, y)
      return string.lower(x[2]:getText()) < string.lower(y[2]:getText())
  end)

  -- Only update the table if any entries have changed.
  local anyDifferent = false
  if not lineTableRows or #newRows ~= #lineTableRows then
    anyDifferent = true
  else
    for i, row in pairs(newRows) do
      oldRow = lineTableRows[i]
      -- Check the color label.
      if oldRow[1]:getText() ~= row[1]:getText() then
        anyDifferent = true
        break
      end

      -- Check the name of the line.
      if oldRow[2]:getText() ~= row[2]:getText() then
        anyDifferent = true
        break
      end
    end
  end

  if anyDifferent then
    -- Clear the table.
    lineTable:deleteRows(0, lineTable:getNumRows())

    -- Add all of the new rows, and update the line table (don't create a new
    -- one).
    for i, row in pairs(newRows) do
      lineTable:addRow(row)
      lineTableRows[i] = row
    end
  end

  return
end

-- Initialize the window: create all the tabs and other structure that will be
-- filled when clicked.
--
-- Returns a table that has the same schema as 'timetableWindow' described in
-- the main mod file.
function timetableWindowFuncs.initWindow(lineTableRows)
  -- We have to build the components here from the inside to the outside.
  -- So, at the innermost level, let's start with the actual table that contains
  -- the lines.
  local lineHeader = api.gui.comp.Table.new(6, 'None')
  local filters = {
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_road_vehicles.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/TimetableTramIcon.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_trains.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_ships.tga")),
      api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new(
          "ui/icons/game-menu/hud_filter_planes.tga")),
  }
  lineHeader:addRow({ api.gui.comp.TextView.new(_("filter:")), table.unpack(filters) })

  local lineTable = api.gui.comp.Table.new(3, 'SINGLE')
  lineTable:setColWidth(0, 28)
  lineTable:onSelect(function(i)
    if i >= 0 then
      print("Selected line index ", tostring(i), "!")
    end
  end)

  -- Set up callbacks for all of the filters.
  for i, f in pairs(filters) do
    f:onToggle(function()
      timetableWindowFuncs.refreshLines(lineTable, filters, lineTableRows)
    end)
  end
  -- Rebuild the elements of the table with no filter.
  timetableWindowFuncs.refreshLines(lineTable, filters, lineTableRows)

  -- Now create a scroll area to wrap the table, since there could be many
  -- lines.
  local lineTableScrollArea = api.gui.comp.ScrollArea.new(
      api.gui.comp.TextView.new("LineOverview"), "strict_timetable.LineOverview")
  lineTableScrollArea:setMinimumSize(api.gui.util.Size.new(320, 690))
  lineTableScrollArea:setMaximumSize(api.gui.util.Size.new(320, 690))
  lineTableScrollArea:setContent(lineTable)

  -- Next we need a layout to use for the wrapper...
  local lineTabLayout = api.gui.layout.FloatingLayout.new(0, 1)
  lineTabLayout:setId("strict_timetable.lineTabLayout")
  lineTabLayout:setGravity(-1, -1)
  lineTabLayout:addItem(lineHeader, 0, 0)
  lineTabLayout:addItem(lineTableScrollArea, 0, 1)

  -- Next we need a wrapper for the content of the tab.
  local lineTab = api.gui.comp.Component.new("wrapper")
  lineTab:setLayout(lineTabLayout)

  local tabWidget = api.gui.comp.TabWidget.new("NORTH")
  tabWidget:addTab(api.gui.comp.TextView.new(_("lines")), lineTab)
  --tabWidget:onCurrentChanged(function(i)
  --  print("Changed tab to ", tostring(i))
  --  if i == 0 then
  --    timetableWindowFuncs.
  --  end
  --end)

  local window = api.gui.comp.Window.new(_("timetables"), tabWidget)
  window:addHideOnCloseHandler()
  window:setMovable(true)
  window:setPinButtonVisible(true)
  window:setResizable(true)
  window:setSize(api.gui.util.Size.new(1200, 800))
  window:setPosition(200, 200)
  window:setVisible(false, false)

  return {
      handle = window,
      lineTable = lineTable,
      lineTableRows = lineTableRows,
      filters = filters
  }
end

-- Open the window.
function timetableWindowFuncs.showWindow(window)
  if not window then
    print("Attempted to show window but it was nil!")
  else
    window:setVisible(true, true)
  end
end

-- Create the button on the main GUI (to the right of the clock) that a user can
-- click on to open the timetable window dialog.
function timetableWindowFuncs.initButton(window)
  -- Now create a button for the timetable.
  local line = api.gui.comp.Component.new("VerticalLine")
  local buttonLabel = gui.textView_create("gameInfo.strict_timetables.button_label", _("timetable"))
  local button = gui.button_create("gameInfo.strict_timetables.button", buttonLabel)

  local gameInfoLayout = api.gui.util.getById("gameInfo"):getLayout()
  gameInfoLayout:addItem(line)
  game.gui.boxLayout_addItem("gameInfo.layout", button.id)
  button:onClick(function ()
    local status, err = pcall(timetableWindowFuncs.showWindow, window)
    if not status then
      print(err)
    end
  end)

  return
end

return timetableWindowFuncs
