import lenientops
import nanovg

import common
import map


let
  gridSize = 22.0
  startX = 50.0
  startY = 50.0 + 32 * gridSize


proc cellX(x: Natural): float =
  startX + gridSize * x

proc cellY(y: Natural): float =
  startY - gridSize * y

proc drawBackgroundGrid(vg: NVGContext, m: Map) =
  vg.strokeColor(gray(0.0, 0.3))
  vg.strokeWidth(1.0)

  var endX = cellX(m.width)
  var endY = cellY(m.height)

  for x in 0..m.width:
    let x = cellX(x)
    vg.beginPath()
    vg.moveTo(x, startY)
    vg.lineTo(x, endY)
    vg.stroke()

  for y in 0..m.height:
    let y = cellY(y)
    vg.beginPath()
    vg.moveTo(startX, y)
    vg.lineTo(endX, y)
    vg.stroke()


proc drawCellCoords(vg: NVGContext, m: Map, cursorX, cursorY: Natural) =
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

  let endX = startX + gridSize * m.width
  let endY = startY - gridSize * m.height

  for x in 0..<m.width:
    let
      xPos = cellX(x) + gridSize/2
      coord = $x

    setTextHighlight(x == cursorX)

    discard vg.text(xPos, startY + 12, coord)
    discard vg.text(xPos, endY - 12, coord)

  for y in 0..<m.height:
    let
      yPos = cellY(y) - gridSize/2
      coord = $y

    setTextHighlight(y == cursorY)

    discard vg.text(startX - 12, yPos, coord)
    discard vg.text(endX + 12, yPos, coord)


proc drawMapBackground(vg: NVGContext, m: Map) =
  vg.strokeColor(gray(0.0, 0.7))
  vg.strokeWidth(1.0)

  let
    w = gridSize * m.width
    h = gridSize * m.height
    offs = max(w, h)
    lineSpacing = 3.0

  vg.scissor(startX, startY - h, w, h)

  var
    x1 = startX - offs
    y1 = startY
    x2 = startX + offs
    y2 = startY - 2*offs

  while x1 < startX + offs:
    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    vg.stroke()

    x1 += lineSpacing
    x2 += lineSpacing
    y1 += lineSpacing
    y2 += lineSpacing

  vg.resetScissor()


proc drawWallHoriz(vg: NVGContext, x, y: float, wall: Wall) =
  case wall
  of wNone: discard

  of wWall:
    vg.beginPath()
    vg.strokeColor(gray(0.1))
    vg.strokeWidth(3.0)
    vg.moveTo(x, y)
    vg.lineTo(x + gridSize, y)
    vg.stroke()

  of wDoor:
    let
      xs = x
      x1 = xs + gridSize * 0.3
      x2 = xs + gridSize * 0.7
      xe = xs + gridSize
      y1 = y - 2.5
      y2 = y + 2.5

    vg.strokeColor(gray(0.1))
    vg.strokeWidth(3.0)

    vg.lineCap(lcjSquare)
    vg.beginPath()
    vg.moveTo(xs, y)
    vg.lineTo(x1, y)
    vg.stroke()

    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x1, y2)
    vg.stroke()

    vg.beginPath()
    vg.moveTo(x2, y1)
    vg.lineTo(x2, y2)
    vg.stroke()

    vg.beginPath()
    vg.moveTo(x2, y)
    vg.lineTo(xe, y)
    vg.stroke()

  of wDoorway: discard

  of wSecretDoor: discard

  of wIllusoryWall: discard

  of wInvisibleWall: discard


proc drawWallVert(vg: NVGContext, x, y: float, wall: Wall) =
  case wall
  of wNone: discard

  of wWall:
    vg.beginPath()
    vg.strokeColor(gray(0.1))
    vg.strokeWidth(3.0)
    vg.moveTo(x, y - gridSize)
    vg.lineTo(x, y)
    vg.stroke()

  of wDoor:
    let
      x1 = x - 2.5
      x2 = x + 2.5
      ys = y - gridSize
      y1 = ys + gridSize * 0.3
      y2 = ys + gridSize * 0.7
      ye = ys + gridSize

    vg.strokeColor(gray(0.1))
    vg.strokeWidth(3.0)

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

  of wDoorway: discard

  of wSecretDoor: discard

  of wIllusoryWall: discard

  of wInvisibleWall: discard


proc drawCursor(vg: NVGContext, m: Map, cursorX, cursorY: Natural,
                guides: bool = false) =
  let
    x = cellX(cursorX)
    y = cellY(cursorY)

  if guides:
    let
      w = gridSize * m.width
      h = gridSize * m.height

    vg.beginPath()
    vg.fillColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeWidth(1.0)
    vg.rect(x, startY - h, gridSize, h)
    vg.fill()
    vg.stroke()

    vg.beginPath()
    vg.rect(startX, y - gridSize, w, gridSize)
    vg.strokeColor(rgba(1.0, 0.65, 0.0, 0.2))
    vg.strokeWidth(1.0)
    vg.fill()
    vg.stroke()

  vg.beginPath()
  vg.rect(x, y - gridSize, gridSize, gridSize)

#  vg.strokeColor(gray(0))
#  vg.strokeWidth(4.0)
#  vg.stroke()
#
#  vg.strokeColor(rgb(1.0, 0.8, 0.5))
  vg.fillColor(rgb(1.0, 0.65, 0.0))
#  vg.strokeWidth(2.0)
#  vg.stroke()
  vg.fill()


proc drawFloor(vg: NVGContext, m: Map, x: Natural, y: Natural) =
  if m.getFloor(x,y) != fNone:
    let
      x = cellX(x)
      y = cellY(y)

    vg.beginPath()
    vg.fillColor(gray(0.9))
    vg.strokeColor(gray(0.7))
    vg.strokeWidth(1.0)
    vg.rect(x, y - gridSize, gridSize, gridSize)
    vg.fill()
    vg.stroke()


proc drawWalls(vg: NVGContext, m: Map, x: Natural, y: Natural) =
  let
    xPos = cellX(x)
    yPos = cellY(y)

  vg.lineCap(lcjRound)
  drawWallHoriz(vg, xPos, yPos, m.getWall(x,y, South))
  drawWallVert(vg, xPos, yPos, m.getWall(x,y, West))

  if x == m.width-1:
    drawWallVert(vg, xPos + gridSize, yPos, m.getWall(x,y, East))

  if y == m.height-1:
    drawWallHoriz(vg, xPos, yPos - gridSize, m.getWall(x,y, North))


proc drawMap*(vg: NVGContext, m: Map, cursorX, cursorY: Natural) =
  drawCellCoords(vg, m, cursorX, cursorY)
  drawMapBackground(vg, m)
  drawBackgroundGrid(vg, m)

  for y in 0..<m.height:
    for x in 0..<m.width:
      drawFloor(vg, m, x, y)

  drawCursor(vg, m, cursorX, cursorY, guides=false)

  for y in 0..<m.height:
    for x in 0..<m.width:
      drawWalls(vg, m, x, y)


# vim: et:ts=2:sw=2:fdm=marker
