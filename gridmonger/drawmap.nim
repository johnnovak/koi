import lenientops
import math
import options

import nanovg

import common
import map
import selection


const
  UltrathinStrokeWidth = 1.0
  ThinStrokeWidth      = 2.0
  NormalStrokeWidth    = 3.0

# All drawing procs interpret the passed in (x,y) coordinates as the
# upper-left corner of the object (e.g. a cell).

# {{{ DrawParams*
type
  DrawParams* = ref object
    gridSize*: float

    startX*:   float
    startY*:   float

    defaultFgColor*:      Color

    mapBackgroundColor*:  Color
    mapOutlineColor*:     Color
    drawOutline*:         bool

    gridColorBackground*: Color
    gridColorFloor*:      Color

    floorColor*:          Color

    cursorColor*:         Color
    cursorGuideColor*:    Color
    drawCursorGuides*:    bool

    selectionColor*:      Color

    cellCoordsColor*:     Color
    cellCoordsColorHi*:   Color
    cellCoordsFontSize*:  float

# }}}

using
  dp: DrawParams
  vg: NVGContext

# {{{ utils

# This is needed for drawing crisp lines
func snap(f: float, strokeWidth: float): float =
  let (i, _) = splitDecimal(f)
  let (_, offs) = splitDecimal(strokeWidth/2)
  result = i + offs

proc cellX(x: Natural, dp): float =
  dp.startX + dp.gridSize * x

proc cellY(y: Natural, dp): float =
  dp.startY + dp.gridSize * y

# }}}

# {{{ drawBackgroundGrid
proc drawBackgroundGrid(m: Map, dp, vg) =
  let strokeWidth = UltrathinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(dp.gridColorBackground)
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
proc drawCellCoords(m: Map, cursorX, cursorY: Natural, dp, vg) =

  vg.fontFace("sans")
  vg.fontSize(dp.cellCoordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fillColor(dp.cellCoordsColorHi)
    else:
      vg.fillColor(dp.cellCoordsColor)
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
proc drawMapBackground(m: Map, dp, vg) =
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
proc drawCursor(x, y: float, dp, vg) =
  vg.fillColor(dp.cursorColor)
  vg.beginPath()
  vg.rect(x+1, y+1, dp.gridSize-1, dp.gridSize-1)
  vg.fill()

# }}}
# {{{ drawCursorGuides()
proc drawCursorGuides(m: Map, cursorX, cursorY: Natural, dp, vg) =
  let
    x = cellX(cursorX, dp)
    y = cellY(cursorY, dp)
    w = dp.gridSize * m.width
    h = dp.gridSize * m.height

  vg.fillColor(dp.cursorGuideColor)
  vg.strokeColor(dp.cursorGuideColor)
  let sw = UltrathinStrokeWidth
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x, sw), snap(dp.startY, sw), dp.gridSize, h)
  vg.fill()
  vg.stroke()

  vg.beginPath()
  vg.rect(snap(dp.startX, sw), snap(y, sw), w, dp.gridSize)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawOutline()
proc drawOutline(m: Map, dp, vg) =
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
          sw = UltrathinStrokeWidth
          x = snap(cellX(x, dp), sw)
          y = snap(cellY(y, dp), sw)

        vg.strokeWidth(sw)
        vg.fillColor(dp.mapOutlineColor)
        vg.strokeColor(dp.mapOutlineColor)

        vg.beginPath()
        vg.rect(x, y, dp.gridSize, dp.gridSize)
        vg.fill()
        vg.stroke()

# }}}

# {{{ drawGround()
proc drawGround(x, y: float, color: Color, dp, vg) =
  let sw = UltrathinStrokeWidth

  vg.beginPath()
  vg.fillColor(color)
  vg.strokeColor(dp.gridColorFloor)
  vg.strokeWidth(sw)
  vg.rect(snap(x, sw), snap(y, sw), dp.gridSize, dp.gridSize)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, dp, vg) =
  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(dp.defaultFgColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawClosedPit()
proc drawClosedPit(x, y: float, dp, vg) =
  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(dp.defaultFgColor)
  vg.strokeWidth(sw)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)
    x2 = snap(x + offs + a, sw)
    y2 = snap(y + offs + a, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1+1, y1+1)
  vg.lineTo(x2-1, y2-1)
  vg.stroke()
  vg.beginPath()
  vg.moveTo(x2-1, y1+1)
  vg.lineTo(x1+1, y2-1)
  vg.stroke()

# }}}
# {{{ drawOpenPit()
proc drawOpenPit(x, y: float, dp, vg) =
  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(dp.defaultFgColor)
  vg.fillColor(dp.defaultFgColor)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawStairsDown()
