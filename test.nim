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

  dropdownVal1 = 0
  dropdownVal2 = 0
  dropdownVal3 = 3
  dropdownTopRight = 0
  dropdownBottomLeft = 0
  dropdownBottomRight = 0

#  textFieldVal1 = ""
#  textFieldVal2 = "Nobody expects the Spanish Inquisition!"
#  textFieldVal3 = "Raw text field"
#
  textFieldVal1 = "Some text"
  textFieldVal2 = "Look behind you! A three-headed monkey!"
  textFieldVal3 = "42"

  textAreaVal1 = "A merry little surge of electricity piped by automatic alarm from the mood organ beside his bed awakened Rick Deckard. Surprised—it always surprised him to find himself awake without prior notice—he rose from the bed, stood up in his multicolored pajamas, and stretched.\n\nNow, in her bed, his wife Iran opened her gray, unmerry eyes, blinked, then groaned and shut her eyes again."
  printBreakRows = true


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

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  ##########################################

  var txt = textAreaVal1
#  var txt = "i\nF\nii\nFi\n\niii\n\n\ndoes not\nwork."
#  var txt = "i\nii\n\niii\n\n\ndoes not\nwork."

  if printBreakRows:
    let rows = textBreakLines(txt, 300)
    printBreakRows = false

    echo vg.textWidth("i")
    echo vg.textWidth("ii")
    echo vg.textWidth("iii")
    echo vg.textWidth("does not")
    echo vg.textWidth("work.")
    echo vg.textWidth("blinked, then groaned and shut her eyes again") # one last line

    for row in rows:
      echo row
      echo "'", txt.runeSubStr(row.startPos, row.endPos - row.startPos + 1), "'"
      echo ""

  ############################################################
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

  koi.label(x, y, w, h, "Koi widget tests", labelStyle)

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
  scrollBarVal1 = koi.horizScrollBar(
    x, y, w * 1.5, h,
    startVal = 0, endVal = 100, thumbSize = 20, clickStep = 10.0,
    tooltip = "Horizontal ScrollBar 1",
    scrollBarVal1)

  y += pad
  scrollBarVal2 = koi.horizScrollBar(
    x, y, w * 1.5, h ,
    startVal = 0, endVal = 1, thumbSize = -1, clickStep = -1,
    tooltip = "Horizontal ScrollBar 2",
    scrollBarVal2)

  scrollBarVal3 = koi.vertScrollBar(
    320, 60, h, 140,
    startVal = 0.0, endVal = 100, thumbSize = 20, clickStep = 10,
    tooltip = "Vertical ScrollBar 1",
    scrollBarVal3)

  scrollBarVal4 = koi.vertScrollBar(
    350, 60, h, 140,
    startVal = 1, endVal = 0, thumbSize = -1, clickStep = -1,
    tooltip = "Vertical ScrollBar 2",
    scrollBarVal4)

  y += pad
  scrollBarVal5 = koi.horizScrollBar(
    x, y, w * 1.5, h,
    startVal = 100, endVal = 0, thumbSize = 20, clickStep = 10.0,
    tooltip = "Horizontal ScrollBar 3",
    scrollBarVal5)

  # Sliders

  y += pad * 2
  sliderVal1 = koi.horizSlider(
    x, y, w * 1.5, h,
    startVal = 0, endVal = 100, tooltip = "Horizontal Slider 1",
    sliderVal1)

  y += pad
  sliderVal2 = koi.horizSlider(
    x, y, w * 1.5, h,
    startVal = 50, endVal = -30, tooltip = "Horizontal Slider 2",
    sliderVal2)

  sliderVal3 = koi.vertSlider(
    320, 460, h, 120,
    startVal = 0, endVal = 100, tooltip = "Vertical Slider 1",
    sliderVal3)

  koi.label(300, 590, w, h, fmt"{sliderVal3:.3f}", labelStyle)

  sliderVal4 = koi.vertSlider(
    400, 460, h, 120,
    startVal = 50, endVal = -30, tooltip = "Vertical Slider 2",
    sliderVal4)

  koi.label(380, 590, w, h, fmt"{sliderVal4:.3f}", labelStyle)

  # Dropdowns
  y += pad * 2
  dropdownVal1 = koi.dropdown(
    x, y, w, h,
    items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
    dropdownVal1,
    tooltip = "Select a fruit")

  dropdownVal2 = koi.dropdown(
    280, y, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropdownVal2,
    tooltip = "Select a colour")

  dropdownVal3 = koi.dropdown(
    430, y, w, h,
    items = @["This", "Dropdown", "Is", "Disabled"],
    dropdownVal3,
    tooltip = "Disabled dropdown",
    disabled = true)

  dropdownTopRight = koi.dropdown(
    winWidth.float - (w+10), 20, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropdownTopRight,
    tooltip = "Select a colour")

  dropdownBottomRight = koi.dropdown(
    winWidth.float - (w+10), winHeight.float - 40, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropdownBottomRight,
    tooltip = "Select a colour")

  dropdownBottomLeft = koi.dropdown(
    10, winHeight.float - 40, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    dropdownBottomLeft,
    tooltip = "Select a colour")

  # Text fields
  y += pad * 2
  textFieldVal1 = koi.textField(
    x, y, w * 1.0, h, textFieldVal1, tooltip = "Text field 1")

  y += pad
  textFieldVal2 = koi.textField(
    x, y, w * 1.0, h, textFieldVal2, tooltip = "Text field 2")

  y += pad
  textFieldVal3 = koi.rawTextField(
    x, y, w * 1.0, h, textFieldVal3, tooltip = "Text field 3")

  # Checkboxes
  y += pad * 2
  checkBoxVal1 = koi.checkBox(
    x, y, h, checkBoxVal1, tooltip = "CheckBox 1")

  checkBoxVal2 = koi.checkBox(
    x + 30, y, h, checkBoxVal2, tooltip = "CheckBox 2")

  # Radio buttons (horiz)
  y += pad * 2
  radioButtonsVal1 = koi.radioButtons(
    x, y, 150, h+2,
    labels = @["PNG", "JPG", "OpenEXR"],
    radioButtonsVal1,
    tooltips = @["Save PNG image", "Save JPG image", "Save EXR image"])

  y += pad
  radioButtonsVal2 = koi.radioButtons(
    x, y, 220, h+2,
    labels = @["One", "Two", "The Third Option"],
    radioButtonsVal2,
    tooltips = @["First (1)", "Second (2)", "Third (3)"])

  # Custom drawn radio buttons
  var radioButtonsDrawProc: RadioButtonsDrawProc =
    proc (vg: NVGContext, buttonIdx: Natural, label: string,
          hover, active, pressed, first, last: bool,
          x, y, w, h: float, style: RadioButtonsStyle) =

      var col = hsl(0.08 * buttonIdx, 0.6, 0.5)

      if hover:
        col = col.lerp(white(), 0.3)
      if pressed:
        col = col.lerp(black(), 0.3)

      const Pad = 4

      vg.beginPath()
      vg.fillColor(col)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.fill()

      vg.fillColor(black(0.7))
      vg.setFont(14.0, horizAlign=haCenter)
      discard vg.text(x + (w-Pad)*0.5, y + h*0.5,
                      label)
      if active:
        vg.strokeColor(rgb(1.0, 0.4, 0.4))
        vg.strokeWidth(2)
        vg.stroke()

  radioButtonsVal3 = koi.radioButtons(
    500, 100, 150, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal3,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    drawProc=radioButtonsDrawProc.some
  )

  radioButtonsVal4 = koi.radioButtons(
    500, 160, 30, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal4,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc=radioButtonsDrawProc.some
  )

  radioButtonsVal5 = koi.radioButtons(
    500, 220, 30, 30,
    labels = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B"],
    radioButtonsVal5,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc=radioButtonsDrawProc.some
  )

  # Radio buttons (vert)
  radioButtonsVal6 = koi.radioButtons(
    700, 100, 30, 30,
    labels = @["1", "2", "3", "4"],
    radioButtonsVal6,
    tooltips = @["First (1)", "Second (2)", "Third (3)", "Fourth (4)"],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 4),
    drawProc=radioButtonsDrawProc.some
  )

  radioButtonsVal7 = koi.radioButtons(
    770, 100, 30, 30,
    labels = @["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B",],
    radioButtonsVal7,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 4),
    drawProc=radioButtonsDrawProc.some
  )


  textAreaVal1 = koi.textArea(
    650, 300, 300, 230, textAreaVal1, tooltip = "Text area 1")


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

  koi.init(vg)

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
