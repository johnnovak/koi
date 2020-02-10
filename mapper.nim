import strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg

import common
import drawmap
import map
import utils


# {{{ Globals
var
  g_vg: NVGContext

  g_map: Map
  g_cursorX: Natural
  g_cursorY: Natural

# }}}

# {{{ createWindow()
proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 800, h: 800)
  cfg.title = "Dungeon PowerMapper Deluxe v0.1 alpha"
  cfg.resizable = true
  cfg.visible = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = true
  cfg.nMultiSamples = 4

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  newWindow(cfg)

# }}}
# {{{ loadData()
proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add regular font.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add bold font.\n"

# }}}

# {{{ render()
proc render(win: Window, res: tuple[w, h: int32] = (0,0)) =
  let
    (winWidth, winHeight) = win.size
    (fbWidth, fbHeight) = win.framebufferSize
    pxRatio = fbWidth / winWidth

  # Update and render
  glViewport(0, 0, fbWidth, fbHeight)

  glClearColor(0.4, 0.4, 0.4, 1.0)

  glClear(GL_COLOR_BUFFER_BIT or
          GL_DEPTH_BUFFER_BIT or
          GL_STENCIL_BUFFER_BIT)

  g_vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  ############################################################

  drawMap(g_map, g_cursorX, g_cursorY, g_drawParams, g_vg)

  ############################################################

  koi.endFrame()
  g_vg.endFrame()

  glfw.swapBuffers(win)

# }}}

# {{{ GLFw callbacks
proc windowPosCb(win: Window, pos: tuple[x, y: int32]) =
  render(win)

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  render(win)

# }}}
# {{{ init()
proc init(): Window =
  glfw.initialize()

  var win = createWindow()

  var flags = {nifStencilStrokes, nifDebug}
  g_vg = nvgInit(getProcAddress, flags)
  if g_vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(g_vg)

  g_Map = newMap(32, 32)

  koi.init(g_vg)

  win.windowPositionCb = windowPosCb
  win.framebufferSizeCb = framebufSizeCb

  glfw.swapInterval(1)

  win.pos = (150, 150)  # TODO for development
  wrapper.showWindow(win.getHandle())

  result = win

# }}}
# {{{ cleanup()
proc cleanup() =
  koi.deinit()
  nvgDeinit(g_vg)
  glfw.terminate()

# }}}

type
  ActionProc = proc (m: var Map)

  UndoStateKind = enum
    uskRectAreaChange

  UndoState = object
    case kind: UndoStateKind
    of uskRectAreaChange:
      rectX, rectY: Natural
      map: Map
      # TODO skipGrid

var
  g_undoStates: seq[UndoState]
  g_undoPos: int
  g_redoActions: seq[ActionProc]


proc initUndo() =
  g_undoStates = @[]
  g_undoPos = -1
  g_redoActions = @[]


proc storeUndo(undoState: UndoState, redoAction: ActionProc) =
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

proc undo(m: var Map) =
  if canUndo():
    restoreUndoState(m, g_undoStates[g_undoPos])
    dec(g_undoPos)


proc canRedo(): bool = g_undoPos+1 <= g_redoActions.len-1

proc redo(m: var Map) =
  if canRedo():
    let redoAction = g_redoActions[g_undoPos+1]
    redoAction(m)
    inc(g_undoPos)


# {{{ setCursor()
proc setCursor(m: Map, x, y: Natural) =
  g_cursorX = min(x, m.width-1)
  g_cursorY = min(y, m.height-1)

# }}}
# {{{ moveCursor()
proc moveCursor(m: Map, dir: Direction) =
  case dir:
  of North:
    if g_cursorY > 0: setCursor(m, g_cursorX,   g_cursorY-1)
  of East:
    setCursor(m, g_cursorX+1, g_cursorY)
  of South:
    setCursor(m, g_cursorX,   g_cursorY+1)
  of West:
    if g_cursorX > 0: setCursor(m, g_cursorX-1, g_cursorY)

