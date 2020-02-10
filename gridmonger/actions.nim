import common
import map
import undomanager



using
  um: var UndoManager[Map]


proc storeSingleCellUndoState(m: var Map, x, y: Natural,
                              redoAction: proc (s: var Map), um) =

  var undoMap = newMapFrom(m, x, y, width=1, height=1)

  um.storeUndoState(
    undoAction = proc (s: var Map) =
      s.copyFrom(undoMap, srcX=0, srcY=0, width=1, height=1, destX=x, destY=y),

    redoAction=redoAction
  )


# {{{ eraseCellWalls()
proc eraseCellWalls(m: var Map, x, y: Natural) =
  m.setWall(x,y, North, wNone)
  m.setWall(x,y, West,  wNone)
  m.setWall(x,y, South, wNone)
  m.setWall(x,y, East,  wNone)

# }}}

# {{{ eraseCellWallsAction*()
proc eraseCellWallsAction*(m: var Map, x, y: Natural, um) =
  let action = proc (s: var Map) =
    s.eraseCellWalls(x, y)

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)


# }}}
# {{{ eraseCellAction*()
proc eraseCellAction*(m: var Map, x, y: Natural, um) =
  let action = proc (m: var Map) =
    # TODO fill should be improved
    m.fill(x, y, x, y)
    m.eraseCellWalls(x, y)

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)

# }}}
# {{{ setWallAction*()
proc setWallAction*(m: var Map, x, y: Natural, dir: Direction, w: Wall, um) =
  let action = proc (m: var Map) =
    m.setWall(x, y, dir, w)

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)

# }}}
# {{{ setFloorAction*()
proc setFloorAction*(m: var Map, x, y: Natural, f: Floor, um) =
  let action = proc (m: var Map) =
    m.setFloor(x, y, f)

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)

# }}}
# {{{ excavateAction*()
proc excavateAction*(m: var Map, x, y: Natural, um) =
  let action = proc (m: var Map) =
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

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)

# }}}
# {{{ toggleFloorOrientationAction*()
proc toggleFloorOrientationAction*(m: var Map, x, y: Natural, um) =
  let action = proc (m: var Map) =
    let newOt = if m.getFloorOrientation(x, y) == Horiz: Vert else: Horiz
    m.setFloorOrientation(x, y, newOt)

  storeSingleCellUndoState(m, x, y, action, um)

  action(m)

# }}}


# vim: et:ts=2:sw=2:fdm=marker
