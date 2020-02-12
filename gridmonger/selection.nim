import options


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

proc `[]=`*(s; x, y: Natural, v: bool) =
  assert x < s.width
  assert y < s.height
  s.cells[s.width * y + x] = v

proc `[]`*(s; x, y: Natural): bool =
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

proc initSelection(s; width, height: Natural) =
  s.width = width
  s.height = height
  newSeq(s.cells, s.width * s.height)

proc newSelection*(width, height: Natural): Selection =
  var s = new Selection
  s.initSelection(width, height)
  result = s


proc copyFrom*(dest: var Selection,
               src: Selection, srcX, srcY, width, height: Natural,
               destX, destY: Natural) =
  let
    srcWidth   = max(src.width - srcX, 0)
    srcHeight  = max(src.height - srcY, 0)
    destWidth  = max(dest.width - destX, 0)
    destHeight = max(dest.height - destY, 0)

    w = min(min(srcWidth,  destWidth),  width)
    h = min(min(srcHeight, destHeight), height)

  for y in 0..h-1:
    for x in 0..w-1:
      dest[destX + x, destY + y] = src[srcX + x, srcY + y]


proc copyFrom*(s: var Selection, src: Selection) =
  s.copyFrom(src, srcX=0, srcY=0, src.width, src.height, destX=0, destY=0)


proc newSelectionFrom*(src: Selection, x, y, width, height: Natural): Selection =
  assert x < src.width-1
  assert y < src.height-1
  assert width > 0
  assert height > 0
  assert x + width <= src.width-1
  assert y + height <= src.height-1

  var s = new Selection
  s.initSelection(width, height)
  s.copyFrom(src, srcX=x, srcY=y, width, height, destX=0, destY=0)
  result = s


proc newSelectionFrom*(s): Selection =
  newSelectionFrom(s, x=0, y=0, s.width-1, s.height-1)


proc trim*(s): Option[Selection] =
  proc isRowEmpty(y: Natural): bool =
    for x in 0..s.width:
      if s[x,y]: return false
    return true

  proc isColEmpty(x: Natural): bool =
    for y in 0..s.height:
      if s[x,y]: return false
    return true

  var
    x1 = 0
    y1 = 0
    x2 = s.width-1
    y2 = s.height-1

  while isRowEmpty(y1) and y1 < s.height: inc(y1)

  if y1 < s.height-1:
    while isColEmpty(x1) and x1 < s.width: inc(x1)
    while isColEmpty(x2) and x2 > 0: dec(x2)
    while isRowEmpty(y2) and y2 > 0: dec(y2)
    result = some(s.newSelectionFrom(x1, y1, x2, y2))
  else:
    result = none(Selection)


# vim: et:ts=2:sw=2:fdm=marker
