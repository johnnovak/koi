import lenientops
import strformat
import unicode

import glad/gl
import glfw
from glfw/wrapper import showWindow
import nanovg

import koi


# Global NanoVG context
var vg: NVGContext


### UI DATA ################################################

type Fruits = enum
  Orange    = (0, "Orange"),
  Banana    = (1, "Banana"),
  Blueberry = (2, "Blueberry"),
  Apricot   = (3, "Apricot"),
  Apple     = (4, "Apple")

var
  scrollBarVal1 = 30.0
  scrollBarVal2 = 0.0
  scrollBarVal3 = 50.0
  scrollBarVal4 = 0.0
  scrollBarVal5 = 50.0

  sliderVal1 = 50.0
  sliderVal2 = -20.0
  sliderVal3 = 30.0
  sliderVal4 = -20.0

  checkBoxVal1 = true
  checkBoxVal2 = false

  radioButtonsVal1 = 1
  radioButtonsVal2 = 2
  radioButtonsVal3 = 1
  radioButtonsVal4 = 1
  radioButtonsVal5 = 1
  radioButtonsVal6 = 1
  radioButtonsVal7 = 1

  dropDownVal1 = Fruits(0)
  dropDownVal2 = 0
  dropDownVal3 = 3
  dropDownTopRight = 0
  dropDownBottomLeft = 0
  dropDownBottomRight = 0

#  textFieldVal1 = ""
#  textFieldVal2 = "Nobody expects the Spanish Inquisition!"
#  textFieldVal3 = "Raw text field"
#
  textFieldVal1 = "Some text"
  textFieldVal2 = "Look behind—you! A three-headed monkey!"
  textFieldVal3 = "42"

  textAreaVal1 = "A merry little surge of electricity piped by automatic alarm from the mood organ beside his bed awakened Rick Deckard. Surprised—it always surprised him to find himself awake without prior notice—he rose from the bed, stood up in his multicolored pajamas, and stretched.\n\nNow, in her bed, his wife Iran opened her gray, unmerry eyes, blinked, then groaned and shut her eyes again.     A merry little surge of electricity piped by automatic alarm from the mood organ beside his bed awakened Rick Deckard. Surprised—it always surprised him to find himself awake without prior notice—he rose from the bed, stood up in his multicolored pajamas, and stretched.\n\nNow, in her bed, his wife Iran opened her gray, unmerry eyes, blinked, then groaned and shut her eyes again."

############################################################

proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 1000, h: 800)
  cfg.title = "Koi Test"
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


proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add font italic.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add font italic.\n"


proc renderUI(winWidth, winHeight, pxRatio: float) =
  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  let
    w = 110.0
    h = 22.0
    pad = h + 8
  var
    x = 100.0
    y = 70.0

  var labelStyle = getDefaultLabelStyle()
  labelStyle.fontSize = 15.0
  labelStyle.color = gray(0.8)

