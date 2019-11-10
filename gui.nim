import os, strformat

import glad/gl
import glfw
import nanovg

type TooltipState = enum
  tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

const
  TooltipShowDelay       = 0.5
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 0.3

type DragMode = enum
  dmOff, dmNormal, dmFine

type UIState = object
  # Mouse state
  mx:             float
  my:             float
  mbLeftDown:     bool
  mbRightDown:    bool
  mbMidDown:      bool

  # Keyboard
  shiftDown:      bool
  altDown:        bool
  ctrlDown:       bool
  superDown:      bool

  # Active & hot items
  hotItem:        int
  activeItem:     int
  prevHotItem:    int
  prevActiveItem: int

  # Internal state for slider types
  x0:       float
  y0:       float
  dragMode: DragMode
  dragX:    float
  sliderStep: bool

  # Internal state for tooltips
  tooltipState:     TooltipState
  lastTooltipState: TooltipState
  tooltipT0:        float
  tooltipText:      string


var gui: UIState

let RED = rgb(1.0, 0.4, 0.4)


proc disableCursor() = glfw.currentContext().cursorMode = cmDisabled
proc enableCursor()  = glfw.currentContext().cursorMode = cmNormal


proc mouseButtonCb(win: Window, button: MouseButton, pressed: bool,
                   modKeys: set[ModifierKey]) =

  case button
  of mb1: gui.mbLeftDown  = pressed
  of mb2: gui.mbRightDown = pressed
  of mb3: gui.mbMidDown   = pressed
  else: discard


proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           modKeys: set[ModifierKey]) =

  if action == kaDown:
    case key
    of keyEscape: win.shouldClose = true

    of keyLeftShift,   keyRightShift:   gui.shiftDown = true
    of keyLeftControl, keyRightControl: gui.ctrlDown  = true
    of keyLeftAlt,     keyRightAlt:     gui.altDown   = true
    of keyLeftSuper,   keyRightSuper:   gui.superDown = true
    else: discard

  elif action == kaUp:
    case key
    of keyLeftShift,   keyRightShift:   gui.shiftDown = false
    of keyLeftControl, keyRightControl: gui.ctrlDown  = false
    of keyLeftAlt,     keyRightAlt:     gui.altDown   = false
    of keyLeftSuper,   keyRightSuper:   gui.superDown = false
    else: discard


proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 1000, h: 800)
  cfg.title = "uiState test"
  cfg.resizable = true
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = true
  cfg.nMultiSamples = 4

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  newWindow(cfg)


proc mouseInside(x, y, w, h: float): bool =
  gui.mx >= x and gui.mx <= x+w and
  gui.my >= y and gui.my <= y+h


