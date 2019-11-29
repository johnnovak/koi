import options, strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import nanovg

import koi
import pattern


# Global NanoVG context
var vg: NVGContext


### UI DATA ################################################

var
  pattern1 = initPattern()
  track1 = initTrack()
  track2 = initTrack()
  track3 = initTrack()
  track4 = initTrack()

track1.rows[0].note = some(Note(1))
track1.rows[2].note = some(Note(2))
track1.rows[4].note = some(Note(4))
track1.rows[8].note = some(Note(15))
track1.rows[10].note = some(Note(20))

track2.rows[3].note = some(Note(21))
track2.rows[7].note = some(Note(42))
track2.rows[8].note = some(Note(44))
track2.rows[9].note = some(Note(15))
track2.rows[13].note = some(Note(20))

track3.rows[10].note = some(Note(8))
track3.rows[12].note = some(Note(32))
track3.rows[14].note = some(Note(34))
track3.rows[13].note = some(Note(15))
track3.rows[12].note = some(Note(20))

track4.rows[20].note = some(Note(14))
track4.rows[22].note = some(Note(14))
track4.rows[24].note = some(Note(14))
track4.rows[28].note = some(Note(15))
track4.rows[21].note = some(Note(20))

pattern1.tracks.add(track1)
pattern1.tracks.add(track2)
pattern1.tracks.add(track3)
pattern1.tracks.add(track4)



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
  koi.beginFrame(winWidth.float, winHeight.float)

  ############################################################

  var
    x = 20.0
    y = 20.0

  vg.fontSize(17.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(white())

  for track in pattern1.tracks:
    for row in track.rows:
      let
        note = toStr(row.note)
        fx1 =  $row.effect[0] & $row.effect[1] & $row.effect[2]
      if row.note.isNone:
        vg.fillColor(gray(0.500))
      else:
        vg.fillColor(gray(0.990))
      discard vg.text(x, y, note)
      vg.fillColor(gray(0.700))
      discard vg.text(x + 32, y, fx1)
      y += 17
    x += 80
    y = 20

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

  while not win.shouldClose:
#    if win.isKeyDown(keyEscape):  # TODO key buf, like char buf?
#      win.shouldClose = true

    render(win)
    glfw.pollEvents()

  cleanup()


main()

# vim: et:ts=2:sw=2:fdm=marker
