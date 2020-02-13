import streams

import common


using m: Map

func mapWidth*(m): Natural =
  result = m.width-1

func mapHeight*(m): Natural =
  result = m.height-1

proc `[]=`(m; x, y: Natural, c: Cell) =
  assert x < m.width
  assert y < m.height
  m.cells[m.width * y + x] = c

proc `[]`(m; x, y: Natural): var Cell =
  assert x < m.width
  assert y < m.height
  result = m.cells[m.width * y + x]

proc fill*(m; r: Rect[Natural], cell: Cell) =
  assert r.x1 < m.width-1
  assert r.y1 < m.height-1
  assert r.x2 <= m.width-1
  assert r.y2 <= m.height-1

  # TODO fill border

  for y in r.y1..r.y2:
    for x in r.x1..r.x2:
      m[x,y] = cell

proc fill*(m; cell: Cell) =
  let r = Rect[Natural](x1: 0, y1: 0, x2: m.width-1, y2: m.height-1)
  m.fill(r, cell)

proc initMap(m; width, height: Natural) =
  m.width = width+1
  m.height = height+1
  newSeq(m.cells, m.width * m.height)

proc newMap*(width, height: Natural): Map =
  var m = new Map
  m.initMap(width, height)
  m.fill(Cell.default)
  result = m


proc copyFrom*(dest: var Map, src: Map, srcRect: Rect[Natural],
               destX, destY: Natural) =
  let
    srcX = srcRect.x1
    srcY = srcRect.y1
    width  = (srcRect.x2 - srcX) + 2
    height = (srcRect.y2 - srcY) + 2
    srcWidth   = max(src.width - srcX,  0)
    srcHeight  = max(src.height - srcY,  0)
    destWidth  = max(dest.width - destX, 0)
    destHeight = max(dest.height - destY, 0)

    w = min(min(srcWidth,  destWidth),  width)
    h = min(min(srcHeight, destHeight), height)

  for y in 0..h-2:
    for x in 0..w-2:
      dest[destX + x, destY + y] = src[srcX + x, srcY + y]

  for x in 0..w-2:
    dest[destX + x, destY + h-1].wallN = src[srcX + x, srcY + h-1].wallN

  for y in 0..h-2:
    dest[destX + w-1, destY + y].wallW = src[srcX + w-1, srcY + y].wallW


proc copyFrom*(m: var Map, src: Map) =
  let srcRect = Rect[Natural](x1: 0, y1: 0,
                              x2: src.width-1, y2: src.height-1)
  m.copyFrom(src, srcRect, destX=0, destY=0)


proc newMapFrom*(src: Map, r: Rect[Natural]): Map =
  assert r.x1 < src.width-1
  assert r.y1 < src.height-1
  assert r.x2 <= src.width-1
  assert r.y2 <= src.height-1

  var m = new Map
  m.initMap(r.width, r.height)
  m.copyFrom(src, srcRect=r, destX=0, destY=0)
  result = m


proc newMapFrom*(m): Map =
  newMapFrom(m, Rect[Natural](x1: 0, y1: 0, x2: m.width-1, y2: m.height-1))


proc getFloor*(m; x, y: Natural): Floor =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floor

proc getFloorOrientation*(m; x, y: Natural): Orientation =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floorOrientation

proc setFloorOrientation*(m; x, y: Natural, ot: Orientation) =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floorOrientation = ot

proc setFloor*(m; x, y: Natural, f: Floor) =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floor = f


proc getWall*(m; x, y: Natural, dir: Direction): Wall =
  assert x < m.width-1
  assert y < m.height-1

  case dir
  of North: m[  x,   y].wallN
  of West:  m[  x,   y].wallW
  of South: m[  x, 1+y].wallN
  of East:  m[1+x,   y].wallW


proc setWall*(m; x, y: Natural, dir: Direction, w: Wall) =
  assert x < m.width-1
  assert y < m.height-1

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
