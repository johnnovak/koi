import lenientops
import math

import nanovg

import common
import map


const
  UltrathinStrokeWidth = 1.0
  ThinStrokeWidth      = 2.0
  NormalStrokeWidth    = 3.0

  DoorWidthFactor = 0.75
  DoorDepthFactor = 0.1


# All drawing procs interpret the passed in (x,y) coordinates as the
# upper-left corner of the object (e.g. a cell).

# {{{ DrawParams
type
  DrawParams* = object
    gridSize*: float

    startX*:   float
    startY*:   float

    defaultStrokeColor*: Color
    mapBackgroundColor*: Color

    drawCursorGuides*: bool
    drawOutline*:      bool

# }}}
# {{{ initDrawParams()
proc initDrawParams(): DrawParams =
  var dp: DrawParams

  dp.gridSize = 22.0

  dp.startX = 50.0
  dp.startY = 50.0

  dp.defaultStrokeColor = gray(0.1)
  dp.mapBackgroundColor = gray(0.0, 0.7)

  dp.drawCursorGuides = false
  dp.drawOutline      = false

  result = dp
# }}}

var g_drawParams*: DrawParams = initDrawParams()

# This is needed for drawing crisp lines
func snap(f: float, strokeWidth: float): float =
  let (i, _) = splitDecimal(f)
  let (_, offs) = splitDecimal(strokeWidth/2)
  result = i + offs


proc cellX(x: Natural, dp: DrawParams): float =
  dp.startX + dp.gridSize * x

proc cellY(y: Natural, dp: DrawParams): float =
  dp.startY + dp.gridSize * y

