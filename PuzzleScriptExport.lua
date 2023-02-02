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
local function qq(...)
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
local function pq(...)
  print(qq(...))
end
local function qa(l)
  return "{"..table.concat(l,",").."}"
end

-- returns any key in tab s.t tab[key]==x
local function find(tab,x)
  for k,v in pairs(tab) do
    if v==x then return k end
  end
end
local function ifind(tab,x)
  for i=1,#tab do
    if tab[i]==x then return i end
  end
end

local function add(tab,elem)
  table.insert(tab,elem)
  return elem
end
local function deli(tab,ix)
  return table.remove(tab,ix)
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

  local pal={} -- array of colors
  local body=""
  for it in img:pixels(zone.bounds) do
    -- pqt = it.x==0 and it.y==0 and pq or function()end

    local hexcode,transparent
    do
      -- note: pix is a 32-bit int, even if app.activeSprite.colorMode is indexed
      -- so Color(pix) does not work -- it will misinterpret indexed images
      -- https://www.aseprite.org/api/color#color
      local rr = app.pixelColor.rgbaR(it())
      local gg = app.pixelColor.rgbaG(it())
      local bb = app.pixelColor.rgbaB(it())
      local aa = app.pixelColor.rgbaA(it())
      hexcode = string.format("#%02x%02x%02x", rr, gg, bb)
      transparent = aa==0
      -- pq(string.format("#%08x",pix),"|",rr,gg,bb,aa)
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
        add(pal,hexcode)
        code = #pal-1
      end
    end

    body = body..code
    if it.x == zone.bounds.width-1 then
      body = body.."\n"
    end
  end

  if #pal>10 then
    print("error: more than 10 colors in sprite at x="..x.." y="..y)
  end

  if #pal>0 then
    return zone.name.."\n"..table.concat(pal," ").."\n"..body
  end
end

local function defaultGridType()
    -- todo: would be great to check something like
    -- "if app.activeSprite.gridVisible then"
    -- but I don't see anything like that in the API
  local gb = app.activeSprite.gridBounds
  local gridVisible = gb.width~=16 or gb.height~=16

  if #app.activeSprite.slices>0 then
    return "slices"
  elseif gridVisible then
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
    local x1=math.floor(rect.x/zonew)*zonew
    local y1=math.floor(rect.y/zoneh)*zoneh
    local x2=math.ceil((rect.x+rect.width-1)/zonew)*zonew
    local y2=math.ceil((rect.y+rect.height-1)/zoneh)*zoneh
    -- pq(x1,y1,x2,y2)
    rect = Rectangle(x1,y1,x2-x1,y2-y1)
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

local dlg = Dialog("PuzzleScript Export")
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
  local gridtype,layeronly = dlg.data.gridtype,dlg.data.layeronly

  if not app.activeSprite then return app.alert("error: no sprite found") end

  local zones = gatherZones(app.activeSprite,gridtype)
  local img = prepareImage(app.activeSprite,layeronly)
  local tiles = exportZones(img,zones)

  local label = string.format("output (%d)",#tiles)
  local text = table.concat(tiles,"\n")
  dlg:modify{
    id="output",
    label=label,
    text=text,
    focus=true,
    visible=true,
  }
end}
dlg:entry{
  id="output",
  label="output",
  text="",
  focus=false,
  visible=false,
}
dlg:show{wait=false}
