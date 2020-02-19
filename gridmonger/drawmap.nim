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
  MaxZoomLevel*        = 15


# Naming conventions
# ------------------
#
# The names `col`, `row` (or `c`, `r`) refer to the zero-based coordinates of
# a cell in a map. The cell in the top-left corner is the origin.
#
# `screenCol` and `screenRow` refer to the cell coodinates of a screen buffer
# that contains a rectangular area of a map (just the area that's visible on
# the screen).
#
# Anything with `x` or `y` in the name refers to pixel-coordinates within the
# window's drawing area (top-left corner is the origin).
#
# All drawing procs interpret the passed in `(x,y)` coordinates as the
# upper-left corner of the object (e.g. a cell).
#

# {{{ Types
type
  MapStyle* = ref object
    cellCoordsColor*:     Color
    cellCoordsColorHi*:   Color
    cellCoordsFontSize*:  float
    cursorColor*:         Color
    cursorGuideColor*:    Color
    defaultFgColor*:      Color
    floorColor*:          Color
    gridColorBackground*: Color
    gridColorFloor*:      Color
    mapBackgroundColor*:  Color
    mapOutlineColor*:     Color
    pastePreviewColor*:   Color
    selectionColor*:      Color


  DrawMapParams* = ref object
    startX*:       float
    startY*:       float

    cursorCol*:    Natural
    cursorRow*:    Natural

    startCol*:     Natural
    startRow*:     Natural
    numCols*:      Natural
    numRows*:      Natural

    selection*:    Option[Selection]
    selRect*:      Option[SelectionRect]
    pastePreview*: Option[CopyBuffer]

    drawOutline*:      bool
    drawCursorGuides*: bool

    # internal
    zoomLevel:         Natural
    gridSize:          float
    normalStrokeWidth: float

    vertTransformYFudgeFactor: float


  DrawMapContext* = object
    ms*: MapStyle
    dp*: DrawMapParams
    vg*: NVGContext

# }}}

using
  dp: DrawMapParams
  ctx: DrawMapContext

# {{{ zoomLevel*()
proc getZoomLevel*(dp): Natural = dp.zoomLevel

# }}}
# {{{ setZoomLevel*()
proc setZoomLevel*(dp; zl: Natural) =
  assert zl <= MaxZoomLevel
  let
    MinGridSize = 18.0
    ZoomFactor = 1.08

  dp.zoomLevel = zl
  dp.gridSize = floor(MinGridSize * pow(ZoomFactor, zl.float))

  if zl <= 10:
    dp.normalStrokeWidth = 3.0
    dp.vertTransformYFudgeFactor = -1.0
  else:
    dp.normalStrokeWidth = 4.0
    dp.vertTransformYFudgeFactor = 0.0

# }}}
# {{{ incZoomLevel*()
proc incZoomLevel*(dp) =
  if dp.zoomLevel < MaxZoomLevel:
    setZoomLevel(dp, dp.zoomLevel+1)

# }}}
# {{{ decZoomLevel*()
proc decZoomLevel*(dp) =
  if dp.zoomLevel > 0:
    setZoomLevel(dp, dp.zoomLevel-1)

# }}}
# {{{ numDisplayableRows*()
proc numDisplayableRows*(dp; height: float): Natural =
  max(height / dp.gridSize, 0).int

# }}}
# {{{ numDisplayableCols*()
proc numDisplayableCols*(dp; width: float): Natural =
  max(width / dp.gridSize, 0).int

