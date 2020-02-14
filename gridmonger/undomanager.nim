import options


type
  UndoManager*[S] = ref object
    states: seq[UndoState[S]]
    currState: int

  UndoStateChangeProc*[S] = proc (s: var S)

  UndoState[S] = object
    nextState: UndoStateChangeProc[S]
    prevState: UndoStateChangeProc[S]


proc initUndoManager*[S](m: var UndoManager[S]) =
  m.states = @[]
  m.currState = -1

proc newUndoManager*[S](): UndoManager[S] =
  result = new UndoManager[S]
  initUndoManager(result)


proc storeUndoState*[S](m: var UndoManager[S],
                        undoAction: UndoStateChangeProc[S],
                        redoAction: UndoStateChangeProc[S]) =

  if m.states.len == 0:
    m.states.add(UndoState[S]())
    m.currState = 0

  # Discard later states if we're not at the last one
  elif m.currState < m.states.high:
    m.states.setLen(m.currState+1)

  m.states[m.currState].nextState = redoAction
  m.states.add(UndoState[S](nextState: nil, prevState: undoAction))
  inc(m.currState)


proc canUndo*[S](m: var UndoManager[S]): bool =
  m.currState > 0

proc undo*[S](m: var UndoManager[S], s: var S) =
  if m.canUndo():
    m.states[m.currState].prevState(s)
    dec(m.currState)

proc canRedo*[S](m: var UndoManager[S]): bool =
  m.currState < m.states.high

proc redo*[S](m: var UndoManager[S], s: var S) =
  if m.canRedo():
    m.states[m.currState].nextState(s)
    inc(m.currState)


# vim: et:ts=2:sw=2:fdm=marker
