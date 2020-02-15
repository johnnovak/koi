import options

type
  Orientation* = enum
    Horiz, Vert

  Direction* = enum
    North, East, South, West


type
  # Rects are endpoint-exclusive
  Rect*[T: SomeNumber | Natural] = object
    x1*, y1*, x2*, y2*: T


proc rectN*(x1, y1, x2, y2: Natural): Rect[Natural] =
  assert x1 < x2
  assert y1 < y2

  result.x1 = x1
  result.y1 = y1
  result.x2 = x2
  result.y2 = y2


proc intersect*[T: SomeNumber | Natural](a, b: Rect[T]): Option[Rect[T]] =
  let
    x = max(a.x1, b.x1)
    y = max(a.y1, b.y1)
    n1 = min(a.x1 + a.width,  b.x1 + b.width)
    n2 = min(a.y1 + a.height, b.y1 + b.height)

  if (n1 >= x and n2 >= y):
    some(Rect[T](
      x1: x,
      y1: y,
      x2: x + n1-x,
      y2: y + n2-y
    ))
  else: none(Rect[T])


func width*[T: SomeNumber | Natural](r: Rect[T]): T = r.x2 - r.x1
func height*[T: SomeNumber | Natural](r: Rect[T]): T = r.y2 - r.y1

func contains*[T: SomeNumber | Natural](r: Rect[T], x, y: T): bool =
  x >= r.x1 and x < r.x2 and y >= r.y1 and y < r.y2


type
  Floor* = enum
    fNone                = (  0, "blank"),
    fEmptyFloor          = ( 10, "empty"),
    fClosedDoor          = ( 20, "closed door"),
    fOpenDoor            = ( 21, "open door"),
    fPressurePlate       = ( 30, "pressure plate"),
    fHiddenPressurePlate = ( 31, "hidden pressure plate"),
    fClosedPit           = ( 40, "closed pit"),
    fOpenPit             = ( 41, "open pit"),
    fHiddenPit           = ( 42, "hidden pit"),
    fCeilingPit          = ( 43, "ceiling pit"),
    fStairsDown          = ( 50, "stairs down"),
    fStairsUp            = ( 51, "stairs up"),
    fSpinner             = ( 60, "spinner"),
    fTeleport            = ( 70, "teleport"),
    fCustom              = (999, "custom")

  Wall* = enum
    wNone          = ( 0, "none"),
    wWall          = (10, "wall"),
    wIllusoryWall  = (11, "illusory wall"),
    wInvisibleWall = (12, "invisible wall")
    wOpenDoor      = (20, "closed door"),
    wClosedDoor    = (21, "open door"),
    wSecretDoor    = (22, "secret door"),
    wLever         = (30, "statue")
    wNiche         = (40, "niche")
    wStatue        = (50, "statue")

  Cell* = object
    floor*:            Floor
    floorOrientation*: Orientation
    wallN*, wallW*:    Wall
    customChar*:       char
    notes*:            string

  # (0,0) is the top-left cell of the map
  Map* = ref object
    width*:  Natural
    height*: Natural
    cells*:  seq[Cell]


type
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    width*:  Natural
    height*: Natural
    cells*:  seq[bool]


type
  SelectionRect* = object
    x0*, y0*:   Natural
    rect*:      Rect[Natural]
    fillValue*: bool

  CopyBuffer* = object
    map*:       Map
    selection*: Selection