proc drawToolTip(vg: NVGContext, x, y: float, text: string,
                 alpha: float = 1.0) =
  let
    w = 150.0
    h = 40.0

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(gray(0.1, 0.88 * alpha))
  vg.fill()

  vg.fontSize(17.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(white(0.9 * alpha))
  discard vg.text(x + 10, y + 10, text)


proc uiStatePre() =
  gui.hotItem = 0

proc uiStatePost(vg: NVGContext) =
  # Tooltip handling
  let
    ttx = gui.mx + 13
    tty = gui.my + 20

  case gui.tooltipState:
  of tsOff: discard
  of tsShowDelay:
    if getTime() - gui.tooltipT0 > TooltipShowDelay:
      gui.tooltipState = tsShow

  of tsShow:
    drawToolTip(vg, ttx, tty, gui.tooltipText)

  of tsFadeOutDelay:
    drawToolTip(vg, ttx, tty, gui.tooltipText)
    if getTime() - gui.tooltipT0 > TooltipFadeOutDelay:
      gui.tooltipState = tsFadeOut
      gui.tooltipT0 = getTime()

  of tsFadeOut:
    let t = getTime() - gui.tooltipT0
    if t > TooltipFadeOutDuration:
      gui.tooltipState = tsOff
    else:
      let alpha = 1.0 - t / TooltipFadeOutDuration
      drawToolTip(vg, ttx, tty, gui.tooltipText, alpha)

  gui.lastTooltipState = gui.tooltipState

  # We reset the show delay state or move into the fade out state if the
  # tooltip was shown to handle the case when the user just moved the cursor
  # outside of a widget. The actual widgets are responsible to "keep alive"
  # the state every frame by restoring the tooltip state from lastTooltipState
  if gui.lastTooltipState == tsShowDelay:
    gui.tooltipState = tsOff
  elif gui.lastTooltipState == tsShow:
    gui.tooltipState = tsFadeOutDelay
    gui.tooltipT0 = getTime()


  gui.prevHotItem = gui.hotItem
  gui.prevActiveItem = gui.activeItem

  if gui.mbLeftDown:
    if gui.activeItem == 0 and gui.hotItem == 0:
      # Mouse button was pressed outside of any widget. We need to mark this
      # as a separate state so we can't just "drag into" a widget while the
      # button is being depressed and activate it.
      gui.activeItem = -1
  else:
    # If the button was released inside the active widget, that has already
    # been handled at this point--we're just clearing the active item here.
    # This also takes care of the case when the button was depressed inside
    # the widget but released outside of it.
    gui.activeItem = 0

    gui.sliderStep = false

    # Disable drag mode and reset the cursor if the left mouse button was
    # released while in fine drag mode.
    case gui.dragMode:
    of dmOff: discard
    of dmNormal:
      gui.dragMode = dmOff

    of dmFine:
      gui.dragMode = dmOff
      enableCursor()
      let win = glfw.currentContext()
      let (x, y) = win.cursorPos()
      win.cursorPos = (gui.dragX, y)


proc handleTooltipInsideWidget(id: int, tooltipText: string) =
  gui.tooltipState = gui.lastTooltipState

  if gui.mbLeftDown and gui.activeItem > 0:
    gui.tooltipState = tsOff

  elif gui.tooltipState == tsOff and not gui.mbLeftDown and
       gui.prevHotItem != id:
    gui.tooltipState = tsShowDelay
    gui.tooltipT0 = getTime()

  elif gui.tooltipState >= tsShow:
    gui.tooltipState = tsShow
    gui.tooltipT0 = getTime()
    gui.tooltipText = tooltipText


proc renderLabel(vg: NVGContext, id: int, x, y, w, h: float, label: string,
                 color: Color,
                 fontSize: float = 19.0, fontFace = "sans-bold") =

  vg.fontSize(fontSize)
  vg.fontFace(fontFace)
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(color)
#  let tw = vg.horizontalAdvance(0,0, label)
  discard vg.text(x, y+h*0.5, label)


proc renderButton(vg: NVGContext, id: int, x, y, w, h: float, label: string,
                  color: Color, tooltipText: string = ""): bool =

  # Hit testing
  let inside = mouseInside(x, y, w, h)
  if inside:
    gui.hotItem = id
    if gui.activeItem == 0 and gui.mbLeftDown:
      gui.activeItem = id

  if not gui.mbLeftDown and gui.hotItem == id and gui.activeItem == id:
    result = true

  # Draw button
  let fillColor = if gui.hotItem == id:
    if gui.activeItem == id: RED
    elif gui.activeItem <= 0: gray(0.8)
    else: color
  else:
    color

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(black(0.7))
  let tw = vg.horizontalAdvance(0,0, label)
  discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, label)

  if inside:
    handleTooltipInsideWidget(id, tooltipText)


proc renderHorizSlider(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                       minVal: float = 0.0, maxVal: float = 1.0,
                       size: float = -1.0, step: float = -1.0,
                       tooltipText: string = ""): float =

  assert minVal < maxVal
  assert value >= minVal
  assert value <= maxVal
  assert size < 0.0 or size < (maxVal - minVal)
  assert step < 0.0 or step < (maxVal - minVal)

  const
    KnobPad = 3
    KnobMinW = 10

  # Calculate current knob position
  let
    windowSize = if size < 0: 0.000001 else: size
    knobW = max((w - KnobPad*2) / ((maxVal - minVal) / windowSize), KnobMinW)
    knobH = h - KnobPad * 2
    knobMinX = x + KnobPad
    knobMaxX = x + w - KnobPad - knobW

  proc calcKnobX(val: float): float =
    knobMinX + (knobMaxX - knobMinX) * (val / (maxVal - minVal))

  let knobX = calcKnobX(value)

  # Hit testing
  let (insideSlider, insideKnob) =
    if gui.dragMode == dmFine and gui.activeItem == id:
      (true, true)
    else:
      (mouseInside(x, y, w, h), mouseInside(knobX, y, knobW, h))

  if insideSlider:
    gui.hotItem = id

  var sliderClicked = 0.0

  if gui.mbLeftDown and gui.activeItem == 0:
    if insideKnob:
      # Active item is only set if the knob is being dragged
      gui.activeItem = id
      gui.x0 = gui.mx
      if gui.shiftDown:
        gui.dragMode = dmFine
        disableCursor()
      else:
        gui.dragMode = dmNormal

    elif insideSlider and not insideKnob and not gui.sliderStep:
      if gui.mx < knobX: sliderClicked = -1.0
      else:              sliderClicked =  1.0
      gui.sliderStep = true

  # New knob position & value calculation...
  var
    newKnobX = knobX
    newValue = value

  # ...when the slider was clicked outside of the knob
  if sliderClicked != 0:
    let stepSize = if step < 0: (maxVal - minVal) * 0.1 else: step
    newValue = min(max(newValue + sliderClicked * stepSize, minVal), maxVal)
    newKnobX = calcKnobX(newValue)

  # ...when dragging slider
  elif gui.activeItem == id:
    if gui.shiftDown and gui.dragMode == dmNormal:
      gui.dragMode = dmFine
      disableCursor()

    elif not gui.shiftDown and gui.dragMode == dmFine:
      gui.dragMode = dmNormal
      enableCursor()

      let win = glfw.currentContext()
      let (x, y) = win.cursorPos()
      gui.mx = gui.dragX
      gui.x0 = gui.dragX
      win.cursorPos = (gui.dragX, y)

    var dx = gui.mx - gui.x0
    if gui.dragMode == dmFine:
      dx /= 8
      if gui.altDown: dx /= 8

    newKnobX = min(max(knobX + dx, knobMinX), knobMaxX)

    newValue = (newKnobX - knobMinX) / (knobMaxX - knobMinX) *
               (maxVal - minVal)

    gui.x0 = if gui.dragMode == dmFine:
      gui.mx
    else:
      min(max(gui.mx, knobMinX), knobMaxX + knobW)

    gui.dragX = newKnobX + knobW/2


  result = newValue

  # Draw slider
  let fillColor = if gui.hotItem == id and not insideKnob:
    if gui.activeItem <= 0: gray(0.8)
    else: gray(0.60)
  else: gray(0.60)

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw knob
  let knobColor = if gui.activeItem == id: RED
  elif insideKnob and gui.activeItem <= 0: gray(0.35)
  else: gray(0.25)

  vg.beginPath()
  vg.roundedRect(newKnobX, y + KnobPad, knobW, knobH, 5)
  vg.fillColor(knobColor)
  vg.fill()

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(white())
  let valueString = fmt"{newValue:.3f}"
  let tw = vg.horizontalAdvance(0,0, valueString)
  discard vg.text(x + w/2 - tw/2, y+h*0.5, valueString)

  if insideSlider:
    handleTooltipInsideWidget(id, tooltipText)

    if gui.sliderStep:
      gui.tooltipState = tsOff


proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add font italic.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add font italic.\n"


proc main() =
  glfw.initialize()

  var win = createWindow()
  win.mouseButtonCb = mouseButtonCb
  win.keyCb = keyCb
  win.pos = (400, 150)  # TODO for development

  glfw.makeContextCurrent(win)

  var flags = {nifStencilStrokes, nifDebug}
  var vg = nvgInit(getProcAddress, flags)
  if vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(vg)

  glfw.swapInterval(1)

  ### UI DATA ################################################
  var sliderVal1 = 50.0
  var sliderVal2 = 0.0

  ############################################################

  while not win.shouldClose:
    var
      (winWidth, winHeight) = win.size
      (fbWidth, fbHeight) = win.framebufferSize
      pxRatio = fbWidth / winWidth

    # Update and render
    glViewport(0, 0, fbWidth, fbHeight)

    glClearColor(0.3, 0.3, 0.3, 1.0)

    glClear(GL_COLOR_BUFFER_BIT or
            GL_DEPTH_BUFFER_BIT or
            GL_STENCIL_BUFFER_BIT)

    vg.beginFrame(winWidth.float, winHeight.float, pxRatio)

    uiStatePre()
    (gui.mx, gui.my) = win.cursorPos()

    ############################################################
    let
      w = 110.0
      h = 22.0
      pad = h + 8
    var
      x = 100.0
      y = 50.0

    renderLabel(vg, 1, x + 5, y, w, h, "Test buttons", color = gray(0.90),
                fontSize = 22.0)
    y += pad
    if renderButton(vg, 2, x, y, w, h, "Start", color = gray(0.60), "I am the first!"):
      echo "button 1 pressed"

    y += pad
    if renderButton(vg, 3, x, y, w, h, "Stop", color = gray(0.60), "Middle one..."):
      echo "button 2 pressed"

    y += pad
    if renderButton(vg, 4, x, y, w, h, "Preferences", color = gray(0.60), "Last button"):
      echo "button 3 pressed"

    y += pad
    sliderVal1 = renderHorizSlider(
      vg, 5, x, y, w * 1.5, h, sliderVal1,
      minVal = 0.0, maxVal = 100.0, size = 20.0, step = 10.0,
      tooltipText = "Slider 1")

    y += pad
    sliderVal2 = renderHorizSlider(
      vg, 6, x, y, w * 1.5, h, sliderVal2,
      minVal = 0.0, maxVal = 1.0, size = -1.0, step = -1.0,
      tooltipText = "Slider 2")
    ############################################################

    uiStatePost(vg)

    vg.endFrame()

    glfw.swapBuffers(win)
    glfw.pollEvents()


  nvgDeinit(vg)

  glfw.terminate()


main()
