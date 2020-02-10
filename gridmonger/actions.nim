import common
import map
import undo


# {{{ eraseCellWalls()
proc eraseCellWalls(m: var Map, x, y: Natural) =
  m.setWall(x,y, North, wNone)
  m.setWall(x,y, West,  wNone)
  m.setWall(x,y, South, wNone)
  m.setWall(x,y, East,  wNone)

# }}}

# {{{ eraseCellWallsAction*()
proc eraseCellWallsAction*(m: var Map, x, y: Natural) =
  let action = proc (m: var Map) =
    m.eraseCellWalls(x, y)

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}
# {{{ eraseCellAction*()
proc eraseCellAction*(m: var Map, x, y: Natural) =
  let action = proc (m: var Map) =
    # TODO fill should be improved
    m.fill(x, y, x, y)
    m.eraseCellWalls(x, y)

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}
# {{{ setWallAction*()
proc setWallAction*(m: var Map, x, y: Natural, dir: Direction, w: Wall) =
  let action = proc (m: var Map) =
    m.setWall(x, y, dir, w)

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}
# {{{ setFloorAction*()
proc setFloorAction*(m: var Map, x, y: Natural, f: Floor) =
  let action = proc (m: var Map) =
    m.setFloor(x, y, f)

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}
# {{{ excavateAction*()
proc excavateAction*(m: var Map, x, y: Natural) =
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

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}
# {{{ toggleFloorOrientationAction*()
proc toggleFloorOrientationAction*(m: var Map, x, y: Natural) =
  let action = proc (m: var Map) =
    let newOt = if m.getFloorOrientation(x, y) == Horiz: Vert else: Horiz
    m.setFloorOrientation(x, y, newOt)

  storeUndo(
    UndoState(
      kind: uskRectAreaChange,
      rectX: x, rectY: y,
      map: newMapFrom(m, x, y, width=1, height=1)
    ),
    redoAction=action
  )

  action(m)

# }}}


# vim: et:ts=2:sw=2:fdm=marker
