import map


type
  ActionProc* = proc (m: var Map)

  UndoStateKind* = enum
    uskRectAreaChange

  UndoState* = object
    case kind*: UndoStateKind
    of uskRectAreaChange:
      rectX*, rectY*: Natural
      map*: Map
      # TODO skipGrid

var
  g_undoStates: seq[UndoState]
  g_undoPos: int
  g_redoActions: seq[ActionProc]


proc initUndo*() =
  g_undoStates = @[]
  g_undoPos = -1
  g_redoActions = @[]


proc storeUndo*(undoState: UndoState, redoAction: ActionProc) =
  # Discard later undo states if we're not at the last step in the history
  if g_undoPos < g_undoStates.len-1:
    let newLen = g_undoPos+1
    g_undoStates.setLen(newLen)
    g_redoActions.setLen(newLen)

  g_undoStates.add(undoState)
  g_redoActions.add(redoAction)
  inc(g_undoPos)


proc restoreUndoState(m: var Map, undoState: UndoState) =
  # TODO
  discard


proc canUndo(): bool = g_undoStates.len > 0

proc undo*(m: var Map) =
  if canUndo():
    restoreUndoState(m, g_undoStates[g_undoPos])
    dec(g_undoPos)


proc canRedo*(): bool = g_undoPos+1 <= g_redoActions.len-1

proc redo*(m: var Map) =
  if canRedo():
    let redoAction = g_redoActions[g_undoPos+1]
    redoAction(m)
    inc(g_undoPos)


# vim: et:ts=2:sw=2:fdm=marker
