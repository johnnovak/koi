import streams

import common


using m: Map

func width*(m): Natural =
  result = m.width

func height*(m): Natural =
  result = m.height


proc cellIndex(m; x, y: Natural): Natural =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  let w = m.width+1
  let h = m.height+1
  assert x < w+1
  assert y < h+1
  result = w*y + x

proc `[]=`(m; x, y: Natural, c: Cell) =
  m.cells[cellIndex(m, x, y)] = c

proc `[]`(m; x, y: Natural): var Cell =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  result = m.cells[cellIndex(m, x, y)]

proc fill*(m; r: Rect[Natural], cell: Cell) =
  assert r.x1 < m.width
  assert r.y1 < m.height
  assert r.x2 <= m.width
  assert r.y2 <= m.height

  # TODO fill border
  for y in r.y1..<r.y2:
    for x in r.x1..<r.x2:
      m[x,y] = cell


proc fill*(m; cell: Cell) =
  let r = rectN(0, 0, m.width-1, m.height-1)
  m.fill(r, cell)

proc initMap(m; width, height: Natural) =
  m.width = width
  m.height = height

  # We're storing one extra row & column at the bottom-right edges ("edge"
  # columns & rows) so we can store the South and East walls of the bottommost
  # row and rightmost column, respectively.
  newSeq(m.cells, (width+1) * (height+1))

proc newMap*(width, height: Natural): Map =
  var m = new Map
  m.initMap(width, height)
  m.fill(Cell.default)
  result = m


proc copyFrom*(dest: var Map, destX, destY: Natural,
               src: Map, srcRect: Rect[Natural]) =
  let
    srcX = srcRect.x1
    srcY = srcRect.y1
    srcWidth   = max(src.width - srcX, 0)
    srcHeight  = max(src.height - srcY, 0)
    destWidth  = max(dest.width - destX, 0)
    destHeight = max(dest.height - destY, 0)

    w = min(min(srcWidth,  destWidth),  srcRect.width)
    h = min(min(srcHeight, destHeight), srcRect.height)

  for y in 0..<h:
    for x in 0..<w:
      dest[destX + x, destY + y] = src[srcX + x, srcY + y]

  # Copy the South walls of the bottommost "edge" row
  for x in 0..<w:
    dest[destX + x, destY + h].wallN = src[srcX + x, srcY + h].wallN

  # Copy the East walls of the rightmost "edge" column
  for y in 0..<h:
    dest[destX + w, destY + y].wallW = src[srcX + w, srcY + y].wallW


proc copyFrom*(dest: var Map, src: Map) =
  dest.copyFrom(destX=0, destY=0, src, rectN(0, 0, src.width, src.height))


proc newMapFrom*(src: Map, r: Rect[Natural]): Map =
  assert r.x1 < src.width
  assert r.y1 < src.height
  assert r.x2 <= src.width
  assert r.y2 <= src.height

  var dest = new Map
  dest.initMap(r.width, r.height)
  dest.copyFrom(destX=0, destY=0, src, srcRect=r)
  result = dest


proc newMapFrom*(m): Map =
  newMapFrom(m, rectN(0, 0, m.width, m.height))


proc getFloor*(m; x, y: Natural): Floor =
  assert x < m.width
  assert y < m.height
  m[x,y].floor

proc getFloorOrientation*(m; x, y: Natural): Orientation =
  assert x < m.width
  assert y < m.height
  m[x,y].floorOrientation

proc setFloorOrientation*(m; x, y: Natural, ot: Orientation) =
  assert x < m.width
  assert y < m.height
  m[x,y].floorOrientation = ot

proc setFloor*(m; x, y: Natural, f: Floor) =
  assert x < m.width
  assert y < m.height
  m[x,y].floor = f


proc getWall*(m; x, y: Natural, dir: Direction): Wall =
  assert x < m.width
  assert y < m.height

  case dir
  of North: m[  x,   y].wallN
  of West:  m[  x,   y].wallW
  of South: m[  x, 1+y].wallN
  of East:  m[1+x,   y].wallW


proc setWall*(m; x, y: Natural, dir: Direction, w: Wall) =
  assert x < m.width
  assert y < m.height

  case dir
  of North: m[  x,   y].wallN = w
  of West:  m[  x,   y].wallW = w
  of South: m[  x, 1+y].wallN = w
  of East:  m[1+x,   y].wallW = w


# TODO
proc serialize(m; s: var Stream) =
  discard

# TODO
proc deserialize(s: Stream): Map =
  discard


# vim: et:ts=2:sw=2:fdm=marker
