import lenientops
import strformat
import unicode

import koi/glad/gl
import glfw
from glfw/wrapper import showWindow
import nanovg

import koi


# Global NanoVG context
var vg: NVGContext


### UI DATA ##################################################################
var
  section1 = true
  section2 = true

  checkBoxVal1 = true
  checkBoxVal2 = false
  checkBoxVal3 = false
  checkBoxVal4 = true

  dropdownVal1 = 0
  dropdownVal2 = 1

##############################################################################

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

  ############################################################################

  var labelStyle = getDefaultLabelStyle()
  labelStyle.align = haLeft

  koi.beginScrollPanel(x=100, y=100, w=250, h=200)

#  koi.setAutoLayout(rowWidth=250, labelWidth=150)

  if koi.sectionHeader("First section", section1):
    koi.beginGroup()
    koi.label("CheckBox 1", labelStyle)
    koi.checkBox(checkBoxVal1, tooltip = "Checkbox 1")

    koi.label("CheckBox 2", labelStyle)
    koi.checkBox(checkBoxVal2, tooltip = "Checkbox 2")

    koi.label("CheckBox 3", labelStyle)
    koi.checkBox(checkBoxVal3, tooltip = "Checkbox 3")

    koi.label("CheckBox 4", labelStyle)
    koi.checkBox(checkBoxVal4, tooltip = "Checkbox 4")
    koi.endGroup()

    koi.beginGroup()
    koi.label("Dropdown 1", labelStyle)
    koi.dropdown(items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
                 dropdownVal1,
                 tooltip = "Select a fruit")

    koi.label("Dropdown 2", labelStyle)
    koi.dropdown(items = @["One", "Two", "Three"],
                 dropdownVal2,
                 tooltip = "Select a number")
    koi.endGroup()

  if koi.sectionHeader("Second section", section2):
    koi.label("Dropdown 1", labelStyle)
    koi.dropdown(items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
                 dropdownVal1,
                 tooltip = "Select a fruit")

    koi.beginGroup()
    koi.label("CheckBox 1", labelStyle)
    koi.checkBox(checkBoxVal1, tooltip = "Checkbox 1")

    koi.label("CheckBox 2", labelStyle)
    koi.checkBox(checkBoxVal2, tooltip = "Checkbox 2")
    koi.endGroup()

  koi.endScrollPanel()

  ############################################################################

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
