import strformat

import glad/gl
import glfw
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

  dropdownVal1 = 0
  dropdownVal2 = 2

  textFieldVal1 = ""
  textFieldVal2 = "Nobody expects the Spanish Inquisition!"

############################################################

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


proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add font italic.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add font italic.\n"


proc render(win: Window, res: tuple[w, h: int32] = (0,0)) =
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
  koi.beginFrame()

  ############################################################
  let
    w = 110.0
    h = 22.0
    pad = h + 8
  var
    x = 100.0
    y = 50.0

  koi.label(x + 5, y, w, h, "Test buttons", color = gray(0.90),
            fontSize = 22.0)

  # Buttons
  y += pad
  if koi.button(x, y, w, h, "Start", color = GRAY_MID,
                tooltip = "I am the first!"):
    echo "button 1 pressed"

  y += pad
  if koi.button(x, y, w, h, "Stop", color = GRAY_MID,
                tooltip = "Middle one..."):
    echo "button 2 pressed"

  y += pad
  if koi.button(x, y, w, h, "Preferences", color = GRAY_MID,
                tooltip = "Last button"):
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
    320, 300, h, 120,
    startVal = 0, endVal = 100, tooltip = "Vertical Slider 1",
    sliderVal3)

  koi.label(320, 430, w, h, fmt"{sliderVal3:.3f}",
            color = gray(0.90), fontSize = 19.0)

  sliderVal4 = koi.vertSlider(
    400, 300, h, 120,
    startVal = 50, endVal = -30, tooltip = "Vertical Slider 2",
    sliderVal4)

  koi.label(400, 430, w, h, fmt"{sliderVal4:.3f}",
            color = gray(0.90), fontSize = 19.0)

  # Text fields
  y += pad * 2
  textFieldVal1 = koi.textField(
    x, y, w * 1.0, h, tooltip = "Text field 1", textFieldVal1)

  y += pad
  textFieldVal2 = koi.textField(
    x, y, w * 1.0, h, tooltip = "Text field 2", textFieldVal2)

  # Checkboxes
  y += pad * 2
  checkBoxVal1 = koi.checkBox(
    x, y, h, tooltip = "CheckBox 1", checkBoxVal1)

  checkBoxVal2 = koi.checkBox(
    x + 30, y, h, tooltip = "CheckBox 2", checkBoxVal2)

  # Radio buttons
  y += pad * 2
  radioButtonsVal1 = koi.radioButtons(
    x, y, 150, h,
    labels = @["PNG", "JPG", "EXR"],
    tooltips = @["Save PNG image", "Save JPG image", "Save EXR image"],
    radioButtonsVal1)

  y += pad * 2
  radioButtonsVal2 = koi.radioButtons(
    x, y, 220, h,
    labels = @["One", "Two", "Three"],
    tooltips = @["First (1)", "Second (2)", "Third (3)"],
    radioButtonsVal2)

  # Dropdowns
  y = 50.0 + pad
  x = 500
  dropdownVal1 = koi.dropdown(
    x, y, w, h,
    items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
    tooltip = "Select a fruit",
    dropdownVal1)

  y = 50.0 + pad
  x = 650
  dropdownVal2 = koi.dropdown(
    x, y, w, h,
    items = @["Red", "Green", "Blue", "Yellow", "Purple (with little yellow dots)"],
    tooltip = "Select a colour",
    dropdownVal2)

  ############################################################

  koi.endFrame()
  vg.endFrame()

  glfw.swapBuffers(win)


proc windowPosCb(win: Window, pos: tuple[x, y: int32]) =
  render(win)

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  render(win)

proc init(): Window =
  glfw.initialize()

  var win = createWindow()
  win.pos = (400, 150)  # TODO for development

  var flags = {nifStencilStrokes, nifDebug}
  vg = nvgInit(getProcAddress, flags)
  if vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(vg)

  koi.init(vg)

  win.windowPositionCb = windowPosCb
  win.framebufferSizeCb = framebufSizeCb

  glfw.swapInterval(0)

  result = win


proc cleanup() =
  nvgDeinit(vg)
  glfw.terminate()


proc main() =
  let win = init()

  while not win.shouldClose:
#    if win.isKeyDown(keyEscape):  # TODO key buf, like char buf?
#      win.shouldClose = true

    render(win)
    glfw.pollEvents()

  cleanup()


main()

# vim: et:ts=2:sw=2:fdm=marker
