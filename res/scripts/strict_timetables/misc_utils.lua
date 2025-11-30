-- misc_utils.lua
--
-- Miscellaneous utilities that Lua doesn't provide already.

miscUtils = {}

-- Return two values:
--  * a bool if the keys in new and old differ;
--  * if the bool is false, then a list of which keys have different values
function miscUtils.differs(old, new)
  if not new and not old then
    return false, {}
  elseif not new or not old then
    return true, {}
  end

  local newCount = 0
  local diffKeys = {}
  for i, v in pairs(new) do
    newCount = newCount + 1
    if not old[i] then
      return true, {}
    elseif type(new[i]) ~= type(old[i]) then
      table.insert(diffKeys, i)
    elseif type(new[i]) == "table" then
      local d, k = miscUtils.differs(old[i], new[i])
      if d == true or #k > 0 then
        table.insert(diffKeys, i)
      end
    elseif type(new[i]) == "userdata" then
      -- no clear way to compare these, be cautious instead...
      table.insert(diffKeys, i)
    elseif old[i] ~= new[i] then
      table.insert(diffKeys, i)
    end
  end

  -- Check that there isn't anything missing.
  local oldCount = 0
  for i, v in pairs(old) do
    oldCount = oldCount + 1
  end

  if newCount ~= oldCount then
    return true, {}
  end

  return false, diffKeys
end

return miscUtils
