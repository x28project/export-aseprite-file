-- export.lua
-- Copyright (C) 2020  David Capello
--
-- This file is released under the terms of the MIT license.

local spr = app.activeSprite
if not spr then return print "No active sprite" end

if ColorMode.TILEMAP == nil then ColorMode.TILEMAP = 4 end
assert(ColorMode.TILEMAP == 4)

local fs = app.fs
local pc = app.pixelColor
local output_folder = fs.filePath(spr.filename)
local image_n = 0
local tileset_n = 0

local function write_json_data(filename, data)
  local json = dofile('./json.lua')
  local file = io.open(filename, "w")
  file:write(json.encode(data))
  file:close()
end

local function fill_user_data(t, obj)
  if obj.color.alpha > 0 then
    if obj.color.alpha == 255 then
      t.color = string.format("#%02x%02x%02x",
                              obj.color.red,
                              obj.color.green,
                              obj.color.blue)
    else
      t.color = string.format("#%02x%02x%02x%02x",
                              obj.color.red,
                              obj.color.green,
                              obj.color.blue,
                              obj.color.alpha)
    end
  end
  if pcall(function() return obj.data end) then -- a tag doesn't have the data field pre-v1.3
    if obj.data and obj.data ~= "" then
      t.data = obj.data
    end
  end
end

local function export_tileset(tileset, layer)
  local t = {}
  local grid = tileset.grid
  local size = grid.tileSize
  t.firstgid = 1
  t.image = fs.fileTitle(spr.filename) .. layer.name .. "Tileset" .. ".png"
  t.imagewidth = size.width
  t.imageheight = size.height * #tileset
  t.name = fs.fileTitle(spr.filename) .. layer.name .. "Tileset"
  t.tilewidth = size.width
  t.tileheight = size.height
  if #tileset > 0 then
    local spec = spr.spec
    spec.width = size.width
    spec.height = size.height * #tileset
    local image = Image(spec)
    image:clear()
    for i = 0,#tileset-1 do
      local tile = tileset:getTile(i)
      image:drawImage(tile, 0, i*size.height)
    end

    tileset_n = tileset_n + 1
    local imageFn = fs.joinPath(output_folder, fs.fileTitle(spr.filename) .. layer.name .. "Tileset" .. ".png")
    image:saveAs(imageFn)
  end
  return t
end

local function export_tilesets(tilesets, layer)
  local t = {}
  for _,tileset in ipairs(tilesets) do
    table.insert(t, export_tileset(tileset, layer))
  end
  return t
end

local function export_frames(frames)
  local t = {}
  for _,frame in ipairs(frames) do
    table.insert(t, { duration=frame.duration })
  end
  return t
end

local function export_cel(cel, layer)
  local t = {
    frame=cel.frameNumber-1,
    bounds={ x=cel.bounds.x,
             y=cel.bounds.y,
             width=cel.bounds.width,
             height=cel.bounds.height }
  }

  if cel.image.colorMode == ColorMode.TILEMAP then
    local tilemap = cel.image
    -- save tilemap
    t.tilemap = { width=tilemap.width,
                  height=tilemap.height,
                  tiles={} }
    for it in tilemap:pixels() do
      table.insert(layer.data, pc.tileI(it()) + 1)
    end
  else
    -- save regular cel
    image_n = image_n + 1
    local imageFn = fs.joinPath(output_folder, "image" .. image_n .. ".png")
    cel.image:saveAs(imageFn)
    t.image = imageFn
  end

  fill_user_data(t, cel)
  return t
end

local function export_cels(cels, layer)
  local t = {}
  for _,cel in ipairs(cels) do
    table.insert(t, export_cel(cel, layer))
  end
  return t
end

local function get_tileset_index(layer)
  for i,tileset in ipairs(layer.sprite.tilesets) do
    if layer.tileset == tileset then
      return i-1
    end
  end
  return -1
end

