import common
import map
import undomanager


using
  m: var Map
  um: var UndoManager[Map]

# {{{ singleCellAction()
template singleCellAction(m; x, y: Natural, um; body: untyped) =
  let action = proc (m: var Map) =
    body

  var undoMap = newMapFrom(m, Rect[Natural](x1: x, y1: y, x2: x+1, y2: y+1))
  var undoAction = proc (s: var Map) = 
    s.copyFrom(undoMap, Rect[Natural](x1: 0, y1: 0, x2: 1, y2: 1),
               destX=x, destY=y)

  um.storeUndoState(undoAction, redoAction=action)

  action(m)

# }}}

# {{{ eraseCellWalls()
proc eraseCellWalls(m; x, y: Natural) =
  m.setWall(x,y, North, wNone)
  m.setWall(x,y, West,  wNone)
  m.setWall(x,y, South, wNone)
  m.setWall(x,y, East,  wNone)

# }}}

# {{{ eraseCellWallsAction*()
proc eraseCellWallsAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    m.eraseCellWalls(x, y)

# }}}
# {{{ eraseCellAction*()
proc eraseCellAction*(m; x, y: Natural, um) =
  singleCellAction(m, x, y, um):
    # TODO fill should be improved
    m.setFloor(x, y, fNone)
    m.eraseCellWalls(x, y)

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

    if y == m.mapHeight()-1 or m.getFloor(x,y+1) == fNone:
      m.setWall(x,y, South, wWall)
    else:
      m.setWall(x,y, South, wNone)

    if x == m.mapWidth()-1 or m.getFloor(x+1,y) == fNone:
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
