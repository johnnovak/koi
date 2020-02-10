type
  Orientation* = enum
    Horiz, Vert

  Direction* = enum
    North, East, South, West


func orientation*(dir: Direction): Orientation =
  case dir:
  of North: Horiz
  of East:  Vert
  of South: Horiz
  of West:  Vert