# }}}
# {{{ eraseCellWalls()
proc eraseCellWalls(m: var Map, x, y: Natural) =
  m.setWall(x,y, North, wNone)
  m.setWall(x,y, West,  wNone)
  m.setWall(x,y, South, wNone)
  m.setWall(x,y, East,  wNone)

# }}}
# {{{ eraseCellAction()
proc eraseCellAction(m: var Map, x, y: Natural) =
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
# {{{ setWallAction()
proc setWallAction(m: var Map, x, y: Natural, dir: Direction, w: Wall) =
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
# {{{ setFloorAction()
proc setFloorAction(m: var Map, x, y: Natural, f: Floor) =
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
# {{{ excavateAction()
proc excavateAction(m: var Map, x, y: Natural) =
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
# {{{ toggleFloorOrientationAction()
proc toggleFloorOrientationAction(m: var Map, x, y: Natural) =
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
# {{{ handleEvents()
proc handleEvents(win: Window) =
  if win.isKeyDown(keyEscape):  # TODO key buf, like char buf?
    win.shouldClose = true

  for ke in keyBuf():
    alias(curX, g_cursorX)
    alias(curY, g_cursorY)

    proc handleMoveKey(dir: Direction) =
#        if ke.mods == {mkShift}:
      if win.isKeyDown(keyW):
        let w = if g_map.getWall(curX, curY, dir) == wNone: wWall
                else: wNone
        setWallAction(g_map,curX, curY, dir, w)

      elif ke.mods == {mkAlt}:
        setWallAction(g_map,curX, curY, dir, wNone)
      elif ke.mods == {mkAlt, mkShift}:
        setWallAction(g_map,curX, curY, dir, wClosedDoor)
      else:
        g_map.moveCursor(dir)

    if ke.key in {keyLeft,  keyH, keyKp4}: handleMoveKey(West)
    if ke.key in {keyRight, keyL, keyKp6}: handleMoveKey(East)
    if ke.key in {keyUp,    keyK, keyKp8}: handleMoveKey(North)
    if ke.key in {keyDown,  keyJ, keyKp2}: handleMoveKey(South)

    if   win.isKeyDown(keyF): setFloor(g_map, curX, curY, fEmptyFloor)
    elif win.isKeyDown(key1): setFloor(g_map, curX, curY, fEmptyFloor)

    elif win.isKeyDown(key2):
      if g_map.getFloor(curX, curY) == fClosedDoor:
        toggleFloorOrientationAction(g_map, curX, curY)
      else:
        setFloorAction(g_map, curX, curY, fClosedDoor)

    elif win.isKeyDown(key3):
      if g_map.getFloor(curX, curY) == fOpenDoor:
        toggleFloorOrientationAction(g_map, curX, curY)
      else:
        setFloorAction(g_map, curX, curY, fOpenDoor)

    elif win.isKeyDown(key4):
      setFloorAction(g_map, curX, curY, fPressurePlate)

    elif win.isKeyDown(key5):
      setFloorAction(g_map, curX, curY, fHiddenPressurePlate)

    elif win.isKeyDown(key6):
      setFloorAction(g_map, curX, curY, fClosedPit)

    elif win.isKeyDown(key7):
      setFloorAction(g_map, curX, curY, fOpenPit)

    elif win.isKeyDown(key8):
      setFloorAction(g_map, curX, curY, fHiddenPit)

    elif win.isKeyDown(key9):
      setFloorAction(g_map, curX, curY, fCeilingPit)

    elif win.isKeyDown(key0):
      setFloorAction(g_map, curX, curY, fStairsDown)

    elif win.isKeyDown(keyF):
      setFloor(g_map, curX, curY, fEmptyFloor)

    elif win.isKeyDown(keyD):
      excavateAction(g_map, curX, curY)

    elif win.isKeyDown(keyE):
      eraseCellAction(g_map, curX, curY)

    elif win.isKeyDown(keyW) and ke.mods == {mkAlt}:
      g_map.eraseCellWalls(curX, curY)

  clearKeyBuf()

# }}}

# {{{ main()
proc main() =
  let win = init()

  while not win.shouldClose:
    handleEvents(win)
    render(win)
    glfw.pollEvents()

  cleanup()

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
