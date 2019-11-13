import math, strformat

import glad/gl
import glfw
import nanovg


# {{{ Configuration

const
  TooltipShowDelay       = 0.5
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 0.3

  ScrollBarFineDragDivisor         = 10.0
  ScrollBarUltraFineDragDivisor    = 100.0
  ScrollBarTrackClickRepeatDelay   = 0.3
  ScrollBarTrackClickRepeatTimeout = 0.05

  SliderFineDragDivisor      = 10.0
  SliderUltraFineDragDivisor = 100.0

# }}}

# {{{ Types

type TooltipState = enum
  tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

type ScrollBarState = enum
  sbsDefault,
  sbsDragNormal,
  sbsDragHidden,
  sbsTrackClickFirst,
  sbsTrackClickDelay,
  sbsTrackClickRepeat

type SliderState = enum
  ssDefault,
  ssDragHidden

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
  lastHotItem:    int

  # General purpose widget states
  x0, y0:         float   # for relative mouse movement calculations
  t0:             float   # for timeouts
  dragX, dragY:   float   # for keeping track of the cursor in hidden drag mode

  # Widget-specific states
  scrollBarState:    ScrollBarState
  scrollBarClickDir: float

  sliderState:       SliderState

  # Internal tooltip state
  tooltipState:      TooltipState
  lastTooltipState:  TooltipState
  tooltipT0:         float
  tooltipText:       string

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

let
  RED = rgb(1.0, 0.4, 0.4)
  GRAY_MID  = gray(0.6)
  GRAY_HI   = gray(0.8)
  GRAY_LO   = gray(0.25)
  GRAY_LOHI = gray(0.35)

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
# {{{ Tooltip
# {{{ handleTooltipInsideWidget

proc handleTooltipInsideWidget(id: int, tooltipText: string) =
  gui.tooltipState = gui.lastTooltipState

  # Reset the tooltip show delay if the cursor has been moved inside a
  # widget
  if gui.tooltipState == tsShowDelay:
    let cursorMoved = gui.mx != gui.lastmx or gui.my != gui.lastmy
    if cursorMoved:
      gui.tooltipT0 = getTime()

  # Hide the tooltip immediately if the LMB is pressed inside the widget
  if gui.mbLeftDown and gui.activeItem > 0:
    gui.tooltipState = tsOff

  # Start the show delay if we just entered the widget with LMB up and no
  # other tooltip is being shown
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
# {{{ drawTooltip

proc drawTooltip(vg: NVGContext, x, y: float, text: string,
                 alpha: float = 1.0) =
  # TODO should moved to the drawing section once deferred drawing is
  # implemented
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
# {{{ tooltipPost

proc tooltipPost(vg: NVGContext) =
  # TODO the actual drawing should be moved out of here once deferred drawing
  # is implemented
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
  # tooltip is being shown; this is to handle the case when the user just
  # moved the cursor outside of a widget. The actual widgets are responsible
  # for "keeping the state alive" every frame if the widget is hot/active by
  # restoring the tooltip state from lastTooltipState.
  gui.lastTooltipState = gui.tooltipState

  if gui.tooltipState == tsShowDelay:
    gui.tooltipState = tsOff
  elif gui.tooltipState == tsShow:
    gui.tooltipState = tsFadeOutDelay
    gui.tooltipT0 = getTime()

# }}}
# }}}
# {{{ uiStatePre

proc uiStatePre() =
  gui.hotItem = 0

  gui.lastmx = gui.mx
  gui.lastmy = gui.my

  (gui.mx, gui.my) = glfw.currentContext().cursorPos()


# }}}
# {{{ uiStatePost

proc scrollBarPost
proc sliderPost

proc uiStatePost(vg: NVGContext) =
  echo fmt"hotItem: {gui.hotItem}, activeItem: {gui.activeItem}, scrollBarState: {gui.scrollBarState}"

  tooltipPost(vg)

  gui.lastHotItem = gui.hotItem

  # Widget specific postprocessing
  #
  # NOTE: These must be called before the "Active state reset" section below
  # as they usually depend on the pre-reset value of the activeItem!
  scrollBarPost()
  sliderPost()

  # Active state reset
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

# }}}

# {{{ doButton

