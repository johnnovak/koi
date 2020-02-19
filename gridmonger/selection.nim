import options

import common


using s: Selection

proc `[]=`*(s; x, y: Natural, v: bool) =
  assert x < s.cols
  assert y < s.rows
  s.cells[s.cols * y + x] = v

proc `[]`*(s; x, y: Natural): bool =
  assert x < s.cols
  assert y < s.rows
  result = s.cells[s.cols * y + x]


proc fill*(s; r: Rect[Natural], v: bool) =
  assert r.x1 < s.cols
  assert r.y1 < s.rows
  assert r.x2 <= s.cols
  assert r.y2 <= s.rows

  for y in r.y1..<r.y2:
    for x in r.x1..<r.x2:
      s[x,y] = v


proc fill*(s; v: bool) =
  let r = rectN(0, 0, s.cols, s.rows)
  s.fill(r, v)

proc initSelection(s; cols, rows: Natural) =
  s.cols = cols
  s.rows = rows
  newSeq(s.cells, s.cols * s.rows)

proc newSelection*(cols, rows: Natural): Selection =
  var s = new Selection
  s.initSelection(cols, rows)
  result = s


proc copyFrom*(dest: var Selection, destX, destY: Natural,
               src: Selection, srcRect: Rect[Natural]) =
  let
    srcX = srcRect.x1
    srcY = srcRect.y1
    srcCols   = max(src.cols - srcX, 0)
    srcRows  = max(src.rows - srcY, 0)
    destCols  = max(dest.cols - destX, 0)
    destRows = max(dest.rows - destY, 0)

    w = min(min(srcCols,  destCols), srcRect.width)
    h = min(min(srcRows, destRows), srcRect.height)

  for y in 0..<h:
    for x in 0..<w:
      dest[destX + x, destY + y] = src[srcX + x, srcY + y]


proc copyFrom*(dest: var Selection, src: Selection) =
  dest.copyFrom(destX=0, destY=0, src, rectN(0, 0, src.cols, src.rows))


proc newSelectionFrom*(src: Selection, r: Rect[Natural]): Selection =
  assert r.x1 < src.cols
  assert r.y1 < src.rows
  assert r.x2 <= src.cols
  assert r.y2 <= src.rows

  var dest = new Selection
  dest.initSelection(r.width, r.height)
  dest.copyFrom(destX=0, destY=0, src, srcRect=r)
  result = dest


proc newSelectionFrom*(s): Selection =
  newSelectionFrom(s, rectN(0, 0, s.cols, s.rows))


proc boundingBox*(s): Option[Rect[Natural]] =
  proc isRowEmpty(y: Natural): bool =
    for x in 0..<s.cols:
      if s[x,y]: return false
    return true

  proc isColEmpty(x: Natural): bool =
    for y in 0..<s.rows:
      if s[x,y]: return false
    return true

  var
    x1 = 0
    y1 = 0
    x2 = s.cols-1
    y2 = s.rows-1

  while isRowEmpty(y1) and y1 < s.rows: inc(y1)

  if y1 < s.rows-1:
    while isColEmpty(x1) and x1 < s.cols: inc(x1)
    while isColEmpty(x2) and x2 > 0: dec(x2)
    while isRowEmpty(y2) and y2 > 0: dec(y2)

    result = some(rectN(x1, y1, x2+1, y2+1))
  else:
    result = none(Rect[Natural])


# vim: et:ts=2:sw=2:fdm=marker
