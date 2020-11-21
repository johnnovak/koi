import lenientops
import strformat
import unicode

import koi/glad/gl
import glfw
from glfw/wrapper import showWindow
import nanovg

import koi

import ../gridmonger/src/theme


# Global NanoVG context
var vg: NVGContext


### UI DATA ##################################################################
var
  sectionGeneral = true
  sectionWidget = true
  sectionTextField = true
  sectionDialog = true
  sectionTitleBar = true
  sectionStatusBar = true
  sectionLeveldropDown = true
  sectionAboutButton = true

var currTheme = loadTheme("../gridmonger/themes/Default.cfg")

var
  themeName = "Default"

  section1 = true
  section2 = true
  section3 = true

  dropDownVal1 = 0
  dropDownVal2 = 0
  dropDownVal3 = 0

  checkBoxVal1 = false
  checkBoxVal2 = false
  checkBoxVal3 = false
  checkBoxVal4 = false
  checkBoxVal5 = false
  checkBoxVal6 = false

let layoutParams = AutoLayoutParams(
  rowWidth:         300.0,
  labelWidth:       180.0,
  itemsPerRow:      2,
  rowPad:           16.0,
  rowGroupPad:      6.0,
  defaultRowHeight: 22.0
)

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

  koi.beginScrollView(x=100, y=100, w=250, h=600)

  var lp = layoutParams
  lp.rowWidth = 230
  koi.setAutoLayoutParams(lp)

  if koi.sectionHeader("General", sectionGeneral):
    koi.beginGroup()
    koi.label("Theme name")
    koi.textfield(themeName)

    koi.label("Background")
    koi.color(currTheme.general.backgroundColor)

    koi.label("Highlight")
    koi.color(currTheme.general.highlightColor)
    koi.endGroup()

  if koi.sectionHeader("Widget", sectionWidget):
    koi.beginGroup()
    koi.label("Background")
    koi.color(currTheme.widget.bgColor)

    koi.label("Background hover")
    koi.color(currTheme.widget.bgColorHover)

    koi.label("Background disabled")
    koi.color(currTheme.widget.bgColorDisabled)

    koi.beginGroup()
    koi.label("Text")
    koi.color(currTheme.widget.textColor)

    koi.label("Text disabled")
    koi.color(currTheme.widget.textColorDisabled)
    koi.endGroup()

  if koi.sectionHeader("Text field", sectionTextField):
    koi.beginGroup()
    koi.label("Background active")
    koi.color(currTheme.textField.bgColorActive)

    koi.label("Text active")
    koi.color(currTheme.textField.textColorActive)

    koi.label("Cursor")
    koi.color(currTheme.textField.cursorColor)

    koi.label("Selection")
    koi.color(currTheme.textField.selectionColor)
    koi.endGroup()

  if koi.sectionHeader("Dialog", sectionDialog):
    koi.beginGroup()
    koi.label("Title bar background")
    koi.color(currTheme.dialog.titleBarBgColor)

    koi.label("Title bar text")
    koi.color(currTheme.dialog.titleBarTextColor)

    koi.label("Background")
    koi.color(currTheme.dialog.backgroundColor)

    koi.label("Text")
    koi.color(currTheme.dialog.textColor)

    koi.label("Warning text")
    koi.color(currTheme.dialog.warningTextColor)
    koi.endGroup()

  if koi.sectionHeader("Title bar", sectionTitleBar):
    koi.beginGroup()
    koi.label("Background")
    koi.color(currTheme.titleBar.backgroundColor)

    koi.label("Background unfocused")
    koi.color(currTheme.titleBar.bgColorUnfocused)

    koi.label("Text")
    koi.color(currTheme.titleBar.textColor)

    koi.label("Text unfocused")
    koi.color(currTheme.titleBar.textColorUnfocused)

    koi.beginGroup()
    koi.label("Modified flag")
    koi.color(currTheme.titleBar.modifiedFlagColor)

    koi.label("Button")
    koi.color(currTheme.titleBar.buttonColor)

    koi.label("Button hover")
    koi.color(currTheme.titleBar.buttonColorHover)

    koi.label("Button down")
    koi.color(currTheme.titleBar.buttonColorDown)
    koi.endGroup()

  if koi.sectionHeader("Status bar", sectionStatusBar):
    koi.beginGroup()
    koi.label("Background")
    koi.color(currTheme.statusBar.backgroundColor)

    koi.label("Text")
    koi.color(currTheme.statusBar.textColor)

    koi.label("Command background")
    koi.color(currTheme.statusBar.commandBgColor)

    koi.label("Command")
    koi.color(currTheme.statusBar.commandColor)

    koi.label("Coordinates")
    koi.color(currTheme.statusBar.coordsColor)
    koi.endGroup()

  if koi.sectionHeader("Level dropDown", sectionLeveldropDown):
    koi.beginGroup()
    koi.label("Button")
    koi.color(currTheme.leveldropDown.buttonColor)

    koi.label("Button hover")
    koi.color(currTheme.leveldropDown.buttonColorHover)

    koi.label("Text")
    koi.color(currTheme.leveldropDown.textColor)

    koi.beginGroup()
    koi.label("Item list")
    koi.color(currTheme.leveldropDown.itemListColor)

    koi.label("Item")
    koi.color(currTheme.leveldropDown.itemColor)

    koi.label("Item hover")
    koi.color(currTheme.leveldropDown.itemColorHover)
    koi.endGroup()

  if koi.sectionHeader("About button", sectionAboutButton):
    koi.beginGroup()
    koi.label("Color")
    koi.color(currTheme.aboutButton.color)

    koi.label("Hover")
    koi.color(currTheme.aboutButton.colorHover)

    koi.label("Active")
    koi.color(currTheme.aboutButton.colorActive)
    koi.endGroup()

