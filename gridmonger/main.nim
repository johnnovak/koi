import lenientops
import options

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg

import actions
import common
import drawmap
import map
import selection
import undomanager
import utils


# {{{ App context
type
  EditMode = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emEraseCell,
    emClearFloor,
    emSelectDraw,
    emSelectRect

  AppContext = ref object
    vg:          NVGContext
    win:         Window

    map:         Map
    cursorX:     Natural
    cursorY:     Natural

    editMode:    EditMode
    selection:   Option[Selection]
    selRect:     Option[SelectionRect]
    copyBuf:     Option[CopyBuffer]

    drawParams:  DrawParams

    undoManager: UndoManager[Map]


var g_app: AppContext

# }}}

using a: var AppContext

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

var g_textFieldVal1 = "Level 1"

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

  drawMap(
    g_app.map,
    g_app.cursorX, g_app.cursorY,
    g_app.selection,
    g_app.selRect,
    none(CopyBuffer),
    g_app.drawParams,
    vg
  )

  g_textFieldVal1 = koi.textField(
    winWidth-200.0, 30.0, 150.0, 24.0, tooltip = "Text field 1", g_textFieldVal1)

  ############################################################

  koi.endFrame()
  vg.endFrame()

  glfw.swapBuffers(win)

# }}}

# {{{ GLFW callbacks
proc windowPosCb(win: Window, pos: tuple[x, y: int32]) =
  render(win)

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  render(win)

# }}}
# {{{ initDrawParams*()
proc initDrawParams*(dp: var DrawParams) =
  dp.gridSize = 22.0

  dp.startX = 50.0
  dp.startY = 50.0

  dp.defaultFgColor  = gray(0.1)

  dp.gridColorBackground = gray(0.0, 0.3)
  dp.gridColorFloor      = gray(0.0, 0.2)

  dp.floorColor          = gray(0.9)

  dp.mapBackgroundColor  = gray(0.0, 0.7)
  dp.mapOutlineColor     = gray(0.23)
  dp.drawOutline         = false

  dp.cursorColor         = rgb(1.0, 0.65, 0.0)
  dp.cursorGuideColor    = rgba(1.0, 0.65, 0.0, 0.2)
  dp.drawCursorGuides    = false

  dp.selectionColor      = rgba(1.0, 0.5, 0.5, 0.5)

  dp.cellCoordsColor     = gray(0.9)
  dp.cellCoordsColorHi   = rgb(1.0, 0.75, 0.0)
  dp.cellCoordsFontSize  = 15.0

# }}}
# {{{ init()
proc init(): Window =
  g_app = new AppContext

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
  g_app.undoManager = newUndoManager[Map]()
  g_app.drawParams = new DrawParams
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
proc setCursor(x, y: Natural, a) =
  a.cursorX = min(x, a.map.width-1)
  a.cursorY = min(y, a.map.height-1)

# }}}
# {{{ moveCursor()
proc moveCursor(dir: Direction, a) =
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
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelectDraw
  a.selection = some(newSelection(a.map.width, a.map.height))
  a.drawParams.drawCursorGuides = true

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.editMode = emNormal
  a.drawParams.drawCursorGuides = false
  a.selection = none(Selection)

# }}}
# {{{ copySelection()
proc copySelection(a): Option[Rect[Natural]] =
  let sel = a.selection.get
  let bbox = sel.boundingBox()
  if bbox.isSome:
    a.copyBuf = some(CopyBuffer(
      selection: newSelectionFrom(a.selection.get, bbox.get),
      map: newMapFrom(a.map, bbox.get)
    ))
  result = bbox

# }}}
# {{{ isKeyDown()
func isKeyDown(ke: KeyEvent, keys: set[Key],
               mods: set[ModifierKey] = {}, repeat=false): bool =
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  ke.action in a and ke.key in keys and ke.mods == mods

func isKeyDown(ke: KeyEvent, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ke, {key}, mods, repeat)

func isKeyUp(ke: KeyEvent, keys: set[Key]): bool =
  ke.action == kaUp and ke.key in keys