# }}}

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
proc drawBackgroundGrid(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let strokeWidth = UltrathinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.gridColorBackground)
  vg.strokeWidth(strokeWidth)

  let endX = snap(cellX(dp.numCols, dp), strokeWidth)
  let endY = snap(cellY(dp.numRows, dp), strokeWidth)

  for x in 0..dp.numCols:
    let x = snap(cellX(x, dp), strokeWidth)
    let y = snap(dp.startY, strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(x, endY)
    vg.stroke()

  for y in 0..dp.numRows:
    let x = snap(dp.startX, strokeWidth)
    let y = snap(cellY(y, dp), strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(endX, y)
    vg.stroke()

# }}}
# {{{ drawCellCoords()
proc drawCellCoords(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fontFace("sans")
  vg.fontSize(ms.cellCoordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fillColor(ms.cellCoordsColorHi)
    else:
      vg.fillColor(ms.cellCoordsColor)
      vg.fontFace("sans")

  let endX = dp.startX + dp.gridSize * dp.numCols
  let endY = dp.startY + dp.gridSize * dp.numRows

  for x in 0..<dp.numCols:
    let
      xPos = cellX(x, dp) + dp.gridSize/2
      coord = $(dp.startCol + x)

    setTextHighlight(x == dp.cursorCol)

    discard vg.text(xPos, dp.startY - 12, coord)
    discard vg.text(xPos, endY + 12, coord)

  for y in 0..<dp.numRows:
    let
      yPos = cellY(y, dp) + dp.gridSize/2
      coord = $(dp.startRow + y)

    setTextHighlight(y == dp.cursorRow)

    discard vg.text(dp.startX - 12, yPos, coord)
    discard vg.text(endX + 12, yPos, coord)


# }}}
# {{{ drawMapBackground()
proc drawMapBackground(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let strokeWidth = UltrathinStrokeWidth

  vg.strokeColor(ms.mapBackgroundColor)
  vg.strokeWidth(strokeWidth)

  let
    w = dp.gridSize * dp.numCols
    h = dp.gridSize * dp.numRows
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
proc drawCursor(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fillColor(ms.cursorColor)
  vg.beginPath()
  vg.rect(x+1, y+1, dp.gridSize-1, dp.gridSize-1)
  vg.fill()

# }}}
# {{{ drawCursorGuides()
proc drawCursorGuides(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    x = cellX(dp.cursorCol - dp.startCol, dp)
    y = cellY(dp.cursorRow - dp.startRow, dp)
    w = dp.gridSize * dp.numCols
    h = dp.gridSize * dp.numRows

  vg.fillColor(ms.cursorGuideColor)
  vg.strokeColor(ms.cursorGuideColor)
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
proc drawOutline(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  func check(col, row: int): bool =
    let c = max(min(col, m.cols-1), 0)
    let r = max(min(row, m.rows-1), 0)
    m.getFloor(c,r) != fNone

  func isOutline(c, r: Natural): bool =
    check(c,   r+1) or
    check(c+1, r+1) or
    check(c+1, r  ) or
    check(c+1, r-1) or
    check(c  , r-1) or
    check(c-1, r-1) or
    check(c-1, r  ) or
    check(c-1, r+1)

  for r in 0..<m.rows:
    for c in 0..<m.cols:
      if isOutline(c, r):
        let
          sw = UltrathinStrokeWidth
          x = snap(cellX(c, dp), sw)
          y = snap(cellY(r, dp), sw)

        vg.strokeWidth(sw)
        vg.fillColor(ms.mapOutlineColor)
        vg.strokeColor(ms.mapOutlineColor)

        vg.beginPath()
        vg.rect(x, y, dp.gridSize, dp.gridSize)
        vg.fill()
        vg.stroke()

# }}}

# {{{ drawGround()
proc drawGround(x, y: float, color: Color, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let sw = UltrathinStrokeWidth

  vg.beginPath()
  vg.fillColor(color)
  vg.strokeColor(ms.gridColorFloor)
  vg.strokeWidth(sw)
  vg.rect(snap(x, sw), snap(y, sw), dp.gridSize, dp.gridSize)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.defaultFgColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float, ctx) =
  discard

# }}}
# {{{ drawClosedPit()
proc drawClosedPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.defaultFgColor)
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
proc drawOpenPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)
  vg.fillColor(ms.defaultFgColor)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float, ctx) =
  discard

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float, ctx) =
  discard

# }}}
# {{{ drawStairsDown()
proc drawStairsDown(x, y: float, ctx) =
  discard

# }}}
# {{{ drawStairsUp()
proc drawStairsUp(x, y: float, ctx) =
  discard

# }}}
# {{{ drawSpinner()
proc drawSpinner(x, y: float, ctx) =
  discard

# }}}
# {{{ drawTeleport()
proc drawTeleport(x, y: float, ctx) =
  discard

# }}}
# {{{ drawCustom()
proc drawCustom(x, y: float, ctx) =
  discard

# }}}

# {{{ drawSolidWallHoriz()
proc drawSolidWallHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = dp.normalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.defaultFgColor)
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawOpenDoorHoriz()
proc drawOpenDoorHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

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

  var sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)

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
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawClosedDoorHoriz()
proc drawClosedDoorHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

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

  var sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)

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
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}

# {{{ setVertTransform()
proc setVertTransform(x, y: float, ctx) =
  let dp = ctx.dp
  let vg = ctx.vg

  vg.translate(x, y)
  vg.rotate(degToRad(90.0))

  # We need to use some fudge factor here because of the grid snapping...
  vg.translate(0, dp.vertTransformYFudgeFactor)

