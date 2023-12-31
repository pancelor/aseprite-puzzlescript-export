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

the tilemap docs don't exist yet, but see this example:
https://github.com/dacap/export-aseprite-file/
(via https://github.com/aseprite/api/issues/66)
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
local function find(arr,target)
  for k,v in ipairs(arr) do
    if v==target then return k,v end
  end
end
-- returns any key in arr s.t fn(value) is truthy
local function findby(arr,fn)
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
local _id = -1
local function getId()
  _id = _id+1
  return _id
end

-- convert a name into a valid puzzlescript spritename
-- note: not very robust
-- mainly just intended to easy-fix filenames
local function sanitizeName(name)
  return name:gsub("[ -.]","_")
  -- return name:gsub("[%p%s]","_")
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

  local imgDst = Image(imgDstSpec)
  for it in imgSrc:pixels() do
    if it()~=imgSrc.spec.transparentColor then
      local col = Color(it())
      -- pq("pixel",it(),col.red,col.blue,col.green,col.alpha)
      imgDst:drawPixel(it.x,it.y,col)
    end
  end
  return imgDst
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

      local hexcode,trans do
        -- note: col32 is a 32-bit int, even if app.activeSprite.colorMode is indexed
        -- so Color(col32) does not work -- it will misinterpret indexed images
        -- https://www.aseprite.org/api/color#color
        local rr = app.pixelColor.rgbaR(col32)
        local gg = app.pixelColor.rgbaG(col32)
        local bb = app.pixelColor.rgbaB(col32)
        local aa = app.pixelColor.rgbaA(col32)
        hexcode = string.format("#%02x%02x%02x", rr, gg, bb)
        trans = aa==0
        -- pq(string.format("#%08x @ %d,%d",col32,x,y),"|",rr,gg,bb,aa)
      end

      local code
      if trans then
        code = "."
      else
        local index = find(pal,hexcode)
        if not index then
          add(pal,hexcode)
          index = #pal
        end
        code = index-1
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

--[[
# script
]]

-- see gatherZones
local function _gatherZonesFromGrid(data)
  for y = data.rect.y,data.rect.y+data.rect.height-1,data.gridheight do
    for x = data.rect.x,data.rect.x+data.rect.width-1,data.gridwidth do
      local id = getId()-(data.idOffset or 0)
      add(data.zones,{
        name = data.prefix..tostring(id),
        bounds = Rectangle{
          x = x,
          y = y,
          width = data.gridwidth,
          height = data.gridheight,
        },
      })
    end
  end
end

-- returns a list of "zones" that fit into the current selection of the active sprite
--   a "zone" is a {name = <string>, bounds = <Rectangle>} object
-- sel may be non-rectangular (e.g. multiple rectangles)
--   but support isn't great (e.g. the grid anchor will not reset between
--   multiple selections)
local function gatherZones(data)
  local prefix = data.prefix or "sprite"
  local zones = {}
  local sel = app.activeSprite.selection
  -- rect: the subrectangle to export tiles from
  local rect = sel.isEmpty and app.activeSprite.bounds or sel.bounds

  if data.source=="grid" then
    -- selection correction
    -- if the selection isn't an exact multiples of 5x5,
    -- the edge tiles will expand to full 5x5
    local x1 = math.floor(rect.x/data.gridwidth)*data.gridwidth
    local y1 = math.floor(rect.y/data.gridheight)*data.gridheight
    local x2 = math.ceil((rect.x+rect.width)/data.gridwidth)*data.gridwidth
    local y2 = math.ceil((rect.y+rect.height)/data.gridheight)*data.gridheight
    -- pq(rect)
    -- pq(x1,y1,x2,y2)
    rect = Rectangle(x1,y1,x2-x1,y2-y1)
    -- pq(rect)

    _gatherZonesFromGrid{
      zones=zones,
      prefix=prefix,
      rect=rect,
      gridwidth=data.gridwidth,
      gridheight=data.gridheight,
    }
  elseif data.source=="slices" then
    for i,slice in ipairs(app.activeSprite.slices) do
      if rect:contains(slice.bounds) then
        if data.subdivide then
          _gatherZonesFromGrid{
            zones=zones,
            prefix=slice.name,
            rect=slice.bounds,
            gridwidth=data.gridwidth,
            gridheight=data.gridheight,
            idOffset=_id+1, -- HACK: make ids start at 0 for each slice
          }
        else
          add(zones,{
            name = slice.name,
            bounds = slice.bounds,
          })
        end
      end
    end
  else
    assert(nil,"bad source: "..tostring(data.source))
  end
  return zones
