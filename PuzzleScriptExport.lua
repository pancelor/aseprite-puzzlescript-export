-- PuzzleScript Export
--  by pancelor, 2022-02-01
--  pancelor.com

-- handy link to the aseprite api docs:
-- https://www.aseprite.org/api/

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

local qindent = 0
local function qq(...)
  local tbl = {...}
  local s = ""
  for i = 1,#tbl do
    local o = tbl[i]
    if type(o)=='table' then
      s = s..'{\n'
      qindent = qindent+2
      assert(qindent<50)
      local tab = string.rep(" ",qindent)
      for k,v in pairs(o) do
        s = s..tab..k..' = '..qq(v)..'\n'
      end
      qindent = qindent-2
      s = s..string.rep(" ",qindent)..'} '
    else
      s = s..tostring(o).." "
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

-- returns the first index in arr where arr[index]==target
function find(arr,target)
  for k,v in ipairs(arr) do
    if v==target then return k,v end
  end
end
-- returns any key in arr s.t fn(value) is truthy
function findby(arr,fn)
  for k,v in ipairs(arr) do
    if fn(v) then return k,v end
  end
end

local function add(tab,elem)
  table.insert(tab,elem)
  return elem
end
local function deli(tab, ix)
  return table.remove(tab,ix)
end

local function mid(a,b,c)
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

-- note: this counter doesn't reset between exports
-- (good, I think?)
local _id = 0
local function getId()
  _id = _id+1
  return _id
end

-- converts a single "zone" into a string
local function exportZone(img,zone)
  assert(img.colorMode==ColorMode.RGB)
  -- pq("exportZone",zone)

  local pal = {} -- array of colors
  local body = ""
  for y = zone.bounds.y,zone.bounds.y+zone.bounds.height-1 do
    for x = zone.bounds.x,zone.bounds.x+zone.bounds.width-1 do
      -- pqt = x==0 and y==0 and pq or function()end
      local inbounds = mid(0,img.width-1,x)==x and mid(0,img.height-1,y)==y
      local col32 = inbounds and img:getPixel(x,y) or 0

      local hexcode,transparent
      do
        -- note: col32 is a 32-bit int, even if app.activeSprite.colorMode is indexed
        -- so Color(col32) does not work -- it will misinterpret indexed images
        -- https://www.aseprite.org/api/color#color
        local rr = app.pixelColor.rgbaR(col32)
        local gg = app.pixelColor.rgbaG(col32)
        local bb = app.pixelColor.rgbaB(col32)
        local aa = app.pixelColor.rgbaA(col32)
        hexcode = string.format("#%02x%02x%02x", rr, gg, bb)
        transparent = aa==0
        -- pq(string.format("#%08x @ %d,%d",col32,x,y),"|",rr,gg,bb,aa)
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
    end
    body = body.."\n"
  end

  if #pal>10 then
    print("error: more than 10 colors in sprite at ("..zone.bounds.x..","..zone.bounds.y..")")
    return ""
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

local function tilemapToImage(imgSrc, tileset, colorMode)
  assert(imgSrc.colorMode==ColorMode.TILEMAP,"can only call on tilemap")

  local size = tileset.grid.tileSize

  local imgDstSpec = ImageSpec(imgSrc.spec)
  imgDstSpec.colorMode = colorMode
  imgDstSpec.width  = imgSrc.width *size.width
  imgDstSpec.height = imgSrc.height*size.height

  local imgDst = Image(imgDstSpec)
  for it in imgSrc:pixels() do
    local tileimg = tileset:getTile(it())
    imgDst:drawImage(tileimg,it.x*size.width,it.y*size.height)
  end
  return imgDst
end

local function weirdImagetoRgbImage(imgSrc)
  assert(imgSrc.colorMode==ColorMode.INDEXED or imgSrc.colorMode==ColorMode.GRAYSCALE,"can only call on indexed or grayscale images")

  local imgDstSpec = ImageSpec(imgSrc.spec)
  imgDstSpec.colorMode = ColorMode.RGB

  -- local posSrc = imgSrc.cel.position --todo?
  local posSrc = Point(0,0)

  local imgDst = Image(imgDstSpec)
  for it in imgSrc:pixels() do
    if it()~=imgSrc.spec.transparentColor then
      local col = Color(it())
      -- pq("pixel",it(),col.red,col.blue,col.green,col.alpha)
      imgDst:drawPixel(posSrc.x+it.x,posSrc.y+it.y,col)
    end
  end
  return imgDst
