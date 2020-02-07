import common

type
  Floor* = enum
    fNone      = ( 0, "blank"),
    fGround     = ( 1, "ground"),
    fDoor       = ( 2, "door"),
    fPlate      = ( 3, "pressure plate"),
    fOpenPit    = ( 4, "open pit"),
    fClosedPit  = ( 5, "closed pit"),
    fPitAbove   = ( 6, "pit (above)"),
    fStairsDown = ( 7, "stairs (down)"),
    fStairsUp   = ( 8, "stairs (up)"),
    fSpinner    = ( 9, "spinner"),
    fTeleport   = (10, "teleport"),
#    fCurtain    = (11, "curtain"),
#    fGrate      = (12, "grate"),
#    fColumn     = (13, "column"),
#    fStatue     = (14, "statue"),
#    fWater      = (16, "water")
    fCustom     = (17, "custom")

  Wall* = enum
    wNone          = ( 0, "none"),
    wWall          = ( 1, "wall"),
    wDoor          = ( 2, "door"),
    wDoorway       = ( 3, "doorway"),
    wSecretDoor    = ( 4, "secret door"),
    wIllusoryWall  = ( 5, "illusory wall"),
    wInvisibleWall = ( 6, "invisible wall")

    # TODO
#    wLever         = ( 0, "lever"),
#    wButton        = ( 1, "button"),
#    wWallCavity    = ( 2, "wall cavity"),
#    wWriting       = ( 3, "writing"),
#    fProjector  = (15, "projector"),

  Cell* = object
    floor*:         Floor
    wallS*, wallW*: Wall
    customChar*:    char
    notes*:         string

  Map* = ref object
    width: Natural
    height: Natural
    cells: seq[Cell]


func width*(m: Map): Natural =
  result = m.width-1

func height*(m: Map): Natural =
  result = m.height-1

proc `[]=`(m: var Map, x, y: Natural, c: Cell) =
  assert x < m.width
  assert y < m.height
  m.cells[m.width * y + x] = c

proc `[]`(m: Map, x, y: Natural): var Cell =
  assert x < m.width
  assert y < m.height
  result = m.cells[m.width * y + x]

proc fill*(m: var Map, x1, y1, x2, y2: Natural, cell: Cell = Cell.default) =
  assert x1 < m.width-1
  assert y1 < m.height-1
  for y in y1..y2:
    for x in x1..x2:
      m[x,y] = cell

proc clear*(m: var Map, cell: Cell = Cell.default) =
  m.fill(0, 0, m.width-1, m.height-1, cell)

proc initMap(m: var Map, width, height: Natural) =
  m.width = width+1
  m.height = height+1
  newSeq(m.cells, m.width * m.height)

proc newMap*(width, height: Natural): Map =
  var m = new Map
  m.initMap(width, height)
  m.clear()
  result = m


proc copyFrom*(m: var Map,
               src: Map, srcX, srcY, width, height: Natural,
               destX, destY: Natural) =
  let
    srcWidth = max(src.width - srcX, 0)
    srcHeight = max(src.height - srcY, 0)
    destWidth = max(m.width - destX, 0)
    destHeight = max(m.height - destY, 0)
    w = min(min(srcWidth, destWidth), width)
    h = min(min(srcHeight, destHeight), height)

  for y in 0..h-2:
    for x in 0..w-2:
      m[x + destX, y + destY] = src[x + srcX, y + srcY]

  for x in 0..w-2:
    m[x+destX, h-1 + destY].wallS = src[x+srcX, h-1 + destY].wallS

  for y in 0..h-2:
    m[w-1 + destX, y+destY].wallS = src[w-1 + destX, y+destY].wallW

proc copyFrom*(m: var Map, src: Map) =
  m.copyFrom(src, 0, 0, src.width, src.height, 0, 0)

proc newMapFrom*(src: Map): Map =
  var m = new Map
  m.initMap(src.width, src.height)
  m.copyFrom(src)
  result = m


proc getFloor*(m: Map, x, y: Natural): Floor =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floor

proc setFloor*(m: Map, x, y: Natural, f: Floor) =
  assert x < m.width-1
  assert y < m.height-1
  m[x,y].floor = f


proc getWall*(m: Map, x, y: Natural, dir: Direction): Wall =
  assert x < m.width-1
  assert y < m.height-1

  case dir
  of North: m[  x, 1+y].wallS
  of East:  m[1+x,   y].wallW
  of South: m[  x,   y].wallS
  of West:  m[  x,   y].wallW


proc setWall*(m: var Map, x, y: Natural, dir: Direction, w: Wall) =
  assert x < m.width-1
  assert y < m.height-1

  case dir
  of North: m[  x, 1+y].wallS = w
  of East:  m[1+x,   y].wallW = w
  of South: m[  x,   y].wallS = w
  of West:  m[  x,   y].wallW = w


# vim: et:ts=2:sw=2:fdm=marker
