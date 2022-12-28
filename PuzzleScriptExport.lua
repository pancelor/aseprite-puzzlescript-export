-- PuzzleScript Export
--  by pancelor, 2022-02-01

-- handy link to the aseprite api docs:
-- https://www.aseprite.org/api/
-- https://github.com/aseprite/api/

--[[
note: this extenstion does not deal with making maps using the aseprite
"tilemap" feature I don't think it would fit into my personal workflow --
sometimes you want to make tweaks in the official editor, and how would
you import those back into aseprite? it's doable, but it sounds awkward

is it useful enough to add anyway? eh, maybe

the docs don't exist yet, but see https://github.com/aseprite/api/issues/66
]]



--[[
# libpance
]]

local qindent=0
function qq(...)
  local tbl={...}
  local s=""
  for i=1,#tbl do
    local o=tbl[i]
    if type(o)=='table' then
      s=s..'{\n'
      qindent=qindent+2
      assert(qindent<50)
      local tab=string.rep(" ",qindent)
      for k,v in pairs(o) do
        s=s..tab..k..'='..qq(v)..'\n'
      end
      qindent=qindent-2
      s=s..string.rep(" ",qindent)..'} '
    else
      s=s..tostring(o).." "
    end
  end
  return s
end
function pq(...)
  print(qq(...))
end
function qa(l)
  return "{"..table.concat(l,",").."}"
end

-- returns any key in tab s.t tab[key]==x
function find(tab,x)
  for k,v in pairs(tab) do
    if v==x then return k end
  end
end
function ifind(tab,x)
  for i=1,#tab do
    if tab[i]==x then return i end
  end
end

function add(tab,elem)
  table.insert(tab,elem)
  return elem
end
function deli(tab,ix)
  return table.remove(tab,ix)
end

function mid(a,b,c)
  c=c or 0
  b=b or 1
  local ab,bc,ac=a<b,b<c,a<c
  if ab==bc then
    return b
  elseif bc==ac then
    return a
  else
    return c
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

-- convert a single "zone" into a string
local function exportZone(img,zone)
  -- pq("exportZone",zone)
  local x=zone.bounds.x
  local y=zone.bounds.y
  local w=zone.bounds.width
  local h=zone.bounds.height

  local pal = {} -- array of colors
  local body = ""
  for ty = 0,h-1 do
    for tx = 0,w-1 do
      -- pqt = ty==0 and tx==0 and pq or function()end

      local hexcode,transparent
      do
        local pix = img:getPixel(x+tx, y+ty)
        local color = Color(pix)
        hexcode = string.format("#%02x%02x%02x", color.red, color.green, color.blue)
        transparent = color.alpha==0 or pix==0
        -- pqt(pix,"|",color.red,color.green,color.blue,color.alpha)
      end

      local code
      if transparent then
        code = "."
      else
        local existing = find(pal,hexcode)
        if existing then
          -- old color
          code = existing-1
        else
          -- new color found
          code = #pal
          add(pal,hexcode)
        end
      end

      body = body..code
    end
    body = body.."\n"
  end

  if #pal>10 then
    print("error: too many colors in sprite at x="..x.." y="..y)
  end

  if #pal>0 then
    local header = zone.name.."\n"
    for i=1,#pal do
      header = header..pal[i].." "
    end
    return header.."\n"..body
  end
end

local function defaultGridType()
  if #app.activeSprite.slices>0 then
    return "slices"
  elseif app.activeSprite.gridBounds.width~=16 then
    return "aseprite grid"
  else
    return "5x5"
  end
end

--[[
# script
]]