proc doButton(vg: NVGContext, id: int, x, y, w, h: float, label: string,
                  color: Color, tooltipText: string = ""): bool =

  # Hit testing
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  if not gui.mbLeftDown and isHotAndActive(id):
    result = true

  # Draw button
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: RED
    else:        color

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
# {{{ doCheckBox
#
proc doCheckBox(vg: NVGContext, id: int, x, y, w: float, state: bool,
                tooltipText: string = ""): bool =

  # Hit testing
  if mouseInside(x, y, w, w):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  if not gui.mbLeftDown and isHotAndActive(id):
    result = true

  # Draw check box
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: RED
    else:        GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, w, 5)
  vg.fillColor(fillColor)
  vg.fill()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ ScrollBar
# {{{ doHorizScrollBar

# Must be kept in sync with doVertScrollBar!
proc doHorizScrollBar(vg: NVGContext, id: int, x, y, w, h: float, value: float,
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

  # Hit testing
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  let insideThumb = mouseInside(thumbX, y, thumbW, h)

  # New thumb position & value calculation
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
    min(max(newValue + gui.scrollBarClickDir * clickStep, s), e)

  if isActive(id):
    case gui.scrollBarState
    of sbsDefault:
      if insideThumb:
        gui.x0 = gui.mx
        if gui.shiftDown:
          disableCursor()
          gui.scrollBarState = sbsDragHidden
        else:
          gui.scrollBarState = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if gui.mx < thumbX: gui.scrollBarClickDir = -1 * s
        else:               gui.scrollBarClickDir =  1 * s
        gui.scrollBarState = sbsTrackClickFirst
        gui.t0 = getTime()

    of sbsDragNormal:
      if gui.shiftDown:
        disableCursor()
        gui.scrollBarState = sbsDragHidden
      else:
        let dx = gui.mx - gui.x0

        newThumbX = min(max(thumbX + dx, thumbMinX), thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = min(max(gui.mx, thumbMinX), thumbMaxX + thumbW)

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if gui.shiftDown:
        let d = if gui.altDown: ScrollBarUltraFineDragDivisor
                else:           ScrollBarFineDragDivisor
        let dx = (gui.mx - gui.x0) / d

        newThumbX = min(max(thumbX + dx, thumbMinX), thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = gui.mx
        gui.dragX = newThumbX + thumbW*0.5
        gui.dragY = -1.0
      else:
        gui.scrollBarState = sbsDragNormal
        enableCursor()
        setCursorPosX(gui.dragX)
        gui.mx = gui.dragX
        gui.x0 = gui.dragX

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbX = calcThumbX(newValue)

      gui.scrollBarState = sbsTrackClickDelay
      gui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - gui.t0 > ScrollBarTrackClickRepeatDelay:
        gui.scrollBarState = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - gui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbX = calcThumbX(newValue)

          if gui.scrollBarClickDir * sgn(endVal - startVal).float > 0:
            if newThumbX + thumbW > gui.mx:
              newThumbX = thumbX
              newValue = value
          else:
            if newThumbX < gui.mx:
              newThumbX = thumbX
              newValue = value

          gui.t0 = getTime()
      else:
        gui.t0 = getTime()

  result = newValue

  # Draw slider
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let trackColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(trackColor)
  vg.fill()

  # Draw thumb
  let thumbColor = case drawState
    of dsHover: GRAY_LOHI
    of dsActive:
      if gui.scrollBarState < sbsTrackClickFirst: RED
      else: GRAY_LO
    else:   GRAY_LO

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
# {{{ doVertScrollBar

# Must be kept in sync with doHorizScrollBar!
proc doVertScrollBar(vg: NVGContext, id: int, x, y, w, h: float, value: float,
                     startVal: float = 0.0, endVal: float = 1.0,
                     thumbSize: float = -1.0, clickStep: float = -1.0,
                     tooltipText: string = ""): float =

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  assert thumbSize < 0.0 or thumbSize < abs(startVal - endVal)
  assert clickStep < 0.0 or clickStep < abs(startVal - endVal)

  const
    ThumbPad = 3
    ThumbMinH = 10

  # Calculate current thumb position
  let
    thumbSize = if thumbSize < 0: 0.000001 else: thumbSize
    thumbW = w - ThumbPad * 2
    thumbH = max((h - ThumbPad*2) / (abs(startVal - endVal) / thumbSize),
                 ThumbMinH)
    thumbMinY = y + ThumbPad
    thumbMaxY = y + h - ThumbPad - thumbH

  proc calcThumbY(val: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(thumbMinY, thumbMaxY, t)

  let thumbY = calcThumbY(value)

  # Hit testing
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  let insideThumb = mouseInside(x, thumbY, w, thumbH)

  # New thumb position & value calculation
  var
    newThumbY = thumbY
    newValue = value

  proc calcNewValue(newThumbY: float): float =
    let t = invLerp(thumbMinY, thumbMaxY, newThumbY)
    lerp(startVal, endVal, t)

  proc calcNewValueTrackClick(): float =
    let clickStep = if clickStep < 0: abs(startVal - endVal) * 0.1
                    else: clickStep

    let (s, e) = if startVal < endVal: (startVal, endVal)
                 else: (endVal, startVal)
    min(max(newValue + gui.scrollBarClickDir * clickStep, s), e)

  if isActive(id):
    case gui.scrollBarState
    of sbsDefault:
      if insideThumb:
        gui.y0 = gui.my
        if gui.shiftDown:
          disableCursor()
          gui.scrollBarState = sbsDragHidden
        else:
          gui.scrollBarState = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if gui.my < thumbY: gui.scrollBarClickDir = -1 * s
        else:               gui.scrollBarClickDir =  1 * s
        gui.scrollBarState = sbsTrackClickFirst
        gui.t0 = getTime()

    of sbsDragNormal:
      if gui.shiftDown:
        disableCursor()
        gui.scrollBarState = sbsDragHidden
      else:
        let dy = gui.my - gui.y0

        newThumbY = min(max(thumbY + dy, thumbMinY), thumbMaxY)
        newValue = calcNewValue(newThumbY)

        gui.y0 = min(max(gui.my, thumbMinY), thumbMaxY + thumbH)

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if gui.shiftDown:
        let d = if gui.altDown: ScrollBarUltraFineDragDivisor
                else:           ScrollBarFineDragDivisor
        let dy = (gui.my - gui.y0) / d

        newThumbY = min(max(thumbY + dy, thumbMinY), thumbMaxY)
        newValue = calcNewValue(newThumbY)

        gui.y0 = gui.my
        gui.dragX = -1.0
        gui.dragY = newThumbY + thumbH*0.5
      else:
        gui.scrollBarState = sbsDragNormal
        enableCursor()
        setCursorPosY(gui.dragY)
        gui.my = gui.dragY
        gui.y0 = gui.dragY

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbY = calcThumbY(newValue)

      gui.scrollBarState = sbsTrackClickDelay
      gui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - gui.t0 > ScrollBarTrackClickRepeatDelay:
        gui.scrollBarState = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - gui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbY = calcThumbY(newValue)

          if gui.scrollBarClickDir * sgn(endVal - startVal).float > 0:
            if newThumbY + thumbH > gui.my:
              newThumbY = thumbY
              newValue = value
          else:
            if newThumbY < gui.my:
              newThumbY = thumbY
              newValue = value

          gui.t0 = getTime()
      else:
        gui.t0 = getTime()

  result = newValue

  # Draw slider
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let trackColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(trackColor)
  vg.fill()

  # Draw thumb
  let thumbColor = case drawState
    of dsHover: GRAY_LOHI
    of dsActive:
      if gui.scrollBarState < sbsTrackClickFirst: RED
      else: GRAY_LO
    else:   GRAY_LO

  vg.beginPath()
  vg.roundedRect(x + ThumbPad, newThumbY, thumbW, thumbH, 5)
  vg.fillColor(thumbColor)
  vg.fill()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ scrollBarPost

proc scrollBarPost() =
  # Handle release active scrollbar outside of the widget
  if not gui.mbLeftDown and gui.activeItem != 0:
    case gui.scrollBarState:
    of sbsDragHidden:
      gui.scrollBarState = sbsDefault
      enableCursor()
      if gui.dragX > -1.0:
        setCursorPosX(gui.dragX)
      else:
        setCursorPosY(gui.dragY)

    else: gui.scrollBarState = sbsDefault

# }}}
# }}}
# {{{ Slider
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
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # New position & value calculation
  var
    newPosX = posX
    newValue = value

  if isActive(id):
    case gui.sliderState:
    of ssDefault:
      gui.x0 = gui.mx
      gui.dragX = gui.mx
      gui.dragY = -1.0
      disableCursor()
      gui.sliderState = ssDragHidden

    of ssDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      let d = if gui.shiftDown:
        if gui.altDown: SliderUltraFineDragDivisor
        else:           SliderFineDragDivisor
      else: 1

      let dx = (gui.mx - gui.x0) / d

      newPosX = min(max(posX + dx, posMinX), posMaxX)
      let t = invLerp(posMinX, posMaxX, newPosX)
      newValue = lerp(startVal, endVal, t)
      gui.x0 = gui.mx

  result = newValue

  # Draw slider track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover: GRAY_HI
    else:       GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw slider
  let sliderColor = case drawState
    of dsHover:  GRAY_LOHI
    of dsActive: RED
    else:        GRAY_LO

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

  if isHot(id):
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
  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # New position & value calculation
  var
    newPosY = posY
    newValue = value

  if isActive(id):
    case gui.sliderState:
    of ssDefault:
      gui.y0 = gui.my
      gui.dragX = -1.0
      gui.dragY = gui.my
      disableCursor()
      gui.sliderState = ssDragHidden

    of ssDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      let d = if gui.shiftDown:
        if gui.altDown: SliderUltraFineDragDivisor
        else:           SliderFineDragDivisor
      else: 1

      let dy = (gui.my - gui.y0) / d

      newPosY = min(max(posY + dy, posMaxY), posMinY)
      let t = invLerp(posMinY, posMaxY, newPosY)
      newValue = lerp(startVal, endVal, t)
      gui.y0 = gui.my

  result = newValue

  # Draw slider track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover: GRAY_HI
    else:       GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Draw slider
  let sliderColor = case drawState
    of dsHover:  GRAY_LOHI
    of dsActive: RED
    else:        GRAY_LO

  vg.beginPath()
#  vg.roundedRect(x + SliderPad, y + SliderPad,
#                 newPosX - x - SliderPad, h - SliderPad*2, 5)
  vg.roundedRect(x + SliderPad, newPosY,
                 w - SliderPad*2, y + h - newPosY - SliderPad, 5)
  vg.fillColor(sliderColor)
  vg.fill()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltipText)

# }}}
# {{{ sliderPost

proc sliderPost() =
  # Handle release active slider outside of the widget
  if not gui.mbLeftDown and gui.activeItem != 0:
    case gui.sliderState:
    of ssDragHidden:
      gui.sliderState = ssDefault
      enableCursor()
      if gui.dragX > -1.0:
        setCursorPosX(gui.dragX)
      else:
        setCursorPosY(gui.dragY)

    else: gui.sliderState = ssDefault

# }}}
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
    scrollBarVal1 = 30.0
    scrollBarVal2 = 0.0
    scrollBarVal3 = 50.0
    scrollBarVal4 = 0.0
    scrollBarVal5 = 50.0

    sliderVal1 = 50.0
    sliderVal2 = -20.0
    sliderVal3 = 30.0
    sliderVal4 = -20.0

    checkBoxVal1 = false
    checkBoxVal2 = true

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
    if doButton(vg, 2, x, y, w, h, "Start", color = GRAY_MID, "I am the first!"):
      echo "button 1 pressed"

    y += pad
    if doButton(vg, 3, x, y, w, h, "Stop", color = GRAY_MID, "Middle one..."):
      echo "button 2 pressed"

    y += pad
    if doButton(vg, 4, x, y, w, h, "Preferences", color = GRAY_MID, "Last button"):
      echo "button 3 pressed"

    # ScrollBars

    y += pad * 2
    scrollBarVal1 = doHorizScrollBar(
      vg, 5, x, y, w * 1.5, h, scrollBarVal1,
      startVal = 0, endVal = 100, thumbSize = 20, clickStep = 10.0,
      tooltipText = "Horizontal ScrollBar 1")

    y += pad
    scrollBarVal2 = doHorizScrollBar(
      vg, 6, x, y, w * 1.5, h, scrollBarVal2,
      startVal = 0, endVal = 1, thumbSize = -1, clickStep = -1,
      tooltipText = "Horizontal ScrollBar 2")

    scrollBarVal3 = doVertScrollBar(
      vg, 7, 320, 60, h, 140, scrollBarVal3,
      startVal = 0.0, endVal = 100, thumbSize = 20, clickStep = 10,
      tooltipText = "Vertical ScrollBar 1")

    scrollBarVal4 = doVertScrollBar(
      vg, 8, 350, 60, h, 140, scrollBarVal4,
      startVal = 1, endVal = 0, thumbSize = -1, clickStep = -1,
      tooltipText = "Vertical ScrollBar 2")

    y += pad
    scrollBarVal5 = doHorizScrollBar(
      vg, 9, x, y, w * 1.5, h, scrollBarVal5,
      startVal = 100, endVal = 0, thumbSize = 20, clickStep = 10.0,
      tooltipText = "Horizontal ScrollBar 3")

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

    # Checkboxes
    y += pad * 2

    checkBoxVal1 = doCheckBox(
      vg, 16, x, y, h, checkBoxVal1, tooltipText = "CheckBox 1")

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
