import strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg

import actions
import common
import drawmap
import map
import undomanager
import utils


# {{{ App context
type
  AppContext = object
    vg:          NVGContext
    win:         Window

    map:         Map
    drawParams:  DrawParams
    cursorX:     Natural
    cursorY:     Natural

    undoManager: UndoManager[Map]


var g_app: AppContext

# }}}

# {{{ createWindow()
proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 800, h: 800)
  cfg.title = "GridMonger v0.1 alpha"
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
  alias(vg, g_app.vg)

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

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  ############################################################

  drawMap(g_app.map, g_app.cursorX, g_app.cursorY, g_app.drawParams, vg)

  ############################################################

  koi.endFrame()
  vg.endFrame()

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
  g_app.win = win

  var flags = {nifStencilStrokes, nifDebug}
  g_app.vg = nvgInit(getProcAddress, flags)
  if g_app.vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(g_app.vg)

  g_app.map = newMap(24, 32)

  initUndoManager(g_app.undoManager)
  initDrawParams(g_app.drawParams)

  koi.init(g_app.vg)

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
  nvgDeinit(g_app.vg)
  glfw.terminate()

# }}}

# {{{ setCursor()
proc setCursor(x, y: Natural, a: var AppContext) =
  a.cursorX = min(x, a.map.width-1)
  a.cursorY = min(y, a.map.height-1)

# }}}
# {{{ moveCursor()
proc moveCursor(dir: Direction, a: var AppContext) =
  let x = a.cursorX
  let y = a.cursory

  case dir:
  of North:
    if y > 0: setCursor(x, y-1, a)
  of East:
    setCursor(x+1, y, a)
  of South:
    setCursor(x, y+1, a)
  of West:
    if x > 0: setCursor(x-1, y, a)

# }}}
# {{{ handleEvents()
proc handleEvents(a: var AppContext) =
  alias(curX, a.cursorX)
  alias(curY, a.cursorY)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(win, a.win)

  if win.isKeyDown(keyEscape):  # TODO key buf, like char buf?
    win.shouldClose = true

  for ke in keyBuf():

    proc handleMoveKey(dir: Direction, a: var AppContext) =
#        if ke.mods == {mkShift}:
      if win.isKeyDown(keyW):
        let w = if m.getWall(curX, curY, dir) == wNone: wWall
                else: wNone
        setWallAction(m, curX, curY, dir, w, um)

      elif ke.mods == {mkAlt}:
        setWallAction(m, curX, curY, dir, wNone, um)
      elif ke.mods == {mkAlt, mkShift}:
        setWallAction(m, curX, curY, dir, wClosedDoor, um)
      else:
        moveCursor(dir, a)

    if ke.key in {keyLeft,  keyH, keyKp4}: handleMoveKey(West, a)
    if ke.key in {keyRight, keyL, keyKp6}: handleMoveKey(East, a)
    if ke.key in {keyUp,    keyK, keyKp8}: handleMoveKey(North, a)
    if ke.key in {keyDown,  keyJ, keyKp2}: handleMoveKey(South, a)

    if   win.isKeyDown(keyF): setFloorAction(m, curX, curY, fEmptyFloor, um)
    elif win.isKeyDown(key1): setFloorAction(m, curX, curY, fEmptyFloor, um)

    elif win.isKeyDown(key2):
      if m.getFloor(curX, curY) == fClosedDoor:
        toggleFloorOrientationAction(m, curX, curY, um)
      else:
        setFloorAction(m, curX, curY, fClosedDoor, um)

    elif win.isKeyDown(key3):
      if m.getFloor(curX, curY) == fOpenDoor:
        toggleFloorOrientationAction(m, curX, curY, um)
      else:
        setFloorAction(m, curX, curY, fOpenDoor, um)

    elif win.isKeyDown(key4):
      setFloorAction(m, curX, curY, fPressurePlate, um)

    elif win.isKeyDown(key5):
      setFloorAction(m, curX, curY, fHiddenPressurePlate, um)

    elif win.isKeyDown(key6):
      setFloorAction(m, curX, curY, fClosedPit, um)

    elif win.isKeyDown(key7):
      setFloorAction(m, curX, curY, fOpenPit, um)

    elif win.isKeyDown(key8):
      setFloorAction(m, curX, curY, fHiddenPit, um)

    elif win.isKeyDown(key9):
      setFloorAction(m, curX, curY, fCeilingPit, um)

    elif win.isKeyDown(key0):
      setFloorAction(m, curX, curY, fStairsDown, um)

    elif win.isKeyDown(keyF):
      setFloorAction(m, curX, curY, fEmptyFloor, um)

    elif win.isKeyDown(keyD):
      excavateAction(m, curX, curY, um)

    elif win.isKeyDown(keyE):
      eraseCellAction(m, curX, curY, um)

    elif win.isKeyDown(keyW) and ke.mods == {mkAlt}:
      eraseCellWallsAction(m, curX, curY, um)

    elif win.isKeyDown(keyZ) and ke.mods == {mkCtrl}:
      um.undo(m)

    elif win.isKeyDown(keyY) and ke.mods == {mkCtrl}:
      um.redo(m)

  clearKeyBuf()

# }}}

# {{{ main()
proc main() =
  let win = init()

  while not win.shouldClose:
    handleEvents(g_app)
    render(win)
    glfw.pollEvents()

  cleanup()

# }}}

main()


# vim: et:ts=2:sw=2:fdm=marker