-- returns a list of "zones" that fit into the current selection of sprite
--   a "zone" is a {name=<string>,bounds=<Rectangle>} object
-- sel may be non-rectangular (e.g. multiple rectangles)
--   but support isn't great (e.g. the grid anchor will not reset between
--   multiple selections)
local function gatherZones(sprite,gridtype)
  local zones={}

  local sel=sprite.selection
  -- rect: the subrectangle to export tiles from
  local rect=sel.isEmpty and sprite.bounds or sel.bounds
  local zonew
  local zoneh
  if gridtype=="5x5" then
    zonew=5
    zoneh=5
    -- if your selection isn't exact multiples of 5, extra tiles will be created
    -- on the edge. these tiles will be a full 5x5
  elseif gridtype=="aseprite grid" then
    zonew=sprite.gridBounds.width
    zoneh=sprite.gridBounds.height
    -- selection correction
    -- pq(rect)
    local x1=math.ceil(rect.x/zonew)*zonew
    local y1=math.ceil(rect.y/zoneh)*zoneh
    local x2p=math.floor((rect.x+rect.width-1)/zonew)*zonew -- 1 past x2
    local y2p=math.floor((rect.y+rect.height-1)/zoneh)*zoneh
    rect = Rectangle(x1,y1,x2p-x1,y2p-y1)
    -- pq(rect)
  elseif gridtype=="slices" then
    for i,slice in ipairs(sprite.slices) do
      if rect:contains(slice.bounds) then
        add(zones,{
          name=slice.name,
          bounds=slice.bounds,
        })
      end
    end
    return zones
  end

  for y=rect.y,rect.y+rect.height-1,zoneh do
    for x=rect.x,rect.x+rect.width-1,zonew do
      local name="aseprite"..getId()
      local bounds=Rectangle{x=x,y=y,width=zonew,height=zoneh}
      add(zones,{
        name=name,
        bounds=bounds,
      })
    end
  end
  return zones
end

-- https://github.com/dacap/export-aseprite-file/blob/master/export.lua#L125-L132
local function get_tileset_for_layer(layer)
  for i,tileset in ipairs(layer.sprite.tilesets) do
    if layer.tileset == tileset then
      return tileset
    end
  end
end

-- there's gotta be a better way to convert a tilemap cel into pixels, right?
-- returns: an Image
local function renderTilemapCel(cel)
  local tilemap=cel.image
  assert(tilemap.colorMode==ColorMode.TILEMAP)
  assert(cel.sprite.tilesets)
  assert(#cel.sprite.tilesets>0,"error: no tilesets found on a tilemap layer")

  -- uhhh apparently this is 2 for me? very strange
  -- pq(#cel.sprite.tilesets)
  -- pq(cel.sprite.tilesets)
  -- assert(#cel.sprite.tilesets==1,"error: multiple tilesets is not supported")

  local tileset = get_tileset_for_layer(cel.layer)
  assert(tileset)
  local size = tileset.grid.tileSize
  local img = Image(tilemap.width*size.width,tilemap.height*size.height)
  for ty=0,tilemap.height-1 do
    for tx=0,tilemap.width-1 do
      local fakepixel=tilemap:getPixel(tx,ty)
      local tileix=app.pixelColor.tileI(fakepixel)
      local tileimg=tileset:getTile(tileix)
      img:drawImage(tileimg,tx*size.width,ty*size.height)
    end
  end
  return img
end

-- create an image that we can extract colors from
local function prepareImage(sprite,layeronly)
  local img=Image(sprite.width,sprite.height) --iirc we want this instead of sprite.spec to drop ColorMode info and become RGB
  if layeronly then
    if not app.activeCel then
      app.alert("error: current layer is empty")
      return
    end
    if app.activeCel.image.colorMode == ColorMode.TILEMAP then
      img:drawImage(renderTilemapCel(app.activeCel))
    else
      img:drawImage(app.activeCel.image, app.activeCel.position)
    end
  else
    img:drawSprite(sprite, app.activeFrame)
  end

  return img
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
local function exportZones(img,zones)
  local result={}
  for i,zone in ipairs(zones) do
    local str = exportZone(img,zone)
    if str then
      add(result,str)
    end
  end
  return result
end

-- writes a list of strings to the given file
local function writeZones(tiles,filename)
  if #filename==0 then return end

  local f = io.open(filename, "w")
  io.output(f)

  for i = 1,#tiles do
    io.write(tiles[i])
    io.write("\n")
  end

  io.close(f)
end

--[[
# main
]]

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
  local filename,gridtype,layeronly = dlg.data.exportFile,dlg.data.gridtype,dlg.data.layeronly

  if not app.activeSprite then return app.alert("error: no sprite found") end

  local zones = gatherZones(app.activeSprite,gridtype)
  local img = prepareImage(app.activeSprite,layeronly)
  local tiles = exportZones(img,zones)
  if #filename==0 then return app.alert("error: no file chosen") end
  writeZones(tiles,filename)

  app.alert((#tiles).." tiles exported")
end}
dlg:show{wait=false}