#  vg.scissor(0, 0, 630, 100)

  koi.label(x, y, 200, h, "Koi widget tests", style = labelStyle)

  # Buttons
  y += pad
  if koi.button(x, y, w, h, "Start", tooltip = "I am the first!"):
    echo "button 1 pressed"

  y += pad
  if koi.button(x, y, w, h, "Stop (very long text)", tooltip = "Middle one..."):
    echo "button 2 pressed"

  y += pad
  if koi.button(x, y, w, h, "Disabled", tooltip = "This is a disabled button",
                disabled = true):
    echo "button 3 pressed"

  # ScrollBars

  y += pad * 2
  koi.horizScrollBar(
    x, y, w * 1.5, h,
    startVal = 0, endVal = 100,
    scrollBarVal1,
    tooltip = "Horizontal ScrollBar 1",
    thumbSize = 20, clickStep = 10.0)

  y += pad
  koi.horizScrollBar(
    x, y, w * 1.5, h ,
    startVal = 0, endVal = 1,
    scrollBarVal2,
    tooltip = "Horizontal ScrollBar 2",
    thumbSize = -1, clickStep = -1)

  koi.vertScrollBar(
    320, 60, h, 140,
    startVal = 0.0, endVal = 100,
    scrollBarVal3,
    tooltip = "Vertical ScrollBar 1",
    thumbSize = 20, clickStep = 10)

  koi.vertScrollBar(
    350, 60, h, 140,
    startVal = 1, endVal = 0,
    scrollBarVal4,
    tooltip = "Vertical ScrollBar 2",
    thumbSize = -1, clickStep = -1)

  y += pad
  koi.horizScrollBar(
    x, y, w * 1.5, h,
    startVal = 100, endVal = 0,
    scrollBarVal5,
    tooltip = "Horizontal ScrollBar 3",
    thumbSize = 20, clickStep = 10.0)

  # Sliders

  y += pad * 2
  koi.horizSlider(
    x, y, w * 1.5, h,
    startVal = 0, endVal = 100,
    sliderVal1,
    tooltip = "Horizontal Slider 1")

  y += pad
  koi.horizSlider(
    x, y, w * 1.5, h,
    startVal = 50, endVal = -30,
    sliderVal2,
    tooltip = "Horizontal Slider 2")

  koi.vertSlider(
    320, 460, h, 120,
    startVal = 0, endVal = 100,
    sliderVal3,
    tooltip = "Vertical Slider 1")

  koi.label(300, 590, w, h, fmt"{sliderVal3:.3f}", style = labelStyle)

  koi.vertSlider(
    400, 460, h, 120,
    startVal = 50, endVal = -30,
    sliderVal4,
    tooltip = "Vertical Slider 2")

  koi.label(380, 590, w, h, fmt"{sliderVal4:.3f}", style = labelStyle)

  # dropDowns
  y += pad * 2
  koi.dropDown(
    x, y, w, h,
    Fruits,
    dropDownVal1,
    tooltip = "Select a fruit")

  koi.dropDown(
    280, y, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropDownVal2,
    tooltip = "Select a colour")

  koi.dropDown(
    430, y, w, h,
    items = @["This", "dropDown", "Is", "Disabled"],
    dropDownVal3,
    tooltip = "Disabled dropDown",
    disabled = true)

  koi.dropDown(
    winWidth.float - (w+10), 20, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropDownTopRight,
    tooltip = textAreaVal1)

  koi.dropDown(
    winWidth.float - (w+10), winHeight.float - 40, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropDownBottomRight,
    tooltip = textAreaVal1)

  koi.dropDown(
    10, winHeight.float - 40, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropDownBottomLeft,
    tooltip = textAreaVal1)

  # Text fields
  y += pad * 2
  koi.textField(
    x, y, w * 1.0, h, textFieldVal1, tooltip = "Text field 1")

  y += pad
  koi.textField(
    x, y, w * 1.5, h, textFieldVal2, tooltip = "Text field 2")

  y += pad
  koi.rawTextField(
    x, y, w * 1.0, h, textFieldVal3, tooltip = "Text field 3")

  # Checkboxes
  y += pad * 2
  koi.checkBox(
    x, y, h, checkBoxVal1, tooltip = "CheckBox 1")

  koi.checkBox(
    x + 30, y, h, checkBoxVal2, tooltip = "CheckBox 2")

  # Radio buttons (horiz)
  y += pad * 2
  koi.radioButtons(
    x, y, 150, h+2,
    labels = @["PNG", "JPG", "OpenEXR"],
    radioButtonsVal1,
    tooltips = @["Save PNG image", "Save JPG image", "Save EXR image"])

  y += pad
  koi.radioButtons(
    x, y, 220, h+2,
    labels = @["One", "Two", "The Third Option"],
    radioButtonsVal2,
    tooltips = @["First (1)", "Second (2)", "Third (3)"])

  # Custom drawn radio buttons
  var radioButtonsDrawProc: RadioButtonsDrawProc =
    proc (vg: NVGContext, buttonIdx: Natural, label: string,
          state: WidgetState, first, last: bool,
          x, y, w, h: float, style: RadioButtonsStyle) =

      var col = hsl(0.08 * buttonIdx, 0.6, 0.5)

      if state in {wsHover, wsActiveHover}:
        col = col.lerp(white(), 0.3)
      if state == wsDown:
        col = col.lerp(black(), 0.3)

      const Pad = 4

      vg.beginPath()
      vg.fillColor(col)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.fill()

      vg.fillColor(black(0.7))
      vg.setFont(14.0, horizAlign=haCenter)
      discard vg.text(x + (w-Pad)*0.5, y + h*0.5, label)

      if state in {wsActive, wsActiveHover}:
        vg.strokeColor(rgb(1.0, 0.4, 0.4))
        vg.strokeWidth(2)
        vg.stroke()

  koi.radioButtons(
    500, 100, 150, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal3,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    drawProc=radioButtonsDrawProc.some
  )

  koi.radioButtons(
    500, 160, 30, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal4,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc=radioButtonsDrawProc.some
  )

  koi.radioButtons(
    500, 220, 30, 30,
    labels = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B"],
    radioButtonsVal5,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc=radioButtonsDrawProc.some
  )

  # Radio buttons (vert)
  koi.radioButtons(
    700, 100, 30, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal6,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 4),
    drawProc=radioButtonsDrawProc.some
  )

  koi.radioButtons(
    770, 100, 30, 30,
    labels = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B",],
    radioButtonsVal7,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 4),
    drawProc=radioButtonsDrawProc.some
  )


  koi.textArea(
    650, 300, 300, 225, textAreaVal1, tooltip = "Text area 1")

  # Menu

  x = 70.0
  y = 20.0

