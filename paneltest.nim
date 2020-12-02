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
  sectionUserInterface = true

  sectionGeneral = true
  sectionTemp = true

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
  themeAuthor = "chaos"

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

  if koi.sectionHeader("User interface", sectionUserInterface):

    if koi.subSectionHeader("General", sectionGeneral):
      koi.label("Background")
      koi.color(currTheme.general.backgroundColor)

      koi.label("Highlight")
      koi.color(currTheme.general.highlightColor)

    if koi.subSectionHeader("Widget", sectionWidget):
      koi.group:
        koi.label("Background")
        koi.color(currTheme.widget.bgColor)

        koi.label("Background hover")
        koi.color(currTheme.widget.bgColorHover)

        koi.label("Background disabled")
        koi.color(currTheme.widget.bgColorDisabled)

      koi.group:
        koi.label("Text")
        koi.color(currTheme.widget.textColor)

        koi.label("Text disabled")
        koi.color(currTheme.widget.textColorDisabled)

    if koi.subSectionHeader("Text field", sectionTextField):
      koi.group:
        koi.label("Background active")
        koi.color(currTheme.textField.bgColorActive)

        koi.label("Text active")
        koi.color(currTheme.textField.textColorActive)

        koi.label("Cursor")
        koi.color(currTheme.textField.cursorColor)

        koi.label("Selection")
        koi.color(currTheme.textField.selectionColor)

    if koi.subSectionHeader("Dialog", sectionDialog):
      koi.group:
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

    if koi.subSectionHeader("Title bar", sectionTitleBar):
      koi.group:
        koi.label("Background")
        koi.color(currTheme.titleBar.backgroundColor)

        koi.label("Background unfocused")
        koi.color(currTheme.titleBar.bgColorUnfocused)

      koi.group:
        koi.label("Text")
        koi.color(currTheme.titleBar.textColor)

        koi.label("Text unfocused")
        koi.color(currTheme.titleBar.textColorUnfocused)

      koi.group:
        koi.label("Modified flag")
        koi.color(currTheme.titleBar.modifiedFlagColor)

      koi.group:
        koi.label("Button")
        koi.color(currTheme.titleBar.buttonColor)

        koi.label("Button hover")
        koi.color(currTheme.titleBar.buttonColorHover)

        koi.label("Button down")
        koi.color(currTheme.titleBar.buttonColorDown)


  if koi.sectionHeader("Temp section", sectionTemp):

    if koi.subSectionHeader("Status bar", sectionStatusBar):
      koi.group:
        koi.label("Background")
        koi.color(currTheme.statusBar.backgroundColor)

        koi.label("Text")
        koi.color(currTheme.statusBar.textColor)

      koi.group:
        koi.label("Command background")
        koi.color(currTheme.statusBar.commandBgColor)

        koi.label("Command")
        koi.color(currTheme.statusBar.commandColor)

      koi.group:
        koi.label("Coordinates")
        koi.color(currTheme.statusBar.coordsColor)

    if koi.subSectionHeader("Level drop down", sectionLeveldropDown):
      koi.group:
        koi.label("Button")
        koi.color(currTheme.leveldropDown.buttonColor)

        koi.label("Button hover")
        koi.color(currTheme.leveldropDown.buttonColorHover)

      koi.group:
        koi.label("Text")
        koi.color(currTheme.leveldropDown.textColor)

      koi.group:
        koi.label("Item list")
        koi.color(currTheme.leveldropDown.itemListColor)

        koi.label("Item")
        koi.color(currTheme.leveldropDown.itemColor)

        koi.label("Item hover")
        koi.color(currTheme.leveldropDown.itemColorHover)

    if koi.subSectionHeader("About button", sectionAboutButton):
      koi.group:
        koi.label("Color")
        koi.color(currTheme.aboutButton.color)

        koi.label("Hover")
        koi.color(currTheme.aboutButton.colorHover)

        koi.label("Active")
        koi.color(currTheme.aboutButton.colorActive)

  koi.endScrollView()


#[
  if koi.sectionHeader("About button", sectionAboutButton):

[level]
backgroundColor         = "gray(0.4)"
drawColor               = "gray(0.1)"
lightDrawColor          = "gray(0.6)"
lineWidth               = lwNormal

floorColor1             = "gray(0.9)"
floorColor2             = "rgba(51, 92, 162, 66)"
floorColor3             = "rgba(61, 139, 231, 80)"
floorColor4             = "rgba(108, 57, 172, 66)"
floorColor5             = "rgba(137, 95, 233, 76)"
floorColor6             = "rgba(151, 0, 97, 66)"
floorColor7             = "rgba(217, 40, 158, 72)"
floorColor8             = "rgba(48, 141, 154, 55)"
floorColor9             = "rgba(54, 184, 166, 73)"

bgHatch                 = on
bgHatchColor            = "gray(0.0, 0.4)"
bgHatchStrokeWidth      = 1.0
bgHatchSpacingFactor    = 2.0

coordsColor             = "gray(0.9)"
coordsHighlightColor    = "rgb(1.0, 0.75, 0.0)"

cursorColor             = "rgb(1.0, 0.65, 0.0)"
cursorGuideColor        = "rgba(1.0, 0.65, 0.0, 0.2)"

gridStyleBackground     = gsSolid
gridColorBackground     = "gray(0.0, 0.1)"
gridStyleFloor          = gsSolid
gridColorFloor          = "gray(0.2, 0.4)"

outlineStyle            = osCell
outlineFillStyle        = ofsSolid
outlineOverscan         = off
outlineColor            = "gray(0.22)"
outlineWidthFactor      = 0.5

innerShadow             = off
innerShadowColor        = "gray(0.0, 0.1)"
innerShadowWidthFactor  = 0.125
outerShadow             = off
outerShadowColor        = "gray(0.0, 0.1)"
outerShadowWidthFactor  = 0.125

selectionColor          = "rgba(1.0, 0.5, 0.5, 0.4)"
pastePreviewColor       = "rgba(0.2, 0.6, 1.0, 0.4)"

noteMarkerColor         = "gray(0.1, 0.7)"
noteCommentColor        = "rgba(1.0, 0.2, 0.0, 0.8)"
noteIndexColor          = "gray(1.0)"
noteIndexBgColor1       = "rgb(247, 92, 74)"
noteIndexBgColor2       = "rgb(255, 156, 106)"
noteIndexBgColor3       = "rgb(0, 179, 200)"
noteIndexBgColor4       = "rgb(19, 131, 127)"

noteTooltipBgColor      = "gray(0.03)"
noteTooltipTextColor    = "gray(0.9)"

linkMarkerColor         = "rgb(0, 179, 200)"

#-----------------------------------------------------------------------------

[notesPane]
textColor               = "gray(0.9)"
indexColor              = "gray(1.0)"
indexBgColor1           = "rgb(247, 92, 74)"
indexBgColor2           = "rgb(250, 141, 100)"
indexBgColor3           = "rgb(0, 179, 200)"
indexBgColor4           = "rgb(29, 141, 137)"

[toolbarPane]
buttonBgColor           = "gray(0.9)"
buttonBgColorHover      = "gray(1.0)"
]#




  koi.beginScrollView(x=400, y=150, w=300, h=300)

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