proc drawStairsDown(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawStairsUp()
proc drawStairsUp(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawSpinner()
proc drawSpinner(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawTeleport()
proc drawTeleport(x, y: float, dp, vg) =
  discard

# }}}
# {{{ drawCustom()
proc drawCustom(x, y: float, dp, vg) =
  discard

# }}}

# {{{ drawSolidWallHoriz()
proc drawSolidWallHoriz(x, y: float, dp, vg) =
  let
    sw = NormalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(dp.defaultFgColor)
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawOpenDoorHoriz()
proc drawOpenDoorHoriz(x, y: float, dp, vg) =
  let
    wallLen = (dp.gridSize * 0.3).int
    doorWidth = round(dp.gridSize * 0.1)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(dp.defaultFgColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door opening
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(x1, sw), snap(y1, sw))
  vg.lineTo(snap(x1, sw), snap(y2, sw))
  vg.stroke()

  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y1, sw))
  vg.lineTo(snap(x2, sw), snap(y2, sw))
  vg.stroke()

  # Wall end
  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawClosedDoorHoriz()
proc drawClosedDoorHoriz(x, y: float, dp, vg) =
  let
    wallLen = (dp.gridSize * 0.25).int
    doorWidth = round(dp.gridSize * 0.1)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(dp.defaultFgColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door
  vg.lineCap(lcjSquare)
  sw = ThinStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.rect(snap(x1, sw) + 1, snap(y1, sw), x2-x1-1, y2-y1+1)
  vg.stroke()

  # Wall end
  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}

# {{{ drawOriented()

# }}}
# {{{ setVertTransform()
proc setVertTransform(x, y: float, dp, vg) =
  vg.translate(x, y)
  vg.rotate(degToRad(90.0))

  # Because of the grid-snapping, we need to nudge the rotated image to the
  # left of the X-axis by 1 pixel if the stroke width is odd.
  vg.translate(0, -1)

# }}}
# {{{ drawSelection()
proc drawSelection(x, y: Natural, dp, vg) =
  let xPos = cellX(x, dp)
  let yPos = cellY(y, dp)

  vg.beginPath()
  vg.fillColor(dp.selectionColor)
  vg.rect(xPos, yPos, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawFloor()
proc drawFloor(m: Map, x, y: Natural, cursorActive: bool, dp, vg) =

  let xPos = cellX(x, dp)
  let yPos = cellY(y, dp)

  template drawOriented(drawProc: untyped) =
    drawBg()
    case m.getFloorOrientation(x,y):
    of Horiz:
      drawProc(xPos, yPos + dp.gridSize/2, dp, vg)
    of Vert:
      setVertTransform(xPos + dp.gridSize/2, yPos, dp, vg)
      drawProc(0, 0, dp, vg)
      vg.resetTransform()

  template draw(drawProc: untyped) =
    drawBg()
    drawProc(xPos, yPos, dp, vg)

  proc drawBg() =
    drawGround(xPos, yPos, dp.floorColor, dp, vg)
    if cursorActive:
      drawCursor(xPos, yPos, dp, vg)

  case m.getFloor(x,y)
  of fNone:
    if cursorActive:
      drawCursor(xPos, yPos, dp, vg)

  of fEmptyFloor:          drawBg()
  of fClosedDoor:          drawOriented(drawClosedDoorHoriz)
  of fOpenDoor:            drawOriented(drawOpenDoorHoriz)
  of fPressurePlate:       draw(drawPressurePlate)
  of fHiddenPressurePlate: draw(drawHiddenPressurePlate)
  of fClosedPit:           draw(drawClosedPit)
  of fOpenPit:             draw(drawOpenPit)
  of fHiddenPit:           draw(drawHiddenPit)
  of fCeilingPit:          draw(drawCeilingPit)
  of fStairsDown:          draw(drawStairsDown)
  of fStairsUp:            draw(drawStairsUp)
  of fSpinner:             draw(drawSpinner)
  of fTeleport:            draw(drawTeleport)
  of fCustom:              draw(drawCustom)

# }}}
# {{{ drawWall()
proc drawWall(x, y: float, wall: Wall, ot: Orientation, dp, vg) =

  template drawOriented(drawProc: untyped) =
    case ot:
    of Horiz:
      drawProc(x, y, dp, vg)
    of Vert:
      setVertTransform(x, y, dp, vg)
      drawProc(0, 0, dp, vg)
      vg.resetTransform()

  case wall
  of wNone:          discard
  of wWall:          drawOriented(drawSolidWallHoriz)
  of wIllusoryWall:  discard
  of wInvisibleWall: discard
  of wOpenDoor:      drawOriented(drawOpenDoorHoriz)
  of wClosedDoor:    drawOriented(drawClosedDoorHoriz)
  of wSecretDoor:    discard
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

# }}}
# {{{ drawWalls()
proc drawWalls(m: Map, x: Natural, y: Natural, dp, vg) =
  drawWall(cellX(x, dp), cellY(y, dp), m.getWall(x,y, North), Horiz, dp, vg)
  drawWall(cellX(x, dp), cellY(y, dp), m.getWall(x,y, West), Vert, dp, vg)

  if x == m.width-1:
    drawWall(cellX(x+1, dp), cellY(y, dp), m.getWall(x,y, East), Vert, dp, vg)

  if y == m.height-1:
    drawWall(cellX(x, dp), cellY(y+1, dp), m.getWall(x,y, South), Horiz, dp, vg)

# }}}

# {{{ drawMap*()
proc drawMap*(m: Map, cursorX, cursorY: Natural, selection: Option[Selection],
              dp, vg) =

  drawCellCoords(m, cursorX, cursorY, dp, vg)
  drawMapBackground(m, dp, vg)
  drawBackgroundGrid(m, dp, vg)

  if dp.drawOutline: drawOutline(m, dp, vg)

  for y in 0..<m.height:
    for x in 0..<m.width:
      let cursorActive = x == cursorX and y == cursorY
      drawFloor(m, x, y, cursorActive, dp, vg)

  if dp.drawCursorGuides:
    drawCursorGuides(m, cursorX, cursorY, dp, vg)

  for y in 0..<m.height:
    for x in 0..<m.width:
      drawWalls(m, x, y, dp, vg)

  if selection.isSome:
    let sel = selection.get
    for x in 0..<sel.width:
      for y in 0..<sel.height:
        if sel[x,y]: drawSelection(x, y, dp, vg)
# }}}

# vim: et:ts=2:sw=2:fdm=marker
