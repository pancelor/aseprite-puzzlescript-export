-- PuzzleScript Export
--  by pancelor, 2022-02-01

--[[
# debugging / helpers
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

-- this doesn't reset between exports
-- that's a good thing, I think
_id=0
local function getId()
  _id=_id+1
  return _id
end

local function includes(tbl,elem)
  for k,v in pairs(tbl) do
    if v==elem then return k end
  end
end

--[[
# script
]]

local function getTileDataString(img,x,y,w,h,prefix)
  -- pq("getTileDataString",x,y,w,h)
  local pal = {} -- array of colors
  local body = ""
  for ty = 0,h-1 do
    for tx = 0,w-1 do
      local hexcode,transparent
      do
        local rgba = img:getPixel(x+tx, y+ty)
        local RR = app.pixelColor.rgbaR(rgba)
        local GG = app.pixelColor.rgbaG(rgba)
        local BB = app.pixelColor.rgbaB(rgba)
        local AA = app.pixelColor.rgbaA(rgba)
        hexcode = string.format("#%02x%02x%02x", RR, GG, BB)
        transparent = AA==0
        -- pq("rgba",RR,GG,BB,AA,transparent)
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

      body = body .. code
    end
    body = body .. "\n"
  end

  if #pal>0 then
    local header = prefix..getId() .. "\n"
    for i=1,#pal do
      header = header .. pal[i] .. " "
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
local function exportTiles(sprite,subrect,gridw,gridh,prefix)
  -- pq("exportTiles",subrect,gridw,gridh)
  local img = Image(sprite.spec)
  img:drawSprite(sprite, 1)

  local result = {}
  for y = subrect.y,subrect.y+subrect.height-gridh,gridh do
    for x = subrect.x,subrect.x+subrect.width-gridw,gridw do
      local str = getTileDataString(img,x,y,gridw,gridh,prefix)
      if str then
        table.insert(result,str)
      end
    end
  end
  return result
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
local function export(filename,usegrid,prefix)
  local sprite = app.activeSprite
  -- Check constrains
  if sprite == nil then
    app.alert("No Sprite...")
    return
  end
  if sprite.colorMode ~= ColorMode.RGB then
    -- not strictly necessary, but I haven't coded the alternatives
    app.alert("Sprite needs to be RGB")
    return
  end

  local gridw=5
  local gridh=5
  local subrect = sprite.selection.isEmpty and sprite.bounds or sprite.selection.bounds
  if usegrid then
    gridw=sprite.gridBounds.width
    gridh=sprite.gridBounds.height
    local oldx = subrect.x
    local oldy = subrect.y
    subrect.x=math.ceil(subrect.x/gridw)*gridw
    subrect.y=math.ceil(subrect.y/gridh)*gridh
    subrect.width=subrect.width-(subrect.x-oldx)
    subrect.height=subrect.height-(subrect.y-oldy)
  end
  -- note: subrect might not be an exact multiple of {gridw, gridh}

  local tiles = exportTiles(sprite,subrect,gridw,gridh,prefix)
  writeTiles(tiles,filename)
  print("exported "..(#tiles).." tiles")
end

--[[
# main
]]

local dlg = Dialog("PuzzleScript Export")
dlg:file{
  id="exportFile",
  label="File",
  title="PuzzleScript Export",
  save=true,
  filetypes={"txt"},
}
dlg:entry{
  id="prefix",
  label="prefix",
  text="tile",
}
dlg:check{
  id="usegrid",
  text="use aseprite grid",
  selected=true,
}
dlg:button{text="Export", onclick=function()
  local filename,usegrid,prefix = dlg.data.exportFile,dlg.data.usegrid,dlg.data.prefix
  if #filename>0 then
    export(filename,usegrid,prefix)
  else
    print("no file chosen")
  end
end}
dlg:show{wait=false}