#-----------------------------------------------------------------------------

#[
  if koi.sectionHeader("Level", section):
    backgroundColor         = "rgb(90, 90, 130)"
    drawColor               = "rgb(40, 40, 65)"
    lightDrawColor          = "rgba(140, 140, 185, 170)"
    lineWidth               = lwNormal

    floorColor1             = "rgb(230, 230, 240)"
    floorColor2             = "rgba(51, 92, 162, 66)"
    floorColor3             = "rgba(61, 139, 231, 80)"
    floorColor4             = "rgba(108, 57, 172, 66)"
    floorColor5             = "rgba(137, 95, 233, 76)"
    floorColor6             = "rgba(151, 0, 97, 66)"
    floorColor7             = "rgba(217, 40, 158, 72)"
    floorColor8             = "rgba(48, 141, 154, 55)"
    floorColor9             = "rgba(54, 184, 166, 73)"

    bgHatch                 = off

    coordsColor             = "gray(1.0, 0.4)"
    coordsHighlightColor    = "rgb(255, 190, 0)"

    cursorColor             = "rgb(255, 190, 0)"
    cursorGuideColor        = "rgba(255, 180, 111, 60)"

    gridStyleBackground     = gsSolid
    gridColorBackground     = "rgba(50, 50, 55, 0)"
    gridStyleFloor          = gsSolid
    gridColorFloor          = "rgba(50, 50, 55, 70)"

    outlineStyle            = osNone

    innerShadow             = off
    outerShadow             = off

    selectionColor          = "rgba(1.0, 0.5, 0.5, 0.4)"
    pastePreviewColor       = "rgba(0.2, 0.6, 1.0, 0.4)"

    noteMarkerColor         = "rgba(64, 78, 127, 230)"
    noteCommentColor        = "rgba(1.0, 0.2, 0.0, 0.8)"
    noteIndexColor          = "gray(0.9)"
    noteIndexBgColor1       = "rgb(245, 98, 141)"
    noteIndexBgColor2       = "rgb(163, 137, 215)"
    noteIndexBgColor3       = "rgb(102, 162, 220)"
    noteIndexBgColor4       = "rgb(151, 151, 160)"

    noteTooltipBgColor      = "rgb(30, 30, 50)"
    noteTooltipTextColor    = "gray(0.98)"

    linkMarkerColor         = "rgba(120, 50, 140, 170)"

    #-----------------------------------------------------------------------------

    [notesPane]
      if koi.sectionHeader("", section):
    textColor               = "gray(1.0, 0.93)"
    indexColor              = "gray(1.0, 0.93)"
    indexBgColor1           = "rgb(245, 98, 141)"
    indexBgColor2           = "rgb(163, 137, 215)"
    indexBgColor3           = "rgb(92, 152, 210)"
    indexBgColor4           = "rgb(131, 131, 140)"

    [toolbarPane]
    buttonBgColor           = "rgb(210, 210, 220)"
    buttonBgColorHover      = "rgb(255, 255, 255)"
]#

  koi.endScrollView()


  koi.beginScrollView(x=400, y=150, w=300, h=300)

  lp = layoutParams
  lp.rowWidth = 270
  koi.setAutoLayoutParams(lp)

  if koi.sectionHeader("First section", section1):
    koi.beginGroup()
    koi.label("CheckBox 1")
    koi.checkBox(checkBoxVal1, tooltip = "Checkbox 1")

    koi.label("CheckBox 2")
    koi.checkBox(checkBoxVal2, tooltip = "Checkbox 2")

    koi.label("CheckBox 3")
    koi.checkBox(checkBoxVal3, tooltip = "Checkbox 3")

    koi.label("CheckBox 4")
    koi.checkBox(checkBoxVal4, tooltip = "Checkbox 4")
    koi.endGroup()

    koi.beginGroup()
    koi.label("dropDown 1")
    koi.dropDown(items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
                 dropDownVal1,
                 tooltip = "Select a fruit")

    koi.label("dropDown 2")
    koi.dropDown(items = @["One", "Two", "Three"],
                 dropDownVal2,
                 tooltip = "Select a number")
    koi.endGroup()

  if koi.sectionHeader("Second section", section2):
    koi.label("dropDown 1")
    koi.dropDown(items = @["Orange", "Banana", "Blueberry", "Apricot", "Apple"],
                 dropDownVal3,
                 tooltip = "Select a fruit")

    koi.beginGroup()
    koi.label("CheckBox 1")
    koi.checkBox(checkBoxVal5, tooltip = "Checkbox 1")

    koi.label("CheckBox 2")
    koi.checkBox(checkBoxVal6, tooltip = "Checkbox 2")
    koi.endGroup()

  koi.endScrollView()

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