#[
  case menuBar(x, y, 500, h, names = @["File", "Edit", "Help"]):
  of "File":
    if menuParentItem("&New", some(mkKeyEvent(keyN, {mkSuper}))):
      if menuItem("&General"):       echo "File -> New -> General"
      if menuItem("2&D Animation"):  echo "File -> New -> 2D Animation"
      if menuItem("&Sculpting"):     echo "File -> New -> Sculpting"
      if menuItem("&VFX"):           echo "File -> New -> VFX"
      if menuItem("Video &Editing"): echo "File -> New -> Video Editing"

    if menuItem("&Open...", some(mkKeyEvent(keyO, {mkSuper}))):
      echo "File -> Open"

    if menuParentItem("Open &Recent...",
                   some(mkKeyEvent(keyO, {mkShift, mkSuper}))):
      discard menuItem("No recent files", disabled = true)

    if menuItem("Revert", shortcut = none(KeyEvent), disabled = true,
             tooltip = "Reload the saved file."):
      echo "File -> Revert"

    if menuParentItem("Recover", shortcut = none(KeyEvent)):
      if menuItem("&Last Session", tooltip = "Open the last closed file."):
        echo "File -> Revert"

      if menuItem("&Auto Save",
                  tooltip = "Open an automatically saved file to recover it."):
        echo "File -> Revert"

    menuItemSeparator()

    if menuItem("&Save", some(mkKeyEvent(keyO, {mkSuper})),
                tooltip = "Save the current file."):
      echo "File -> Save"

    if menuItem("Save &As...", some(mkKeyEvent(keyO, {mkShift, mkSuper})),
                tooltip = "Save the current file in the desired location."):
      echo "File -> Save As"

    if menuItem("Save &Copy...",
                tooltip = "Save the current file in the desired location."):
      echo "File -> Save Copy"

    menuItemSeparator()

    if menuItem("&Quit", some(mkKeyEvent(keyQ, {mkSuper})),
                tooltip = "Quit the program."):
      echo "File -> Save Copy"

  of "Edit":
    if menuItem("&Undo", some(mkKeyEvent(keyZ, {mkSuper}))):
      echo "Edit -> Undo"

    if menuItem("&Redo", some(mkKeyEvent(keyZ, {mkShift, mkSuper}))):
      echo "Edit -> Redo"

    menuItemSeparator()

    if menuItem("Undo &History..."): echo "Edit -> Undo History"

  of "Help":
    if menuItem("&Manual"):    echo "Help -> Manual"
    if menuItem("&Tutorials"): echo "Help -> Tutorials"
    if menuItem("&Support"):   echo "Help -> Support"

    menuItemSeparator()

    if menuItem("Save System &Info"): echo "Help -> Save System Info"

  else: discard
]#

  ############################################################

  koi.endFrame()
  vg.endFrame()


proc renderFrame(win: Window, res: tuple[w, h: int32] = (0,0)) =
  let
    (winWidth, winHeight) = win.size
    (fbWidth, fbHeight) = win.framebufferSize
    pxRatio = fbWidth / winWidth

  # Update and render
  glViewport(0, 0, fbWidth, fbHeight)

  glClearColor(0.3, 0.3, 0.3, 1.0)

  glClear(GL_COLOR_BUFFER_BIT or
          GL_DEPTH_BUFFER_BIT or
          GL_STENCIL_BUFFER_BIT)

  renderUI(winWidth.float, winHeight.float, pxRatio)

  glfw.swapBuffers(win)


proc windowPosCb(win: Window, pos: tuple[x, y: int32]) =
  renderFrame(win)

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  renderFrame(win)

proc init(): Window =
  glfw.initialize()

  var win = createWindow()

  var flags = {nifStencilStrokes, nifAntialias, nifDebug}
  vg = nvgInit(getProcAddress, flags)
  if vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(vg)

  koi.init(vg, getProcAddress)

  win.windowPositionCb = windowPosCb
  win.framebufferSizeCb = framebufSizeCb

  glfw.swapInterval(1)

  win.pos = (400, 150)  # TODO for development
  wrapper.showWindow(win.getHandle())

  result = win


proc cleanup() =
  koi.deinit()
  nvgDeinit(vg)
  glfw.terminate()


proc main() =
  let win = init()

  while not win.shouldClose: # TODO key buf, like char buf?
    if koi.shouldRenderNextFrame():
      glfw.pollEvents()
    else:
      glfw.waitEvents()
    renderFrame(win)

  cleanup()


main()

# vim: et:ts=2:sw=2:fdm=marker