local function export_layer(layer, export_layers)
  local t = { 
    name=fs.fileTitle(spr.filename) .. layer.name,
    data={},
    opacity=layer:cel(1).opacity,
    type="tilelayer",
    width=layer:cel(1).image.width,
    height=layer:cel(1).image.height,
    x=layer:cel(1).position.x,
    y=layer:cel(1).position.y
  }
  if layer.isImage then
    if layer.opacity < 255 then
      t.opacity = layer.opacity
    end
    if layer.blendMode ~= BlendMode.NORMAL then
      t.blendMode = layer.blendMode
    end
    local tilemap = layer:cel(1).image
    -- save tilemap
    t.data = {}
    for it in tilemap:pixels() do
      table.insert(t.data, pc.tileI(it()) + 1)
    end
  elseif layer.isGroup then
    t.layers = export_layers(layer.layers)
  end
  fill_user_data(t, layer)
  return t
end

local function export_layers(layers)
  local t = {}
  for _,layer in ipairs(layers) do
    if layer.isVisible == true then
      table.insert(t, export_layer(layer, export_layers))
    end
  end
  return t
end

local function ani_dir(d)
  local values = { "forward", "reverse", "pingpong" }
  return values[d+1]
end

local function export_tag(tag)
  local t = {
    name=tag.name,
    from=tag.fromFrame.frameNumber-1,
    to=tag.toFrame.frameNumber-1,
    aniDir=ani_dir(tag.aniDir)
  }
  fill_user_data(t, tag)
  return t
end

local function export_tags(tags)
  local t = {}
  for _,tag in ipairs(tags) do
    table.insert(t, export_tag(tag, export_tags))
  end
  return t
end

local function export_slice(slice)
  local t = {
    name=slice.name,
    bounds={ x=slice.bounds.x,
             y=slice.bounds.y,
             width=slice.bounds.width,
             height=slice.bounds.height }
  }
  if slice.center then
    t.center={ x=slice.center.x,
               y=slice.center.y,
               width=slice.center.width,
               height=slice.center.height }
  end
  if slice.pivot then
    t.pivot={ x=slice.pivot.x,
               y=slice.pivot.y }
  end
  fill_user_data(t, slice)
  return t
end

local function export_slices(slices)
  local t = {}
  for _,slice in ipairs(slices) do
    table.insert(t, export_slice(slice, export_slices))
  end
  return t
end

----------------------------------------------------------------------
-- Creates output folder

fs.makeDirectory(output_folder)

----------------------------------------------------------------------
-- Write /Map.json file in the output folder

if app.range.type == RangeType.LAYERS then
  for _,layer in ipairs(app.range.layers) do
    local jsonFn = fs.joinPath(output_folder, fs.fileTitle(spr.filename) .. layer.name .. ".json")
    local data = {
      orientation = "orthogonal",
      width = spr.width / layer.tileset.grid.tileSize.width,
      height = spr.height / layer.tileset.grid.tileSize.height,
      tilewidth = layer.tileset.grid.tileSize.width,
      tileheight = layer.tileset.grid.tileSize.height,
      layers = export_layers({layer})
    }
    data.tilesets = export_tilesets({layer.tileset}, layer)
    write_json_data(jsonFn, data)
  end
else
  local jsonFn = fs.joinPath(output_folder, fs.fileTitle(spr.filename) .. app.activeLayer.name .. ".json")
  local data = {
    -- filename=spr.filename,
    orientation = "orthogonal",
    width = spr.width / app.activeLayer.tileset.grid.tileSize.width,
    height = spr.height / app.activeLayer.tileset.grid.tileSize.height,
    tilewidth = app.activeLayer.tileset.grid.tileSize.width,
    tileheight = app.activeLayer.tileset.grid.tileSize.height,
    -- frames=export_frames(spr.frames),
    layers = export_layers({app.activeLayer})
  }
  if pcall(function() return spr.tilesets end) then
    data.tilesets = export_tilesets({app.activeLayer.tileset}, app.activeLayer)
  end
  write_json_data(jsonFn, data)
end