# {{{ drawBackgroundGrid
proc drawBackgroundGrid(m: Map, dp: DrawParams, vg: NVGContext) =
  let strokeWidth = UltrathinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(gray(0.0, 0.3))
  vg.strokeWidth(strokeWidth)

  let endX = snap(cellX(m.width,  dp), strokeWidth)
  let endY = snap(cellY(m.height, dp), strokeWidth)

  for x in 0..m.width:
    let x = snap(cellX(x, dp), strokeWidth)
    let y = snap(dp.startY, strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(x, endY)
    vg.stroke()

  for y in 0..m.height:
    let x = snap(dp.startX, strokeWidth)
    let y = snap(cellY(y, dp), strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(endX, y)
    vg.stroke()

# }}}
# {{{ drawCellCoords()
proc drawCellCoords(m: Map, cursorX, cursorY: Natural,
                    dp: DrawParams, vg: NVGContext) =
  vg.fontSize(14.0)
  vg.fontFace("sans")
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fillColor(rgb(1.0, 0.8, 0.0))
      vg.fontFace("sans-bold")
    else:
      vg.fillColor(gray(0.9))
      vg.fontFace("sans")

  let endX = dp.startX + dp.gridSize * m.width
  let endY = dp.startY + dp.gridSize * m.height

  for x in 0..<m.width:
    let
      xPos = cellX(x, dp) + dp.gridSize/2
      coord = $x

    setTextHighlight(x == cursorX)

    discard vg.text(xPos, dp.startY - 12, coord)
    discard vg.text(xPos, endY + 12, coord)

  for y in 0..<m.height:
    let
      yPos = cellY(y, dp) + dp.gridSize/2
      coord = $y

    setTextHighlight(y == cursorY)

    discard vg.text(dp.startX - 12, yPos, coord)
    discard vg.text(endX + 12, yPos, coord)


# }}}
# {{{ drawMapBackground()
proc drawMapBackground(m: Map, dp: DrawParams, vg: NVGContext) =
  let strokeWidth = UltrathinStrokeWidth

  vg.strokeColor(dp.mapBackgroundColor)
  vg.strokeWidth(strokeWidth)

  let
    w = dp.gridSize * m.width
    h = dp.gridSize * m.height
    offs = max(w, h)
    lineSpacing = strokeWidth * 2

  let startX = snap(dp.startX, strokeWidth)
  let startY = snap(dp.startY, strokeWidth)

  vg.scissor(startX, startY, w, h)

  var
    x1 = startX - offs
    y1 = startY + offs
    x2 = startX + offs
    y2 = startY - offs

  while x1 < dp.startX + offs:
    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    vg.stroke()

    x1 += lineSpacing
    x2 += lineSpacing
    y1 += lineSpacing
    y2 += lineSpacing

  vg.resetScissor()

# }}}
# {{{ drawCursor()
proc drawCursor(m: Map, cursorX, cursorY: Natural,
                dp: DrawParams, vg: NVGContext) =
  let
    x = cellX(cursorX, dp)
    y = cellY(cursorY, dp)

  if dp.drawCursorGuides:
    let
      w = dp.gridSize * m.width
      h = dp.gridSize * m.height

    vg.beginPath()
    vg.fillColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeWidth(UltrathinStrokeWidth)
    vg.rect(x, dp.startY, dp.gridSize, h)
    vg.fill()
    vg.stroke()

    vg.beginPath()
    vg.rect(dp.startX, y, w, dp.gridSize)
    vg.strokeColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeWidth(UltrathinStrokeWidth)
    vg.fill()
    vg.stroke()

  vg.fillColor(rgb(1.0, 0.65, 0.0))

  vg.beginPath()
  vg.rect(x+1, y+1, dp.gridSize-1, dp.gridSize-1)
  vg.fill()

# }}}
# {{{ drawOutline()
proc drawOutline(m: Map, dp: DrawParams, vg: NVGContext) =
  func check(x, y: int): bool =
    let x = max(min(x, m.width-1), 0)
    let y = max(min(y, m.height-1), 0)
    m.getFloor(x,y) != fNone

  func isOutline(x, y: Natural): bool =
    check(x,   y+1) or
    check(x+1, y+1) or
    check(x+1, y  ) or
    check(x+1, y-1) or
    check(x  , y-1) or
    check(x-1, y-1) or
    check(x-1, y  ) or
    check(x-1, y+1)

  for y in 0..<m.height:
    for x in 0..<m.width:
      if isOutline(x, y):
        let
          x = cellX(x, dp)
          y = cellY(y, dp)

        vg.beginPath()
        vg.fillColor(gray(0.3))
        vg.strokeColor(gray(0.3))
        vg.strokeWidth(UltrathinStrokeWidth)
        vg.rect(x, y, dp.gridSize, dp.gridSize)
        vg.fill()
        vg.stroke()

# }}}

# {{{ drawSolidWallHoriz()
proc drawSolidWallHoriz(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    sw = NormalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(dp.defaultStrokeColor)
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawOpenDoorHoriz()
proc drawOpenDoorHoriz(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    wallLen = (dp.gridSize * (1.0 - DoorWidthFactor)).int
    doorWidth = round(dp.gridSize * DoorDepthFactor)
    x1 = x - doorWidth
    x2 = x + doorWidth
    ys = y - dp.gridSize
    y1 = ys + wallLen
    ye = ys + dp.gridSize
    y2 = ye - wallLen

  vg.strokeColor(dp.defaultStrokeColor)
  vg.strokeWidth(NormalStrokeWidth)

  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(x, ys)
  vg.lineTo(x, y1)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1, y1)
  vg.lineTo(x2, y1)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1, y2)
  vg.lineTo(x2, y2)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x, y2)
  vg.lineTo(x, ye)
  vg.stroke()

# }}}
# {{{ drawClosedDoorHoriz()
proc drawClosedDoorHoriz(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    wallLen = (dp.gridSize * (1.0 - DoorWidthFactor)).int
    doorWidth = round(dp.gridSize * DoorDepthFactor)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(dp.defaultStrokeColor)

  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1 - sw/2, sw), snap(y, sw))
  vg.stroke()

  sw = ThinStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.rect(snap(x1, sw) + 1, snap(y1, sw), x2-x1-1, y2-y1+1)
  vg.stroke()

  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.moveTo(snap(x2 + sw/2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}

# {{{ drawSolidWallVert()
proc drawSolidWallVert(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    strokeWidth = NormalStrokeWidth
    x = snap(x, strokeWidth)
    y = snap(y, strokeWidth)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(dp.defaultStrokeColor)
  vg.strokeWidth(NormalStrokeWidth)
  vg.moveTo(x, y)
  vg.lineTo(x, y + dp.gridSize)
  vg.stroke()

# }}}
# {{{ drawOpenDoorVert()
proc drawOpenDoorVert(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    wallLen = (dp.gridSize * (1.0 - DoorWidthFactor)).int
    doorWidth = round(dp.gridSize * DoorDepthFactor)
    x1 = x - doorWidth
    x2 = x + doorWidth
    ys = y - dp.gridSize
    y1 = ys + wallLen
    ye = ys + dp.gridSize
    y2 = ye - wallLen

  vg.strokeColor(dp.defaultStrokeColor)
  vg.strokeWidth(NormalStrokeWidth)

  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(x, ys)
  vg.lineTo(x, y1)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1, y1)
  vg.lineTo(x2, y1)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1, y2)
  vg.lineTo(x2, y2)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x, y2)
  vg.lineTo(x, ye)
  vg.stroke()

