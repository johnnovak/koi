import math, strformat

import glad/gl
import glfw
import nanovg


# {{{ Types

type TooltipState = enum
  tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

const
  TooltipShowDelay       = 0.5
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 0.3

type DragMode = enum         # TODO remove?
  dmOff, dmNormal, dmHidden

type SliderState = enum
  ssDefault, ssDragNormal, ssDragHidden,
  ssTrackClickFirst, ssTrackClickWait, ssTrackClickRepeat

type UIState = object
  # Mouse state
  mx, my:         float
  lastmx, lastmy: float
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
  lastHotItem:    int   # TODO needed?

  # Internal state for slider types
  x0, y0:       float
  dragMode:     DragMode    # TODO remove?
  sliderState:  SliderState
  sliderTrackClickDir: float
  sliderTrackClickT0:  float

  dragX, dragY: float
  sliderStep:   bool  # TODO remove

  # Internal state for tooltips
  tooltipState:     TooltipState
  lastTooltipState: TooltipState
  tooltipT0:        float
  tooltipText:      string

type DrawState = enum
  dsNormal, dsHover, dsActive

# }}}
# {{{ Utils

proc lerp(a, b, t: float): float =
  a + (b - a) * t

proc invLerp(a, b, v: float): float =
  (v - a) / (b - a)


proc disableCursor() =
  glfw.currentContext().cursorMode = cmDisabled

proc enableCursor() =
  glfw.currentContext().cursorMode = cmNormal

proc setCursorPosX(x: float) =
  let win = glfw.currentContext()
  let (_, currY) = win.cursorPos()
  win.cursorPos = (x, currY)

proc setCursorPosY(y: float) =
  let win = glfw.currentContext()
  let (currX, _) = win.cursorPos()
  win.cursorPos = (currX, y)

# }}}
# {{{ Globals

var gui: UIState

template isHot(id: int): bool =
  gui.hotItem == id

template setHot(id: int) =
  gui.hotItem = id

template isActive(id: int): bool =
  gui.activeItem == id

template setActive(id: int) =
  gui.activeItem = id

template isHotAndActive(id: int): bool =
  isHot(id) and isActive(id)

template noActiveItem(): bool =
  gui.activeItem == 0

let RED = rgb(1.0, 0.4, 0.4)

# }}}
# {{{ Callbacks

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

# }}}

# {{{ mouseInside

proc mouseInside(x, y, w, h: float): bool =
  gui.mx >= x and gui.mx <= x+w and
  gui.my >= y and gui.my <= y+h

# }}}
# {{{ drawToolTip

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

# }}}
# {{{ handleTooltipInsideWidget

proc handleTooltipInsideWidget(id: int, tooltipText: string) =
  gui.tooltipState = gui.lastTooltipState

  # Reset the tooltip show delay if the cursor has been moved inside a
  # widget
  if gui.tooltipState == tsShowDelay:
    let cursorMoved = gui.mx != gui.lastmx or gui.my != gui.lastmy
    if cursorMoved:
      gui.tooltipT0 = getTime()

  # Hide the tooltip immediately if the LMB was pressed inside the widget
  if gui.mbLeftDown and gui.activeItem > 0:
    gui.tooltipState = tsOff

  elif gui.tooltipState == tsOff and not gui.mbLeftDown and
       gui.lastHotItem != id:
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

# }}}
# {{{ uiStatePre

proc uiStatePre() =
  gui.hotItem = 0

  gui.lastmx = gui.mx
  gui.lastmy = gui.my

  (gui.mx, gui.my) = glfw.currentContext().cursorPos()


# }}}
# {{{ uiStatePost

proc uiStatePost(vg: NVGContext) =
  echo fmt"hotItem: {gui.hotItem}, activeItem: {gui.activeItem}, sliderState: {gui.sliderState}"

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

  # We reset the show delay state or move into the fade out state if the
  # tooltip was shown to handle the case when the user just moved the cursor
  # outside of a widget. The actual widgets are responsible to "keep alive"
  # the state every frame by restoring the tooltip state from lastTooltipState
  gui.lastTooltipState = gui.tooltipState

  if gui.tooltipState == tsShowDelay:
    gui.tooltipState = tsOff
  elif gui.tooltipState == tsShow:
    gui.tooltipState = tsFadeOutDelay
    gui.tooltipT0 = getTime()

  gui.lastHotItem = gui.hotItem

  # Widget deactivation
  if gui.mbLeftDown:
    if gui.activeItem == 0 and gui.hotItem == 0:
      # LMB was pressed outside of any widget. We need to mark this as
      # a separate state so we can't just "drag into" a widget while the LMB
      # is being depressed and activate it.
      gui.activeItem = -1
  else:
    if gui.activeItem != 0:
      # If the LMB was released inside the active widget, that has already
      # been handled at this point--we're just clearing the active item here.
      # This also takes care of the case when the LMB was depressed inside the
      # widget but released outside of it.
      gui.activeItem = 0

      # Handle release slider outside of the slider
      case gui.sliderState:
      of ssDragHidden:
        gui.sliderState = ssDefault
        enableCursor()
        if gui.dragX > -1.0:
          setCursorPosX(gui.dragX)
        else:
          setCursorPosY(gui.dragY)

      else: gui.sliderState = ssDefault


