type
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    width:  Natural
    height: Natural
    cells:  seq[bool]


using s: Selection

func width*(s): Natural =
  result = s.width

func height*(s): Natural =
  result = s.height

proc `[]=`(s; x, y: Natural, v: bool) =
  assert x < s.width
  assert y < s.height
  s.cells[s.width * y + x] = v

proc `[]`(s; x, y: Natural): bool =
  assert x < s.width
  assert y < s.height
  result = s.cells[s.width * y + x]


proc fill*(s; x1, y1, x2, y2: Natural, v: bool) =
  assert x1 < s.width
  assert y1 < s.height
  assert x2 < s.width
  assert y2 < s.height

  var
    x1 = x1
    y1 = y1
    x2 = x2
    y2 = y2

  if x2 < x1: swap(x1, x2)
  if y2 < y1: swap(y1, y1)

  for y in y1..y2:
    for x in x1..x2:
      s[x,y] = v


proc fill*(s; v: bool) =
  s.fill(0, 0, s.width-1, s.height-1, v)

proc newSelection*(width, height: Natural): Selection =
  var s = new Selection
  s.width = width
  s.height = height
  newSeq(s.cells, s.width * s.height)
  result = s


# vim: et:ts=2:sw=2:fdm=marker
