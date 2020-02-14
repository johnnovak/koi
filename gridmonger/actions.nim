import common
import map
import selection
import undomanager


using
  m: var Map
  um: var UndoManager[Map]

# {{{ cellAreaAction()
template cellAreaAction(m; r: Rect[Natural], um; body: untyped) =
  let action = proc (m: var Map) =
    body

  var undoMap = newMapFrom(m, r)
  var undoAction = proc (s: var Map) =
    s.copyFrom(destX=r.x1, destY=r.y1,
               undoMap, rectN(0, 0, r.width, r.height))

  um.storeUndoState(undoAction, redoAction=action)

  action(m)

# }}}
# {{{ singleCellAction()
template singleCellAction(m; x, y: Natural, um; body: untyped) =
  cellAreaAction(m, rectN(x, y, x+1, y+1), um, body)

# }}}

# {{{ eraseCellWalls()
proc eraseCellWalls(m; x, y: Natural) =
  m.setWall(x,y, North, wNone)
  m.setWall(x,y, West,  wNone)
  m.setWall(x,y, South, wNone)
  m.setWall(x,y, East,  wNone)

# }}}
# {{{ eraseCell()
proc eraseCell(m; x, y: Natural) =
  m.setFloor(x, y, fNone)
  m.eraseCellWalls(x, y)

# }}}
#
# {{{ eraseCellWallsAction*()
proc eraseCellWallsAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    m.eraseCellWalls(x, y)

# }}}
# {{{ eraseCellAction*()
proc eraseCellAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    eraseCell(m, x, y)

# }}}
# {{{ eraseSelectionAction*()
proc eraseSelectionAction*(m; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(m, bbox, um):
    for y in bbox.y1..<bbox.y2:
      for x in bbox.x1..<bbox.x2:
        if sel[x,y]:
          eraseCell(m, x, y)

# }}}
# {{{ setWallAction*()
proc setWallAction*(m; x, y: Natural, dir: Direction, w: Wall, um) =
  singleCellAction(m, x, y, um):
    m.setWall(x, y, dir, w)

# }}}
# {{{ setFloorAction*()
proc setFloorAction*(m; x, y: Natural, f: Floor, um) =
  singleCellAction(m, x, y, um):
    m.setFloor(x, y, f)

# }}}
# {{{ excavateAction*()
proc excavateAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    if m.getFloor(x,y) == fNone:
      m.setFloor(x,y, fEmptyFloor)

    if y == 0 or m.getFloor(x,y-1) == fNone:
      m.setWall(x,y, North, wWall)
    else:
      m.setWall(x,y, North, wNone)

    if x == 0 or m.getFloor(x-1,y) == fNone:
      m.setWall(x,y, West, wWall)
    else:
      m.setWall(x,y, West, wNone)

    if y == m.height-1 or m.getFloor(x,y+1) == fNone:
      m.setWall(x,y, South, wWall)
    else:
      m.setWall(x,y, South, wNone)

    if x == m.width-1 or m.getFloor(x+1,y) == fNone:
      m.setWall(x,y, East, wWall)
    else:
      m.setWall(x,y, East, wNone)

# }}}
# {{{ toggleFloorOrientationAction*()
proc toggleFloorOrientationAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    let newOt = if m.getFloorOrientation(x, y) == Horiz: Vert else: Horiz
    m.setFloorOrientation(x, y, newOt)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
