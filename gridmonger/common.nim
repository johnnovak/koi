type
  Orientation* = enum
    Horiz, Vert

  Direction* = enum
    North, East, South, West

  Rect*[T: SomeNumber | Natural] = object
    x1*, x2*, y1*, y2*: T