end

--[[
# script
]]

-- returns a list of "zones" that fit into the current selection of the active sprite
--   a "zone" is a {name = <string>, bounds = <Rectangle>} object
-- sel may be non-rectangular (e.g. multiple rectangles)
--   but support isn't great (e.g. the grid anchor will not reset between
--   multiple selections)
local function gatherZones(gridtype)
  local sprite = app.activeSprite
  local zones = {}

  local sel = sprite.selection
  -- rect: the subrectangle to export tiles from
  local rect = sel.isEmpty and sprite.bounds or sel.bounds
  local zonew
  local zoneh
  if gridtype=="5x5" then
    zonew = 5
    zoneh = 5
    -- if your selection isn't exact multiples of 5, extra tiles will be created
    -- on the edge. these tiles will be a full 5x5
  elseif gridtype=="aseprite grid" then
    zonew = sprite.gridBounds.width
    zoneh = sprite.gridBounds.height
    -- selection correction
    -- pq(rect)
    local x1 = math.floor(rect.x/zonew)*zonew
    local y1 = math.floor(rect.y/zoneh)*zoneh
    local x2 = math.ceil((rect.x+rect.width-1)/zonew)*zonew
    local y2 = math.ceil((rect.y+rect.height-1)/zoneh)*zoneh
    -- pq(x1,y1,x2,y2)
    rect = Rectangle(x1,y1,x2-x1,y2-y1)
    -- pq(rect)
  elseif gridtype=="slices" then
    for i,slice in ipairs(sprite.slices) do
      if rect:contains(slice.bounds) then
        add(zones,{
          name = slice.name:gsub(" ","_"),
          bounds = slice.bounds,
        })
      end
    end
    return zones
  end

  for y = rect.y,rect.y+rect.height-1,zoneh do
    for x = rect.x,rect.x+rect.width-1,zonew do
      local name = "aseprite"..getId()
      add(zones,{
        name = name,
        bounds = Rectangle{
          x = x,
          y = y,
          width = zonew,
          height = zoneh,
        },
      })
    end
  end
  return zones
end

-- create an rgb image from the current sprite
-- properly handles tilemaps
-- properly handles indexed/grayscale images
local function prepareImage(layeronly)
  local res
  if app.activeImage.colorMode==ColorMode.TILEMAP and layeronly then
    local ti,tileset = find(app.activeSprite.tilesets,app.activeLayer.tileset)
    assert(tileset)

    res = tilemapToImage(app.activeImage,tileset,app.activeSprite.colorMode)
  else
    res = Image(app.activeSprite.spec)
    if layeronly then
      res:drawImage(app.activeCel.image,app.activeCel.position)
    else
      res:drawSprite(app.activeSprite,app.activeFrame)
      assert(res.colorMode~=ColorMode.TILEMAP)
    end
  end

  if res.colorMode==ColorMode.INDEXED or res.colorMode==ColorMode.GRAY then
    res = weirdImagetoRgbImage(res)
  end

  assert(res.colorMode==ColorMode.RGB)
  return res
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
  local result = {}
  for i,zone in ipairs(zones) do
    local str = exportZone(img,zone)
    if str then
      add(result,str)
    end
  end
  return result
end

--[[
# main
]]

local dlg = Dialog("PuzzleScript Export")
dlg:combobox{
  id      = "gridtype",
  label   = "grid type",
  option  = defaultGridType(),
  options = {"5x5", "aseprite grid", "slices"},
}
dlg:check{
  id       = "layeronly",
  label    = "active layer only",
  selected = false,
}
dlg:button{text = "Export", onclick = function()
  -- clear output, in case we're interrupted by errors
  dlg:modify{id = "output", label = "", text = ""}

  local gridtype,layeronly = dlg.data.gridtype,dlg.data.layeronly

  if not app.activeSprite then return app.alert("error: no sprite found") end

  local zones = gatherZones(gridtype)
  local imgRGB = prepareImage(layeronly)
  local tiles = exportZones(imgRGB,zones)

  -- set output
  local label = string.format("output (%d)",#tiles)
  local text = table.concat(tiles,"\n")
  dlg:modify{
    id      = "output",
    label   = label,
    text    = text,
    focus   = true,
    visible = true,
  }
end}
dlg:entry{
  id      = "output",
  label   = "output",
  text    = "",
  focus   = false,
  visible = false,
}
dlg:show{wait = false}
