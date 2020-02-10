import options

import map


type
  UndoManager*[S] = object
    undoStates: seq[UndoState[S]]
    undoPos: int

  StateChangeProc*[S] = proc (s: var S)

  UndoState[S] = object
    nextState: StateChangeProc[S]
    prevState: StateChangeProc[S]


proc initUndoManager*[S](m: var UndoManager[S]) =
  m.undoStates = @[]
  m.undoPos = -1


proc storeUndoState*[S](m: var UndoManager[S],
                        undoAction: StateChangeProc[S],
                        redoAction: StateChangeProc[S]) =

  if m.undoStates.len == 0:
    m.undoStates.add(UndoState[S]())
    m.undoPos = 0

  # Discard later states if we're not at the last one
  elif m.undoPos <= m.undoStates.high:
    m.undoStates.setLen(m.undoPos+1)

  m.undoStates[m.undoPos].nextState = redoAction
  m.undoStates.add(UndoState[S](nextState: nil, prevState: undoAction))
  inc(m.undoPos)


proc canUndo*[S](m: var UndoManager[S]): bool =
  m.undoPos > 0

proc undo*[S](m: var UndoManager[S], s: var S) =
  if canUndo():
    m.undoStates[m.undoPos].prevState(m)
    dec(m.undoPos)

proc canRedo*[S](m: var UndoManager[S]): bool =
  m.undoPos < m.undoStates.high-1

proc redo*[S](m: var UndoManager[S], s: var S) =
  if canRedo():
    m.undoStates[m.undoPos].nextState(s)
    inc(m.undoPos)


# vim: et:ts=2:sw=2:fdm=marker
