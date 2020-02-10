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


# {{{ Globals
var
  g_vg: NVGContext

  g_map: Map
  g_cursorX: Natural
  g_cursorY: Natural
  g_undoManager: UndoManager[Map]

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

  g_map = newMap(32, 32)
  initUndoManager(g_undoManager)

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
# {{{ handleEvents()
proc handleEvents(win: Window) =
  if win.isKeyDown(keyEscape):  # TODO key buf, like char buf?
    win.shouldClose = true

  for ke in keyBuf():
    alias(curX, g_cursorX)
    alias(curY, g_cursorY)
    alias(um, g_undoManager)

    proc handleMoveKey(dir: Direction) =
#        if ke.mods == {mkShift}:
      if win.isKeyDown(keyW):
        let w = if g_map.getWall(curX, curY, dir) == wNone: wWall
                else: wNone
        setWallAction(g_map,curX, curY, dir, w, um)

      elif ke.mods == {mkAlt}:
        setWallAction(g_map,curX, curY, dir, wNone, um)
      elif ke.mods == {mkAlt, mkShift}:
        setWallAction(g_map,curX, curY, dir, wClosedDoor, um)
      else:
        g_map.moveCursor(dir)

    if ke.key in {keyLeft,  keyH, keyKp4}: handleMoveKey(West)
    if ke.key in {keyRight, keyL, keyKp6}: handleMoveKey(East)
    if ke.key in {keyUp,    keyK, keyKp8}: handleMoveKey(North)
    if ke.key in {keyDown,  keyJ, keyKp2}: handleMoveKey(South)

    if   win.isKeyDown(keyF): setFloorAction(g_map, curX, curY, fEmptyFloor, um)
    elif win.isKeyDown(key1): setFloorAction(g_map, curX, curY, fEmptyFloor, um)

    elif win.isKeyDown(key2):
      if g_map.getFloor(curX, curY) == fClosedDoor:
        toggleFloorOrientationAction(g_map, curX, curY, um)
      else:
        setFloorAction(g_map, curX, curY, fClosedDoor, um)

    elif win.isKeyDown(key3):
      if g_map.getFloor(curX, curY) == fOpenDoor:
        toggleFloorOrientationAction(g_map, curX, curY, um)
      else:
        setFloorAction(g_map, curX, curY, fOpenDoor, um)

    elif win.isKeyDown(key4):
      setFloorAction(g_map, curX, curY, fPressurePlate, um)

    elif win.isKeyDown(key5):
      setFloorAction(g_map, curX, curY, fHiddenPressurePlate, um)

    elif win.isKeyDown(key6):
      setFloorAction(g_map, curX, curY, fClosedPit, um)

    elif win.isKeyDown(key7):
      setFloorAction(g_map, curX, curY, fOpenPit, um)

    elif win.isKeyDown(key8):
      setFloorAction(g_map, curX, curY, fHiddenPit, um)

    elif win.isKeyDown(key9):
      setFloorAction(g_map, curX, curY, fCeilingPit, um)

    elif win.isKeyDown(key0):
      setFloorAction(g_map, curX, curY, fStairsDown, um)

    elif win.isKeyDown(keyF):
      setFloorAction(g_map, curX, curY, fEmptyFloor, um)

    elif win.isKeyDown(keyD):
      excavateAction(g_map, curX, curY, um)

    elif win.isKeyDown(keyE):
      eraseCellAction(g_map, curX, curY, um)

    elif win.isKeyDown(keyW) and ke.mods == {mkAlt}:
      eraseCellWallsAction(g_map, curX, curY, um)

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
