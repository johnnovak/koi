import options

# TODO
# - use groupStart/groupEnd undo state markers instead of groupWithPrev flag
# - store group name in groupStart
# - unit tests

type
  UndoManager*[S, R] = ref object
    states:        seq[UndoState[S, R]]
    currState:     int
    lastSaveState: int

  ActionProc*[S, R] = proc (s: var S): R

  UndoState[S, R] = object
    action:        ActionProc[S, R]
    undoAction:    ActionProc[S, R]
    groupWithPrev: bool


proc initUndoManager*[S, R](m: var UndoManager[S, R]) =
  m.states = @[]
  m.currState = 0
  m.lastSaveState = 0

proc newUndoManager*[S, R](): UndoManager[S, R] =
  result = new UndoManager[S, R]
  initUndoManager(result)


proc storeUndoState*[S, R](m: var UndoManager[S, R],
                           action, undoAction: ActionProc[S, R],
                           groupWithPrev: bool = false) =

  if m.states.len == 0:
    m.states.add(UndoState[S, R]())
    m.currState = 0

  # Discard later states if we're not at the last one
  elif m.currState < m.states.high:
    m.states.setLen(m.currState+1)

  m.states[m.currState].action = action
  m.states.add(UndoState[S, R](action: nil, undoAction: undoAction,
                               groupWithPrev: groupWithPrev))
  inc(m.currState)


proc canUndo*[S, R](m: UndoManager[S, R]): bool =
  m.currState > 0

proc undo*[S, R](m: var UndoManager[S, R], s: var S): R =
  if m.canUndo():
    result = m.states[m.currState].undoAction(s)
    let undoNextState = m.states[m.currState].groupWithPrev
    dec(m.currState)
    if undoNextState:
      discard m.undo(s)

proc canRedo*[S, R](m: UndoManager[S, R]): bool =
  m.currState < m.states.high

proc redo*[S, R](m: var UndoManager[S, R], s: var S): R =
  if m.canRedo():
    result = m.states[m.currState].action(s)
    inc(m.currState)
    let redoNextState = m.currState+1 <= m.states.high and
                        m.states[m.currState+1].groupWithPrev
    if redoNextState:
      result = m.redo(s)

proc setLastSaveState*[S, R](m: var UndoManager[S, R]) =
  m.lastSaveState = m.currState

proc isModified*[S, R](m: UndoManager[S, R]): bool =
  m.currState != m.lastSaveState

# vim: et:ts=2:sw=2:fdm=marker
