import options

type
  Rect* = object
    x*, y*, w*, h*: float

proc rect*(x, y, w, h: float): Rect =
  result.x = x
  result.y = y
  result.w = w
  result.h = h


proc intersect*(a, b: Rect): Option[Rect] =
  let
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(a.x + a.w, b.x + b.w)
    y2 = min(a.y + a.h, b.y + b.h)

  if (y2 >= y1 and x2 >= x1):
    rect(x1, y1, x2-x1, y2-y1).some
  else: Rect.none