#    gui.sliderStep = false

    # Disable drag mode and reset the cursor if the left mouse button was
    # released while in fine drag mode.
#    case gui.dragMode:
#    of dmOff: discard
#    of dmNormal:
#      gui.dragMode = dmOff
#
#    of dmHidden:
#      gui.dragMode = dmOff
#      enableCursor()
#      if gui.dragX > -1.0:
#        setCursorPosX(gui.dragX)
#      else:
#        setCursorPosY(gui.dragY)

# }}}

# {{{ doButton

proc doButton(vg: NVGContext, id: int, x, y, w, h: float, label: string,
                  color: Color, tooltipText: string = ""): bool =

  # Hit testing
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active button
  if not gui.mbLeftDown and isHotAndActive(id):
    result = true

  # Draw button
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover: gray(0.8)
    of dsActive: RED
    else: color

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

  if isHot(id):
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ doHorizScrollbar

# Must be kept in sync with doVertScrollbar!
proc doHorizScrollbar(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                      startVal: float = 0.0, endVal: float = 1.0,
                      thumbSize: float = -1.0, clickStep: float = -1.0,
                      tooltipText: string = ""): float =

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  assert thumbSize < 0.0 or thumbSize < abs(startVal - endVal)
  assert clickStep < 0.0 or clickStep < abs(startVal - endVal)

  const
    ThumbPad = 3
    ThumbMinW = 10

  # Calculate current thumb position
  let
    thumbSize = if thumbSize < 0: 0.000001 else: thumbSize

    thumbW = max((w - ThumbPad*2) / (abs(startVal - endVal) / thumbSize),
                 ThumbMinW)

    thumbH = h - ThumbPad * 2
    thumbMinX = x + ThumbPad
    thumbMaxX = x + w - ThumbPad - thumbW

  proc calcThumbX(val: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(thumbMinX, thumbMaxX, t)

  let thumbX = calcThumbX(value)

  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  let insideThumb = mouseInside(thumbX, y, thumbW, h)

  # New thumb position & value calculation...
  var
    newThumbX = thumbX
    newValue = value

  proc calcNewValue(newThumbX: float): float =
    let t = invLerp(thumbMinX, thumbMaxX, newThumbX)
    lerp(startVal, endVal, t)

  proc calcNewValueTrackClick(): float =
    let clickStep = if clickStep < 0: abs(startVal - endVal) * 0.1
                    else: clickStep

    let (s, e) = if startVal < endVal: (startVal, endVal)
                 else: (endVal, startVal)
    min(max(newValue + gui.sliderTrackClickDir * clickStep, s), e)

  if isActive(id):
    case gui.sliderState
    of ssDefault:
      if insideThumb:
        gui.x0 = gui.mx
        if gui.shiftDown:
          disableCursor()
          gui.sliderState = ssDragHidden
        else:
          gui.sliderState = ssDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if gui.mx < thumbX: gui.sliderTrackClickDir = -1.0 * s
        else:               gui.sliderTrackClickDir =  1.0 * s
        gui.sliderState = ssTrackClickFirst
        gui.sliderTrackClickT0 = getTime()

    of ssDragNormal:
      if gui.shiftDown:
        disableCursor()
        gui.sliderState = ssDragHidden
      else:
        let dx = gui.mx - gui.x0

        newThumbX = min(max(thumbX + dx, thumbMinX), thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = min(max(gui.mx, thumbMinX), thumbMaxX + thumbW)

    of ssDragHidden:
      if gui.shiftDown:
        let dx = (gui.mx - gui.x0) / (if gui.altDown: 100 else: 10)

        newThumbX = min(max(thumbX + dx, thumbMinX), thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = gui.mx
        gui.dragX = newThumbX + thumbW*0.5
        gui.dragY = -1.0
      else:
        gui.sliderState = ssDragNormal
        enableCursor()
        setCursorPosX(gui.dragX)
        gui.mx = gui.dragX
        gui.x0 = gui.dragX

    of ssTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbX = calcThumbX(newValue)

      gui.sliderState = ssTrackClickWait
      gui.sliderTrackClickT0 = getTime()

    of ssTrackClickWait:
      if getTime() - gui.sliderTrackClickT0 > 0.3:
        gui.sliderState = ssTrackClickRepeat

    of ssTrackClickRepeat:
      if getTime() - gui.sliderTrackClickT0 > 0.05:
        newValue = calcNewValueTrackClick()
        newThumbX = calcThumbX(newValue)
        gui.sliderTrackClickT0 = getTime()

  result = newValue

  # Draw slider
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let trackColor = case drawState
    of dsHover: gray(0.8)
    of dsActive: gray(0.6)
    else: gray(0.6)

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(trackColor)
  vg.fill()

  # Draw thumb
  let thumbColor = case drawState
    of dsHover: gray(0.35)
    of dsActive:
      if gui.sliderState < ssTrackClickFirst: RED
      else: gray(0.25)
    else: gray(0.25)

  vg.beginPath()
  vg.roundedRect(newThumbX, y + ThumbPad, thumbW, thumbH, 5)
  vg.fillColor(thumbColor)
  vg.fill()

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(white())
  let valueString = fmt"{result:.3f}"
  let tw = vg.horizontalAdvance(0,0, valueString)
  discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, valueString)

  if isHot(id):
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ doVertScrollbar

# Must be kept in sync with doHorizScrollbar!
proc doVertScrollbar(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                     startVal: float = 0.0, endVal: float = 1.0,
                     thumbSize: float = -1.0, clickStep: float = -1.0,
                     tooltipText: string = ""): float =

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  assert thumbSize < 0.0 or thumbSize < abs(startVal - endVal)
  assert clickStep < 0.0 or clickStep < abs(startVal - endVal)

  const
    ThumbPad = 3
    thumbMinH = 10

  # Calculate current thumb position
  var thumbSize = if thumbSize < 0: 0.000001 else: thumbSize
  let
    thumbH = max((h - ThumbPad*2) / (abs(startVal - endVal) / thumbSize),
                thumbMinH)
    thumbW = w - ThumbPad * 2
    thumbMinY = y + ThumbPad
    thumbMaxY = y + h - ThumbPad - thumbH

  proc calcThumbY(val: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(thumbMinY, thumbMaxY, t)

  let thumbY = calcThumbY(value)

  # Hit testing
  let (insideSlider, insideThumb) =
    if gui.dragMode == dmHidden and gui.activeItem == id:
      (true, true)
    else:
      (mouseInside(x, y, w, h), mouseInside(x, thumbY, w, thumbH))

  if insideSlider and not gui.mbLeftDown:
    gui.hotItem = id

  var sliderClicked = 0.0

  if gui.mbLeftDown and gui.activeItem == 0:
    if insideThumb and not gui.sliderStep:
      # Active item is only set if the thumb is being dragged
      gui.activeItem = id
      gui.y0 = gui.my
      if gui.shiftDown:
        gui.dragMode = dmHidden
        disableCursor()
      else:
        gui.dragMode = dmNormal

    elif insideSlider and not insideThumb and not gui.sliderStep:
      if gui.my < thumbY: sliderClicked = -1.0
      else:               sliderClicked =  1.0
      gui.sliderStep = true

  # New thumb position & value calculation...
  var
    newThumbY = thumbY
    newValue = value

  # ...when the slider was clicked outside of the thumb
  if sliderClicked != 0:
    var clickStep = if clickStep < 0: abs(startVal - endVal) * 0.1
                    else: clickStep
    if startVal < endVal:
      newValue = min(max(newValue + sliderClicked * clickStep, startVal),
                     endVal)
    else:
      newValue = min(max(newValue - sliderClicked * clickStep, endVal),
                     startVal)
    newThumbY = calcThumbY(newValue)

  # ...when dragging slider
  elif gui.activeItem == id:
    if gui.shiftDown and gui.dragMode == dmNormal:
      gui.dragMode = dmHidden
      disableCursor()

    elif not gui.shiftDown and gui.dragMode == dmHidden:
      gui.dragMode = dmNormal
      enableCursor()
      setCursorPosY(gui.dragY)
      gui.my = gui.dragY
      gui.y0 = gui.dragY

    var dy = gui.my - gui.y0
    if gui.shiftDown:
      dy /= 8
      if gui.altDown: dy /= 8

    newThumbY = min(max(thumbY + dy, thumbMinY), thumbMaxY)
    let t = invLerp(thumbMinY, thumbMaxY, newThumbY)
    newValue = lerp(startVal, endVal, t)

    gui.y0 = if gui.dragMode == dmHidden:
      gui.my
    else:
      min(max(gui.my, thumbMinY), thumbMaxY + thumbH)

    gui.dragX = -1.0
    gui.dragY = newThumbY + thumbH*0.5


  result = newValue

  # Draw slider
  let fillColor = if gui.hotItem == id and not insideThumb:
    if gui.activeItem <= 0: gray(0.8)
    else: gray(0.60)
  else: gray(0.60)

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw thumb
  let thumbColor = if gui.activeItem == id: RED
  elif insideThumb and gui.activeItem <= 0: gray(0.35)
  else: gray(0.25)

  vg.beginPath()
  vg.roundedRect(x + ThumbPad, newThumbY, thumbW, thumbH, 5)
  vg.fillColor(thumbColor)
  vg.fill()

  if insideSlider:
    handleTooltipInsideWidget(id, tooltipText)

    if gui.sliderStep:
      gui.tooltipState = tsOff

# }}}
# {{{ doHorizSlider

proc doHorizSlider(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                   startVal: float = 0.0, endVal: float = 1.0,
                   tooltipText: string = ""): float =

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  const SliderPad = 3

  let
    posMinX = x + SliderPad
    posMaxX = x + w - SliderPad

  # Calculate current slider position
  proc calcPosX(val: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(posMinX, posMaxX, t)

  let posX = calcPosX(value)

  # Hit testing
  let inside = mouseInside(x, y, w, h)

  if inside:
    if not gui.mbLeftDown:
      gui.hotItem = id
    elif gui.mbLeftDown and gui.activeItem == 0:
      gui.activeItem = id
      gui.x0 = gui.mx
      gui.dragMode = dmHidden
      gui.dragX = gui.mx
      gui.dragY = -1.0
      disableCursor()

  # New position & value calculation
  var
    newPosX = posX
    newValue = value

  if gui.activeItem == id:
    var dx = gui.mx - gui.x0
    if gui.shiftDown:
      dx /= 8
      if gui.altDown: dx /= 8

    newPosX = min(max(posX + dx, posMinX), posMaxX)
    let t = invLerp(posMinX, posMaxX, newPosX)
    newValue = lerp(startVal, endVal, t)
    gui.x0 = gui.mx

  result = newValue

  # Draw slider background
  let fillColor = if gui.hotItem == id:
    if gui.activeItem <= 0: gray(0.8)
    else: gray(0.60)
  else: gray(0.60)

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw slider
  let sliderColor = if gui.activeItem == id: RED
  elif inside and gui.activeItem <= 0: gray(0.35)
  else: gray(0.25)

  vg.beginPath()
  vg.roundedRect(x + SliderPad, y + SliderPad,
                 newPosX - x - SliderPad, h - SliderPad*2, 5)
  vg.fillColor(sliderColor)
  vg.fill()

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(white())
  let valueString = fmt"{result:.3f}"
  let tw = vg.horizontalAdvance(0,0, valueString)
  discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, valueString)

  if inside:
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ doVertSlider

proc doVertSlider(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                  startVal: float = 0.0, endVal: float = 1.0,
                  tooltipText: string = ""): float =

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  const SliderPad = 3

  let
    posMinY = y + h - SliderPad
    posMaxY = y + SliderPad

  # Calculate current slider position
  proc calcPosY(val: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(posMinY, posMaxY, t)

  let posY = calcPosY(value)

  # Hit testing
  let inside = mouseInside(x, y, w, h)

  if inside:
    if not gui.mbLeftDown:
      gui.hotItem = id
    elif gui.mbLeftDown and gui.activeItem == 0:
      gui.activeItem = id
      gui.y0 = gui.my
      gui.dragMode = dmHidden
      gui.dragX = -1.0
      gui.dragY = gui.my
      disableCursor()

  # New position & value calculation
  var
    newPosY = posY
    newValue = value

  if gui.activeItem == id:
    var dy = gui.my - gui.y0
    if gui.shiftDown:
      dy /= 8
      if gui.altDown: dy /= 8

    newPosY = min(max(posY + dy, posMaxY), posMinY)
    let t = invLerp(posMinY, posMaxY, newPosY)
    newValue = lerp(startVal, endVal, t)
    gui.y0 = gui.my

  result = newValue

  # Draw slider background
  let fillColor = if gui.hotItem == id:
    if gui.activeItem <= 0: gray(0.8)
    else: gray(0.60)
  else: gray(0.60)

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw slider
  let sliderColor = if gui.activeItem == id: RED
  elif inside and gui.activeItem <= 0: gray(0.35)
  else: gray(0.25)

  vg.beginPath()
  vg.roundedRect(x + SliderPad, newPosY,
                 w - SliderPad*2, y + h - newPosY - SliderPad, 5)
  vg.fillColor(sliderColor)
  vg.fill()

  if inside:
    handleTooltipInsideWidget(id, tooltipText)

# }}}

# {{{ createWindow

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

# }}}
# {{{ loadData

proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add font italic.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add font italic.\n"

# }}}
# {{{ main

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
  var
    scrollbarVal1 = 30.0
    scrollbarVal2 = 0.0
    scrollbarVal3 = 50.0
    scrollbarVal4 = 0.0
    scrollbarVal5 = 50.0

    sliderVal1 = 50.0
    sliderVal2 = -20.0
    sliderVal3 = 30.0
    sliderVal4 = -20.0

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

    # Buttons

    y += pad
    if doButton(vg, 2, x, y, w, h, "Start", color = gray(0.60), "I am the first!"):
      echo "button 1 pressed"

    y += pad
#    if doButton(vg, 3, x, y, w, h, "Stop", color = gray(0.60), "Middle one..."):
#      echo "button 2 pressed"

    y += pad
    if doButton(vg, 4, x, y, w, h, "Preferences", color = gray(0.60), "Last button"):
      echo "button 3 pressed"

    # Scrollbars

    y += pad * 2
    scrollbarVal1 = doHorizScrollbar(
      vg, 5, x, y, w * 1.5, h, scrollbarVal1,
      startVal = 0, endVal = 100, thumbSize = 20, clickStep = 10.0,
      tooltipText = "Horizontal Scrollbar 1")

    y += pad
    scrollbarVal2 = doHorizScrollbar(
      vg, 6, x, y, w * 1.5, h, scrollbarVal2,
      startVal = 0, endVal = 1, thumbSize = -1, clickStep = -1,
      tooltipText = "Horizontal Scrollbar 2")

    scrollbarVal3 = doVertScrollbar(
      vg, 7, 320, 60, h, 140, scrollbarVal3,
      startVal = 0.0, endVal = 100, thumbSize = 20, clickStep = 10,
      tooltipText = "Vertical Scrollbar 1")

    scrollbarVal4 = doVertScrollbar(
      vg, 8, 350, 60, h, 140, scrollbarVal4,
      startVal = 1, endVal = 0, thumbSize = -1, clickStep = -1,
      tooltipText = "Vertical Scrollbar 2")

    y += pad
    scrollbarVal5 = doHorizScrollbar(
      vg, 9, x, y, w * 1.5, h, scrollbarVal5,
      startVal = 100, endVal = 0, thumbSize = 20, clickStep = 10.0,
      tooltipText = "Horizontal Scrollbar 3")

    # Sliders

    y += pad * 2
    sliderVal1 = doHorizSlider(
      vg, 10, x, y, w * 1.5, h, sliderVal1,
      startVal = 0, endVal = 100, tooltipText = "Horizontal Slider 1")

    y += pad
    sliderVal2 = doHorizSlider(
      vg, 11, x, y, w * 1.5, h, sliderVal2,
      startVal = 50, endVal = -30, tooltipText = "Horizontal Slider 2")

    sliderVal3 = doVertSlider(
      vg, 12, 320, 300, h, 120, sliderVal3,
      startVal = 0, endVal = 100, tooltipText = "Vertical Slider 1")

    renderLabel(vg, 13, 320, 430, w, h, fmt"{sliderVal3:.3f}",
                color = gray(0.90), fontSize = 19.0)

    sliderVal4 = doVertSlider(
      vg, 14, 400, 300, h, 120, sliderVal4,
      startVal = 50, endVal = -30, tooltipText = "Vertical Slider 2")

    renderLabel(vg, 15, 400, 430, w, h, fmt"{sliderVal4:.3f}",
                color = gray(0.90), fontSize = 19.0)
    ############################################################

    uiStatePost(vg)

    vg.endFrame()

    glfw.swapBuffers(win)
    glfw.pollEvents()


  nvgDeinit(vg)

  glfw.terminate()

# }}}


main()

# vim: et:ts=2:sw=2:fdm=marker
