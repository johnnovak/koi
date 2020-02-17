import options

import common
import map
import selection
import undomanager


using
  currMap: var Map
  um: var UndoManager[Map]

# {{{ cellAreaAction()
template cellAreaAction(currMap; r: Rect[Natural], um;
                        actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody

  var undoMap = newMapFrom(currMap, r)
  var undoAction = proc (m: var Map) =
    m.copyFrom(destCol=r.x1, destRow=r.y1,
               undoMap, rectN(0, 0, r.width, r.height))

  um.storeUndoState(undoAction, redoAction=action)
  action(currMap)

# }}}
# {{{ singleCellAction()
template singleCellAction(currMap; x, y: Natural, um;
                          actionMap, actionBody: untyped) =
  cellAreaAction(currMap, rectN(x, y, x+1, y+1), um, actionMap, actionBody)

# }}}

# {{{ eraseCellWallsAction*()
proc eraseCellWallsAction*(currMap; x, y: Natural, um) =
  singleCellAction(currMap, x, y, um, m):
    m.eraseCellWalls(x, y)

# }}}
# {{{ eraseCellAction*()
proc eraseCellAction*(currMap; x, y: Natural, um) =
  singleCellAction(currMap, x, y, um, m):
    m.eraseCell(x, y)

# }}}
# {{{ eraseSelectionAction*()
proc eraseSelectionAction*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, m):
    for y in 0..<sel.height:
      for x in 0..<sel.width:
        if sel[x,y]:
          m.eraseCell(bbox.x1 + x, bbox.y1 + y)

# }}}
# {{{ pasteAction*()
proc pasteAction*(currMap; x, y: Natural, cb: CopyBuffer, um) =
  let r = rectN(x, y, x + cb.map.width, y + cb.map.height).intersect(
    rectN(0, 0, currMap.width, currMap.height)
  )
  if r.isSome:
    cellAreaAction(currMap, r.get, um, m):
      m.copyFrom(x, y, cb.map, rectN(0, 0, cb.map.width, cb.map.height))

# }}}
# {{{ setWallAction*()
proc setWallAction*(currMap; x, y: Natural, dir: Direction, w: Wall, um) =
  singleCellAction(currMap, x, y, um, m):
    m.setWall(x, y, dir, w)

# }}}
# {{{ setFloorAction*()
proc setFloorAction*(currMap; x, y: Natural, f: Floor, um) =
  singleCellAction(currMap, x, y, um, m):
    m.setFloor(x, y, f)

# }}}
# {{{ excavateAction*()
proc excavateAction*(currMap; x, y: Natural, um) =
  singleCellAction(currMap, x, y, um, m):
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
# TODO unnecessary
proc toggleFloorOrientationAction*(currMap; x, y: Natural, um) =
  singleCellAction(currMap, x, y, um, m):
    let newOt = if m.getFloorOrientation(x, y) == Horiz: Vert else: Horiz
    m.setFloorOrientation(x, y, newOt)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