# }}}
# {{{ drawClosedDoorVert()
proc drawClosedDoorVert(x, y: float, dp: DrawParams, vg: NVGContext) =
  let
    wallLen = (dp.gridSize * (1.0 - DoorWidthFactor)).int
    doorWidth = round(dp.gridSize * DoorDepthFactor)
    xs = snap(x, NormalStrokeWidth)
    y  = snap(y, NormalStrokeWidth)
    x1 = snap(xs + wallLen, ThinStrokeWidth)
    xe = xs + dp.gridSize
    x2 = snap(xe - wallLen, ThinStrokeWidth)
    y1 = snap(y - doorWidth, ThinStrokeWidth)
    y2 = snap(y + doorWidth, ThinStrokeWidth)

  vg.strokeColor(dp.defaultStrokeColor)
  vg.strokeWidth(NormalStrokeWidth)

  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(xs, y)
  vg.lineTo(x1 - NormalStrokeWidth/2, y)
  vg.stroke()

  vg.strokeWidth(ThinStrokeWidth)
  vg.beginPath()
  vg.rect(
    snap(x1, ThinStrokeWidth),
    snap(y1, ThinStrokeWidth),
    snap(x2-x1, ThinStrokeWidth),
    snap(y2-y1, ThinStrokeWidth)
  )
  vg.stroke()

  vg.strokeWidth(NormalStrokeWidth)
  vg.beginPath()
  vg.moveTo(x2 + NormalStrokeWidth/2, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}

# {{{ drawWallHoriz()
proc drawWallHoriz(x, y: float, wall: Wall,
                   dp: DrawParams, vg: NVGContext) =
  case wall
  of wNone:          discard
  of wWall:          drawSolidWallHoriz(x, y, dp, vg)
  of wIllusoryWall:  discard
  of wInvisibleWall: discard
  of wOpenDoor:      drawOpenDoorHoriz(x, y, dp, vg)
  of wClosedDoor:    drawClosedDoorHoriz(x, y, dp, vg)
  of wSecretDoor:    discard
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

# }}}
# {{{ drawWallVert()
proc drawWallVert(x, y: float, wall: Wall,
                  dp: DrawParams, vg: NVGContext) =
  case wall
  of wNone:          discard
  of wWall:          drawSolidWallVert(x, y, dp, vg)
  of wIllusoryWall:  discard
  of wInvisibleWall: discard
  of wOpenDoor:      drawOpenDoorVert(x, y, dp, vg)
  of wClosedDoor:    drawClosedDoorVert(x, y, dp, vg)
  of wSecretDoor:    discard
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

# }}}
# {{{ drawWalls()
proc drawWalls(m: Map, x: Natural, y: Natural, dp: DrawParams, vg: NVGContext) =
  drawWallHoriz(cellX(x, dp), cellY(y, dp), m.getWall(x,y, North), dp, vg)
  drawWallVert(cellX(x, dp), cellY(y, dp), m.getWall(x,y, West), dp, vg)

  if x == m.width-1:
    drawWallVert(cellX(x+1, dp), cellY(y, dp), m.getWall(x,y, East), dp, vg)

  if y == m.height-1:
    drawWallHoriz(cellX(x, dp), cellY(y+1, dp), m.getWall(x,y, South), dp, vg)

# }}}

# {{{ drawFloor()
proc drawFloor(m: Map, x: Natural, y: Natural, dp: DrawParams, vg: NVGContext) =
  if m.getFloor(x,y) != fNone:
    let
      strokeWidth = UltrathinStrokeWidth
      x = snap(cellX(x, dp), strokeWidth)
      y = snap(cellY(y, dp), strokeWidth)

    vg.beginPath()
    vg.fillColor(gray(0.9))
    vg.strokeColor(gray(0.7))
    vg.strokeWidth(strokeWidth)
    vg.rect(x, y, dp.gridSize, dp.gridSize)
    vg.fill()
    vg.stroke()


# }}}

# {{{ drawMap*()
proc drawMap*(m: Map, cursorX, cursorY: Natural,
              dp: DrawParams, vg: NVGContext) =

  drawCellCoords(m, cursorX, cursorY, dp, vg)
 # drawMapBackground(m, dp, vg)
  drawBackgroundGrid(m, dp, vg)

  if dp.drawOutline: drawOutline(m, dp, vg)

  for y in 0..<m.height:
    for x in 0..<m.width:
      drawFloor(m, x, y, dp, vg)

  drawCursor(m, cursorX, cursorY, dp, vg)

  for y in 0..<m.height:
    for x in 0..<m.width:
      drawWalls(m, x, y, dp, vg)

# }}}


# vim: et:ts=2:sw=2:fdm=marker
