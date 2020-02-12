type
  Orientation* = enum
    Horiz, Vert

  Direction* = enum
    North, East, South, West


type
  Rect*[T: SomeNumber | Natural] = object
    x1*, x2*, y1*, y2*: T

func contains*[T: SomeNumber | Natural](r: Rect[T], x, y: T): bool =
  x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2

func normalize*[T: SomeNumber | Natural](r: Rect[T]): Rect[T] =
  Rect[T](x1: min(r.x1, r.x2), y1: min(r.y1, r.y2),
          x2: max(r.x1, r.x2), y2: max(r.y1, r.y2))


type
  SelectionRect* = object
    x0*, y0*:   Natural
    rect*:      Rect[Natural]
    fillValue*: bool

