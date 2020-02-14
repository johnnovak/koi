import options

import common


using s: Selection

proc `[]=`*(s; x, y: Natural, v: bool) =
  assert x < s.width
  assert y < s.height
  s.cells[s.width * y + x] = v

proc `[]`*(s; x, y: Natural): bool =
  assert x < s.width
  assert y < s.height
  result = s.cells[s.width * y + x]


proc fill*(s; r: Rect[Natural], v: bool) =
  assert r.x1 < s.width
  assert r.y1 < s.height
  assert r.x2 <= s.width
  assert r.y2 <= s.height

  for y in r.y1..<r.y2:
    for x in r.x1..<r.x2:
      s[x,y] = v


proc fill*(s; v: bool) =
  let r = rectN(0, 0, s.width, s.height)
  s.fill(r, v)

proc initSelection(s; width, height: Natural) =
  s.width = width
  s.height = height
  newSeq(s.cells, s.width * s.height)

proc newSelection*(width, height: Natural): Selection =
  var s = new Selection
  s.initSelection(width, height)
  result = s


proc copyFrom*(dest: var Selection, destX, destY: Natural,
               src: Selection, srcRect: Rect[Natural]) =
  let
    srcX = srcRect.x1
    srcY = srcRect.y1
    srcWidth   = max(src.width - srcX, 0)
    srcHeight  = max(src.height - srcY, 0)
    destWidth  = max(dest.width - destX, 0)
    destHeight = max(dest.height - destY, 0)

    w = min(min(srcWidth,  destWidth), srcRect.width)
    h = min(min(srcHeight, destHeight), srcRect.height)

  for y in 0..<h:
    for x in 0..<w:
      dest[destX + x, destY + y] = src[srcX + x, srcY + y]


proc copyFrom*(dest: var Selection, src: Selection) =
  dest.copyFrom(destX=0, destY=0, src, rectN(0, 0, src.width, src.height))


proc newSelectionFrom*(src: Selection, r: Rect[Natural]): Selection =
  assert r.x1 < src.width
  assert r.y1 < src.height
  assert r.x2 <= src.width
  assert r.y2 <= src.height

  var dest = new Selection
  dest.initSelection(r.width, r.height)
  dest.copyFrom(destX=0, destY=0, src, srcRect=r)
  result = dest


proc newSelectionFrom*(s): Selection =
  newSelectionFrom(s, rectN(0, 0, s.width, s.height))


proc boundingBox*(s): Option[Rect[Natural]] =
  proc isRowEmpty(y: Natural): bool =
    for x in 0..<s.width:
      if s[x,y]: return false
    return true

  proc isColEmpty(x: Natural): bool =
    for y in 0..<s.height:
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

    result = some(rectN(x1, y1, x2+1, y2+1))
  else:
    result = none(Rect[Natural])


# vim: et:ts=2:sw=2:fdm=marker
