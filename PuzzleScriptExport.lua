-- PuzzleScript Export
--  by pancelor, 2022-02-01

-- handy link to the aseprite api docs:
-- https://github.com/aseprite/api/

--[[
# debugging
]]

local function quote(...)
  local tbl={...}
  local s=""
  for i=1,#tbl do
    local o=tbl[i]
    if type(o) == 'table' then
      s=s..'{ '
      for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s=s ..'['..k..'] = '..quote(v)..','
      end
      s=s..'}, '
    else
      s=s..tostring(o)..", "
    end
  end
  return s
end
local function pq(...)
  print(quote(...))
end

local function includes(tbl,elem)
  for k,v in pairs(tbl) do
    if v==elem then return k end
  end
end

--[[
# helpers
]]

-- this doesn't reset between exports
-- that's a good thing, I think
_id=0
local function getId()
  _id=_id+1
  return _id
end

-- create an image that we can extract colors from
function prepareImage(sprite,layeronly)
  local img=Image(sprite.spec)
  if layeronly then
    local cel=app.activeCel
    if not app.activeCel then
      app.alert("error: current layer is empty")
      return
    end
    img:drawImage(app.activeCel.image, app.activeCel.position)
  else
    img:drawSprite(sprite, app.activeFrame)
  end
  return img
end

local function getTileDataString(img,zone)
  -- pq("getTileDataString",zone)
  local x=zone.bounds.x
  local y=zone.bounds.y
  local w=zone.bounds.width
  local h=zone.bounds.height

  local pal = {} -- array of colors
  local body = ""
  for ty = 0,h-1 do
    for tx = 0,w-1 do
      local hexcode,transparent
      do
        local pix = img:getPixel(x+tx, y+ty)
        local color = Color(pix)
        hexcode = string.format("#%02x%02x%02x", color.red, color.green, color.blue)
        transparent = color.alpha==0 or pix==0
        -- pq(pix,"|",color.red,color.green,color.blue,color.alpha)
      end

      local code
      if transparent then
        code = "."
      else
        local existing = includes(pal,hexcode)
        if existing then
          -- old color
          code = existing-1
        else
          -- new color found
          code = #pal
          table.insert(pal,hexcode)
        end
      end

      body = body..code
    end
    body = body.."\n"
  end

  if #pal>0 then
    local header = zone.name.."\n"
    for i=1,#pal do
      header = header..pal[i].." "
    end
    return header.."\n"..body
  end
end

-- returns a list of strings
-- each string looks something like this:
--   tile12
--   #ff8000 #00ff80
--   ..010
--   .0010
--   00110
--   0110.
--   110..
local function exportTiles(img,zones)
  local result={}
  for i,zone in ipairs(zones) do
    local str = getTileDataString(img,zone)
    if str then
      table.insert(result,str)
    end
  end
  return result
end

-- returns a list of "zones" that fit into the current selection of sprite
--   a "zone" is a {name=<string>,bounds=<Rectangle>} object
-- sel may be non-rectangular (e.g. multiple rectangles)
--   but support isn't great (e.g. the grid anchor will not reset between
--   multiple selections)
function findZones(sprite,gridtype,prefix)
  local zones={}

  local sel=sprite.selection
  -- rect: the subrectangle to export tiles from
  local rect=sel.isEmpty and sprite.bounds or sel.bounds
  local zonew
  local zoneh
  if gridtype=="5x5" then
    zonew=5
    zoneh=5
  elseif gridtype=="aseprite grid" then
    zonew=sprite.gridBounds.width
    zoneh=sprite.gridBounds.height
    local oldx = rect.x
    local oldy = rect.y
    rect.x=math.ceil(rect.x/zonew)*zonew
    rect.y=math.ceil(rect.y/zoneh)*zoneh
    rect.width=rect.width-(rect.x-oldx)
    rect.height=rect.height-(rect.y-oldy)
  elseif gridtype=="slices" then
    -- note ignores selection
    for i,slice in ipairs(sprite.slices) do
      table.insert(zones,{
        name=slice.name,
        bounds=slice.bounds,
      })
    end
    return zones
  end

  -- each zone.bounds.width/height will be zonew/zoneh
  -- any leftover space in sel (not enough for a full zonew x zoneh zone)
  --   will be ignored
  for y=rect.y,rect.y+rect.height-1,zoneh do
    for x=rect.x,rect.x+rect.width-1,zonew do
      if sel.isEmpty or (sel:contains(x,y) and sel:contains(x+zonew-1,y+zoneh-1)) then
        table.insert(zones,{
          name=prefix..getId(),
          bounds=Rectangle{x=x,y=y,width=zonew,height=zoneh},
        })
      end
    end
  end
  return zones
end

-- writes a list of strings to the given file
local function writeTiles(tiles,filename)
  local f = io.open(filename, "w")
  io.output(f)

  for i = 1,#tiles do
    io.write(tiles[i])
    io.write("\n")
  end

  io.close(f)
end

-- the main function; this organizes the settings and then
-- calls exportTiles() and writeTiles()
local function export(filename,gridtype,prefix,layeronly)
  local sprite = app.activeSprite
  -- Check constrains
  if sprite == nil then
    app.alert("error: no sprite found")
    return
  end

  local zones = findZones(sprite,gridtype,prefix)
  local img = prepareImage(sprite,layeronly)
  if img then
    local tiles = exportTiles(img,zones)
    writeTiles(tiles,filename)

    app.alert((#tiles).." tiles exported")
  end
end

--[[
# main
]]

function defaultGridType()
  if #app.activeSprite.slices>0 then
    return "slices"
  elseif app.activeSprite.gridBounds.width~=16 then
    return "aseprite grid"
  else
    return "5x5"
  end
end

local dlg = Dialog("PuzzleScript Sprite Export")
dlg:file{
  id="exportFile",
  label="File",
  title="PuzzleScript Export",
  save=true,
  filetypes={"txt"},
}
dlg:combobox{
  id="gridtype",
  label="grid type",
  option=defaultGridType(),
  options={ "5x5","aseprite grid","slices" },
}
dlg:check{
  id="layeronly",
  label="active layer only",
}
dlg:button{text="Export", onclick=function()
  local filename,gridtype,prefix,layeronly = dlg.data.exportFile,dlg.data.gridtype,"aseprite",dlg.data.layeronly
  if #filename>0 then
    export(filename,gridtype,prefix,layeronly)
  else
    app.alert("error: no file chosen")
  end
end}
dlg:show{wait=false}