end

-- create an rgb image from the current sprite
-- properly handles tilemaps
-- properly handles indexed/grayscale images
local function spriteToRgbImage(layeronly)
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


local hasSlices = #app.activeSprite.slices>0
local dlg = Dialog("PuzzleScript Export")

-- TODO maybe this visibility stuff would be more understandable as
-- one tab for slices and one tab for grid. (and modify enabled instead of visible)
function updateDlgVisibility()
  dlg:modify{id = 'gridwidth',  visible = dlg.data.source=='grid' or dlg.data.subdivide}
  dlg:modify{id = 'gridheight', visible = dlg.data.source=='grid' or dlg.data.subdivide}
  dlg:modify{id = 'subdivide',  visible = dlg.data.source=='slices'}
  dlg:modify{id = 'prefix',     visible = dlg.data.source=='grid'}
end

dlg:combobox{
  id       = 'source',
  label    = 'Source',
  option   = hasSlices and 'slices' or 'grid',
  options  = {'grid', 'slices'},
  onchange = function()
    updateDlgVisibility()
  end,
}
dlg:check{
  id      = 'subdivide',
  label   = 'Subdivide slices',
  onclick = function()
    updateDlgVisibility()
  end,
}
do
  -- grid size
  local gb = app.activeSprite.gridBounds
  local default = gb.width==16 and gb.height==16
  dlg:number{
    id       = 'gridwidth',
    label    = 'Grid size',
    text     = tostring(default and 5 or gb.width),
    decimals = 0,
    -- onchange = function()
    --   if dlg.data.gridwidth<1 then
    --     dlg:modify{id='gridwidth', text='1'}
    --   end
    -- end
  }
  dlg:number{
    id       = 'gridheight',
    text     = tostring(default and 5 or gb.height),
    decimals = 0,
    -- onchange = function()
    --   if dlg.data.gridheight<1 then
    --     dlg:modify{id='gridheight', text='1'}
    --   end
    -- end
  }
end
dlg:entry{
  id       = 'prefix',
  label    = 'Name prefix',
  text     = sanitizeName(app.fs.fileTitle(app.activeSprite.filename or 'aseprite')),
  -- onchange = function()
  --   dlg:modify{
  --     id   = 'prefix',
  --     text = sanitizeName(dlg.data.prefix),
  --   }
  -- end,
}
dlg:check{
  id       = 'layeronly',
  label    = 'Active layer only',
  selected = true,
}
dlg:button{text = "&Export", onclick = function()
  -- clear output, in case we're interrupted by errors
  dlg:modify{id = "output", label = "", text = ""}

  if not app.activeSprite then return app.alert("error: no sprite found") end

  local zones = gatherZones{
    source     = dlg.data.source,
    subdivide  = dlg.data.subdivide,
    gridwidth  = dlg.data.gridwidth,
    gridheight = dlg.data.gridheight,
    prefix     = dlg.data.prefix,
  }
  local imgRGB = spriteToRgbImage(dlg.data.layeronly)
  local tiles = exportZones(imgRGB,zones)

  -- set output
  local label = string.format("Output (%d)",#tiles)
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
  label   = "Output",
  text    = "",
  focus   = false,
  visible = false,
}

updateDlgVisibility()
dlg:show{wait = false}