# }}}
# {{{ handleEvents()
proc handleEvents(a) =
  alias(curX, a.cursorX)
  alias(curY, a.cursorY)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(win, a.win)

  const
    MoveKeysLeft  = {keyLeft,  keyH, keyKp4}
    MoveKeysRight = {keyRight, keyL, keyKp6}
    MoveKeysUp    = {keyUp,    keyK, keyKp8}
    MoveKeysDown  = {keyDown,  keyJ, keyKp2}

  for ke in keyBuf():
    case a.editMode:
    of emNormal:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      if ke.isKeyDown(keyD):
        a.editMode = emExcavate
        excavateAction(m, curX, curY, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        eraseCellAction(m, curX, curY, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearFloor
        setFloorAction(m, curX, curY, fEmptyFloor, um)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall

      elif ke.isKeyDown(keyW) and ke.mods == {mkAlt}:
        eraseCellWallsAction(m, curX, curY, um)

      elif ke.isKeyDown(key1):
        if m.getFloor(curX, curY) == fClosedDoor:
          toggleFloorOrientationAction(m, curX, curY, um)
        else:
          setFloorAction(m, curX, curY, fClosedDoor, um)

      elif ke.isKeyDown(key2):
        if m.getFloor(curX, curY) == fOpenDoor:
          toggleFloorOrientationAction(m, curX, curY, um)
        else:
          setFloorAction(m, curX, curY, fOpenDoor, um)

      elif ke.isKeyDown(key3):
        setFloorAction(m, curX, curY, fPressurePlate, um)

      elif ke.isKeyDown(key4):
        setFloorAction(m, curX, curY, fHiddenPressurePlate, um)

      elif ke.isKeyDown(key5):
        setFloorAction(m, curX, curY, fClosedPit, um)

      elif ke.isKeyDown(key6):
        setFloorAction(m, curX, curY, fOpenPit, um)

      elif ke.isKeyDown(key7):
        setFloorAction(m, curX, curY, fHiddenPit, um)

      elif ke.isKeyDown(key8):
        setFloorAction(m, curX, curY, fCeilingPit, um)

      elif ke.isKeyDown(key9):
        setFloorAction(m, curX, curY, fStairsDown, um)

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true):
        um.undo(m)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        um.redo(m)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if a.copyBuf.isSome:
          pasteAction(m, curX, curY, a.copyBuf.get, um)

    of emExcavate, emEraseCell, emClearFloor:
      proc handleMoveKey(dir: Direction, a) =
        if a.editMode == emExcavate:
          moveCursor(dir, a)
          excavateAction(m, curX, curY, um)

        elif a.editMode == emEraseCell:
          moveCursor(dir, a)
          eraseCellAction(m, curX, curY, um)

        elif a.editMode == emClearFloor:
          moveCursor(dir, a)
          setFloorAction(m, curX, curY, fEmptyFloor, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(South, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        a.editMode = emNormal

    of emDrawWall:
      proc handleMoveKey(dir: Direction, a) =
        let w = if m.getWall(curX, curY, dir) == wNone: wWall
                else: wNone
        setWallAction(m, curX, curY, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(South, a)

      elif ke.isKeyUp({keyW}):
        a.editMode = emNormal

    of emSelectDraw:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      if   win.isKeyDown(keyD): a.selection.get[curX, curY] = true
      elif win.isKeyDown(keyE): a.selection.get[curX, curY] = false

      if   ke.isKeyDown(keyA, {mkCtrl}): a.selection.get.fill(true)
      elif ke.isKeyDown(keyD, {mkCtrl}): a.selection.get.fill(false)
      elif ke.isKeyDown(keyC): discard
      elif ke.isKeyDown(keyX): discard

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          x0: curX, y0: curY,
          rect: rectN(curX, curY, curX+1, curY+1),
          fillValue: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC):
        discard copySelection(a)
        exitSelectMode(a)

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          eraseSelectionAction(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)

    of emSelectRect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      var x1, y1, x2, y2: Natural
      if a.selRect.get.x0 <= curX:
        x1 = a.selRect.get.x0
        x2 = curX+1
      else:
        x1 = curX
        x2 = a.selRect.get.x0 + 1

      if a.selRect.get.y0 <= curY:
        y1 = a.selRect.get.y0
        y2 = curY+1
      else:
        y1 = curY
        y2 = a.selRect.get.y0 + 1

      a.selRect.get.rect = rectN(x1, y1, x2, y2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.fillValue)
        a.selRect = none(SelectionRect)
        a.editMode = emSelectDraw

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