# }}}
# {{{ drawSelectionCell()
proc drawSelectionCell(col, row: Natural, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let x = cellX(col - dp.startCol, dp)
  let y = cellY(row - dp.startRow, dp)

  vg.beginPath()
  vg.fillColor(ms.selectionColor)
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawSelection()
proc drawSelection(ctx) =
  let dp = ctx.dp

  if dp.selection.isSome:
    let sel = dp.selection.get

    for c in dp.startCol..<(dp.startCol + dp.numCols):
      for r in dp.startRow..<(dp.startRow + dp.numRows):

        if dp.selRect.isSome:
          let sr = dp.selRect.get
          if sr.fillValue == true:
            if sel[c,r] or sr.rect.contains(c,r):
              drawSelectionCell(c, r, ctx)
          else:
            if not sr.rect.contains(c,r) and sel[c,r]:
              drawSelectionCell(c, r, ctx)
        else:
          if sel[c,r]:
            drawSelectionCell(c, r, ctx)

# }}}
# {{{ drawFloor()
proc drawFloor(screenBuf: Map, screenCol, screenRow: Natural,
               cursorActive: bool, ctx) =

  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let x = cellX(screenCol, dp)
  let y = cellY(screenRow, dp)

  template drawOriented(drawProc: untyped) =
    drawBg()
    case screenBuf.getFloorOrientation(screenCol, screenRow):
    of Horiz:
      drawProc(x, y + dp.gridSize/2, ctx)
    of Vert:
      setVertTransform(x + dp.gridSize/2, y, ctx)
      drawProc(0, 0, ctx)
      vg.resetTransform()

  template draw(drawProc: untyped) =
    drawBg()
    drawProc(x, y, ctx)

  proc drawBg() =
    drawGround(x, y, ms.floorColor, ctx)
    if cursorActive:
      drawCursor(x, y, ctx)

  case screenBuf.getFloor(screenCol, screenRow)
  of fNone:
    if cursorActive:
      drawCursor(x, y, ctx)

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
proc drawWall(x, y: float, wall: Wall, ot: Orientation, ctx) =
  let vg = ctx.vg

  template drawOriented(drawProc: untyped) =
    case ot:
    of Horiz:
      drawProc(x, y, ctx)
    of Vert:
      setVertTransform(x, y, ctx)
      drawProc(0, 0, ctx)
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
proc drawWalls(screenBuf: Map, screenCol, screenRow: Natural, ctx) =
  let dp = ctx.dp

  let floorEmpty = screenBuf.getFloor(screenCol, screenRow) == fNone

  if screenRow > 0 or (screenRow == 0 and not floorEmpty):
    drawWall(
      cellX(screenCol, dp),
      cellY(screenRow, dp),
      screenBuf.getWall(screenCol, screenRow, North), Horiz, ctx
    )

  if screenCol > 0 or (screenCol == 0 and not floorEmpty):
    drawWall(
      cellX(screenCol, dp),
      cellY(screenRow, dp),
      screenBuf.getWall(screenCol, screenRow, West), Vert, ctx
    )

  let endCol = dp.numCols-1
  if screenCol < endCol or (screenCol == endCol and not floorEmpty):
    drawWall(
      cellX(screenCol+1, dp),
      cellY(screenRow, dp),
      screenBuf.getWall(screenCol, screenRow, East), Vert, ctx
    )

  let endRow = dp.numRows-1
  if screenRow < endRow or (screenRow == endRow and not floorEmpty):
    drawWall(
      cellX(screenCol, dp),
      cellY(screenRow+1, dp),
      screenBuf.getWall(screenCol, screenRow, South), Horiz, ctx
    )

# }}}

# {{{ drawMap*()
proc drawMap*(m: Map, ctx) =
  let dp = ctx.dp

  assert dp.startCol + dp.numCols <= m.cols
  assert dp.startRow + dp.numRows <= m.rows

  drawCellCoords(ctx)
  drawMapBackground(ctx)
  drawBackgroundGrid(ctx)

  if dp.drawOutline:
    drawOutline(m, ctx)

  let screenBuf = newMapFrom(
    m, rectN(
      dp.startCol,
      dp.startRow,
      dp.startCol + dp.numCols,
      dp.startRow + dp.numRows)
  )

  if dp.pastePreview.isSome:
    screenBuf.paste(dp.cursorCol, dp.cursorRow,
              dp.pastePreview.get.map, dp.pastePreview.get.selection)

  for r in 0..<dp.numRows:
    for c in 0..<dp.numCols:
      let cursorActive = dp.startCol+c == dp.cursorCol and
                         dp.startRow+r == dp.cursorRow
      drawFloor(screenBuf, c, r, cursorActive, ctx)
      drawWalls(screenBuf, c, r, ctx)

  if dp.drawCursorGuides:
    drawCursorGuides(m, ctx)

  if dp.selection.isSome:
    drawSelection(ctx)

  # TODO
#  if pastePreview.isSome:
#    drawPastePreviewHighlight(pastePreview.get.selection,
#                              cursorCol - startCol, cursorRow - startRow,
#                              numCols, numRows, dp, vg)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
