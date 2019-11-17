import math, strformat

import glfw
import nanovg
import xxhash


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

type DropdownState = enum
  dsClosed, dsOpenLMBPressed, dsOpen

type SliderState = enum
  ssDefault,
  ssDragHidden

type ScrollBarState = enum
  sbsDefault,
  sbsDragNormal,
  sbsDragHidden,
  sbsTrackClickFirst,
  sbsTrackClickDelay,
  sbsTrackClickRepeat

type TooltipState = enum
  tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

type GuiState = object
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
  hotItem:        int64
  activeItem:     int64
  lastHotItem:    int64

  # General purpose widget states
  x0, y0:         float   # for relative mouse movement calculations
  t0:             float   # for timeouts
  dragX, dragY:   float   # for keeping track of the cursor in hidden drag mode

  # Widget-specific states
  radioButtonsActiveButton: int

  dropdownState:     DropdownState
  dropdownActive:    int64

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

template generateId(filename: string, line: int, id: string): int64 =
  let
    hash32 = XXH32(filename & $line & id)

  # Make sure the IDs are always positive integers
  int64(hash32) - int32.low + 1


proc lerp*(a, b, t: float): float =
  a + (b - a) * t

proc invLerp*(a, b, v: float): float =
  (v - a) / (b - a)


proc disableCursor*() =
  glfw.currentContext().cursorMode = cmDisabled

proc enableCursor*() =
  glfw.currentContext().cursorMode = cmNormal

proc setCursorPosX*(x: float) =
  let win = glfw.currentContext()
  let (_, currY) = win.cursorPos()
  win.cursorPos = (x, currY)

proc setCursorPosY*(y: float) =
  let win = glfw.currentContext()
  let (currX, _) = win.cursorPos()
  win.cursorPos = (currX, y)

proc truncate(vg: NVGContext, text: string, maxWidth: float): string =
  result = text # TODO

# }}}
# {{{ Globals

var
  gui: GuiState
  vg:  NVGContext

template isHot(id: int64): bool =
  gui.hotItem == id

template setHot(id: int64) =
  gui.hotItem = id

template isActive(id: int64): bool =
  gui.activeItem == id

template setActive(id: int64) =
  gui.activeItem = id

template isHotAndActive(id: int64): bool =
  isHot(id) and isActive(id)

template noActiveItem(): bool =
  gui.activeItem == 0

let
  RED* = rgb(1.0, 0.4, 0.4)
  GRAY_MID*  = gray(0.6)
  GRAY_HI*   = gray(0.8)
  GRAY_LO*   = gray(0.25)
  GRAY_LOHI* = gray(0.35)

# }}}
# {{{ Callbacks

proc keyCb*(win: Window, key: Key, scanCode: int32, action: KeyAction,
            modKeys: set[ModifierKey]) =

  if action == kaDown:
    case key
    of keyEscape: win.shouldClose = true
    else: discard

# }}}

# {{{ mouseInside

proc mouseInside(x, y, w, h: float): bool =
  gui.mx >= x and gui.mx <= x+w and
  gui.my >= y and gui.my <= y+h

# }}}
# {{{ Tooltip
# {{{ handleTooltipInsideWidget

proc handleTooltipInsideWidget(id: int64, tooltip: string) =
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
    gui.tooltipText = tooltip

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

# {{{ setNvgContext()

proc setNvgContext*(nvg: NVGContext) =
  vg = nvg

# }}}
# {{{ beginFrame()

proc beginFrame*() =
  let win = glfw.currentContext()

  gui.lastmx = gui.mx
  gui.lastmy = gui.my

  (gui.mx, gui.my) = win.cursorPos()

  gui.mbLeftDown  = win.mouseButtonDown(mb1)
  gui.mbRightDown = win.mouseButtonDown(mb2)
  gui.mbMidDown   = win.mouseButtonDown(mb3)

  gui.shiftDown  = win.isKeyDown(keyLeftShift) or
                   win.isKeyDown(keyRightShift)

  gui.ctrlDown   = win.isKeyDown(keyLeftControl) or
                   win.isKeyDown(keyRightControl)

  gui.altDown    = win.isKeyDown(keyLeftAlt) or
                   win.isKeyDown(keyRightAlt)

  gui.superDown  = win.isKeyDown(keyLeftSuper) or
                   win.isKeyDown(keyRightSuper)

  gui.hotItem = 0

# }}}
# {{{ endFrame

proc scrollBarPost
proc sliderPost

proc endFrame*() =
#  echo fmt"hotItem: {gui.hotItem}, activeItem: {gui.activeItem}, scrollBarState: {gui.scrollBarState}"

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

# {{{ label
proc textLabel(id:         int64,
               x, y, w, h: float,
               label:      string,
               color:      Color,
               fontSize:   float = 19.0,
               fontFace:   string = "sans-bold") =

  vg.fontSize(fontSize)
  vg.fontFace(fontFace)
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(color)
#  let tw = vg.horizontalAdvance(0,0, label)
  discard vg.text(x, y+h*0.5, label)


template label*(x, y, w, h: float,
                label:      string,
                color:      Color,
                fontSize:   float = 19.0,
                fontFace:   string = "sans-bold") =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  textLabel(id, x, y, w, h, label, color, fontSize, fontFace)

# }}}
# {{{ button

proc button(id:         int64,
            x, y, w, h: float,
            label:      string,
            color:      Color,
            tooltip:    string = ""): bool =

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
  vg.fillColor(GRAY_LO)
  let tw = vg.horizontalAdvance(0,0, label)
  discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, label)

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template button*(x, y, w, h: float,
                 label:      string,
                 color:      Color,
                 tooltip:    string = ""): bool =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  button(id, x, y, w, h, label, color, tooltip)

# }}}
# {{{ checkBox

proc checkBox(id:      int64,
              x, y, w: float,
              tooltip: string = "",
              active:  bool): bool =

  const
    CheckPad = 3

  # Hit testing
  if mouseInside(x, y, w, w):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)

  # TODO SweepCheckBox could be introduced later

  # LMB released over active widget means it was clicked
  let active = if not gui.mbLeftDown and isHotAndActive(id): not active
               else: active

  result = active

  # Draw check box
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  # Draw background
  let bgColor = case drawState
    of dsHover, dsActive: GRAY_HI
    else:                 GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, w, 5)
  vg.fillColor(bgColor)
  vg.fill()

  # Draw check mark
  let checkColor = case drawState
    of dsHover:
      if active: white() else: GRAY_LOHI
    of dsActive: RED
    else:
      if active: GRAY_LO else: GRAY_HI

  let w = w - CheckPad*2
  vg.beginPath()
  vg.roundedRect(x + CheckPad, y + CheckPad, w, w, 5)
  vg.fillColor(checkColor)
  vg.fill()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template checkBox*(x, y, w: float,
                   tooltip: string = "",
                   active:  bool): bool =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  checkbox(id, x, y, w, tooltip, active)

# }}}
# {{{ radioButtons

proc radioButtons(id:           int64,
                  x, y, w, h:   float,
                  labels:       openArray[string],
                  tooltips:     openArray[string] = @[],
                  activeButton: Natural): Natural =

  assert activeButton >= 0 and activeButton <= labels.high
  assert tooltips.len == 0 or tooltips.len == labels.len

  let
    numButtons = labels.len
    buttonW = w / numButtons.float

  # Hit testing
  let hotButton = min(int(floor((gui.mx - x) / buttonW)), numButtons-1)

  if mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)
      gui.radioButtonsActiveButton = hotButton

  # LMB released over active widget means it was clicked
  if not gui.mbLeftDown and isHotAndActive(id) and
     gui.radioButtonsActiveButton == hotButton:
    result = hotButton
  else:
    result = activeButton

  # Draw radio buttons
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  var x = x
  const PadX = 2

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)

  for i, label in labels:
    let fillColor = if   drawState == dsHover  and hotButton == i: GRAY_HI
                    elif drawState == dsActive and hotButton == i and
                         gui.radioButtonsActiveButton == i: RED
                    else:
                      if activeButton == i: GRAY_LO else : GRAY_MID

    vg.beginPath()
    vg.rect(x, y, buttonW - PadX, h)
    vg.fillColor(fillColor)
    vg.fill()

    let
      label = truncate(vg, label, buttonW)
      textColor = if drawState == dsHover and hotButton == i: GRAY_LO
                  else:
                    if activeButton == i: GRAY_HI
                    else: GRAY_LO

    vg.fillColor(textColor)
    let tw = vg.horizontalAdvance(0,0, label)
    discard vg.text(x + buttonW*0.5 - tw*0.5, y+h*0.5, label)

    x += buttonW

  if isHot(id):
    handleTooltipInsideWidget(id, tooltips[hotButton])


template radioButtons*(x, y, w, h:   float,
                       labels:       openArray[string],
                       tooltips:     openArray[string] = @[],
                       activeButton: Natural): Natural =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  radioButtons(id, x, y, w, h, labels, tooltips, activeButton)

# }}}
# {{{ dropdown

proc dropdown(id:           int64,
              x, y, w, h:   float,
              items:        openArray[string],
              tooltip:      string = "",
              selectedItem: Natural): Natural =

  assert items.len > 0
  assert selectedItem <= items.high

  const BoxPad = 7

  var
    boxX, boxY, boxW, boxH: float
    hoverItem = -1

  let
    numItems = items.len
    itemHeight = h  # TODO just temporarily


  result = selectedItem

  if gui.dropdownState == dsClosed:
    if mouseInside(x, y, w, h):
      setHot(id)
      if gui.mbLeftDown and noActiveItem():
        setActive(id)
        gui.dropdownState = dsOpenLMBPressed
        gui.dropdownActive = id

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if gui.dropdownActive == id and gui.dropdownState >= dsOpenLMBPressed:

    # Calculate the position of the box around the dropdown items
    var maxItemWidth = 0.0
    for i in items:
      let tw = vg.horizontalAdvance(0, 0, i)
      maxItemWidth = max(tw, maxItemWidth)

    boxX = x
    boxY = y + h
    boxW = max(maxItemWidth + BoxPad*2, w)
    boxH = float(items.len) * itemHeight + BoxPad*2

    # Hit testing
    let
      insideButton = mouseInside(x, y, w, h)
      insideBox = mouseInside(boxX, boxY, boxW, boxH)

    if insideButton or insideBox:
      setHot(id)
      setActive(id)
    else:
      gui.dropdownState = dsClosed
      gui.dropdownActive = 0

    hoverItem = min(int(floor((gui.my - boxY - BoxPad) / itemHeight)),
                    numItems-1)

    # LMB released inside the box selects the item under the cursor and closes
    # the dropdown
    if gui.dropdownState == dsOpenLMBPressed:
      if not gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          gui.dropdownState = dsClosed
          gui.dropdownActive = 0
        else:
          gui.dropdownState = dsOpen
    else:
      if gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          gui.dropdownState = dsClosed
          gui.dropdownActive = 0

        elif insideButton:
          gui.dropdownState = dsClosed
          gui.dropdownActive = 0

  # Draw button
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  const ItemXPad = 7
  let itemText = items[selectedItem]

  let textColor = case drawState
    of dsHover:  GRAY_LO
    of dsActive: GRAY_LO
    else:        GRAY_LO

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(textColor)
  discard vg.text(x + ItemXPad, y+h*0.5, itemText)

  # Draw item list box
  vg.beginPath()
  vg.roundedRect(boxX, boxY, boxW, boxH, 5)
  vg.fillColor(GRAY_LO)
  vg.fill()

  # Draw items
  if isActive(id) and gui.dropdownState >= dsOpenLMBPressed:
    vg.fontSize(19.0)
    vg.fontFace("sans-bold")
    vg.textAlign(haLeft, vaMiddle)
    vg.fillColor(GRAY_HI)

    var
      ix = boxX + BoxPad
      iy = boxY + BoxPad

    for i, item in items.pairs:
      var textColor = GRAY_HI
      if i == hoverItem:
        vg.beginPath()
        vg.rect(boxX, iy, boxW, h)
        vg.fillColor(RED)
        vg.fill()
        textColor = GRAY_LO

      vg.fillColor(textColor)
      discard vg.text(ix, iy + h*0.5, item)
      iy += itemHeight

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template dropdown*(x, y, w, h:   float,
                   items:        openArray[string],
                   tooltip:      string = "",
                   selectedItem: Natural): Natural =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  dropdown(id, x, y, w, h, items, tooltip, selectedItem)

# }}}
# {{{ ScrollBar
# {{{ horizScrollBar

# Must be kept in sync with vertScrollBar!
proc horizScrollBar(id:         int64,
                    x, y, w, h: float,
                    startVal:   float =  0.0,
                    endVal:     float =  1.0,
                    thumbSize:  float = -1.0,
                    clickStep:  float = -1.0,
                    tooltip:    string = "",
                    value:      float): float =

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

  # Draw track
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
    handleTooltipInsideWidget(id, tooltip)


template horizScrollBar*(x, y, w, h: float,
                         startVal:  float =  0.0,
                         endVal:    float =  1.0,
                         thumbSize: float = -1.0,
                         clickStep: float = -1.0,
                         tooltip:   string = "",
                         value:     float): float =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  horizScrollBar(id,
                 x, y, w, h,
                 startVal, endVal, thumbSize, clickStep, tooltip,
                 value)

# }}}
# {{{ vertScrollBar

# Must be kept in sync with horizScrollBar!
proc vertScrollBar(id:         int64,
                   x, y, w, h: float,
                   startVal:   float =  0.0,
                   endVal:     float =  1.0,
                   thumbSize:  float = -1.0,
                   clickStep:  float = -1.0,
                   tooltip:    string = "",
                   value:      float): float =

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

  # Draw track
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
    handleTooltipInsideWidget(id, tooltip)


template vertScrollBar*(x, y, w, h: float,
                        startVal:   float =  0.0,
                        endVal:     float =  1.0,
                        thumbSize:  float = -1.0,
                        clickStep:  float = -1.0,
                        tooltip:    string = "",
                        value:      float): float =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  vertScrollBar(id,
                x, y, w, h,
                startVal, endVal, thumbSize, clickStep, tooltip,
                value)

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
# {{{ horizSlider

proc horizSlider(id:         int64,
                 x, y, w, h: float,
                 startVal:   float = 0.0,
                 endVal:     float = 1.0,
                 tooltip:    string = "",
                 value:      float): float =

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
    handleTooltipInsideWidget(id, tooltip)


template horizSlider*(x, y, w, h: float,
                      startVal:   float = 0.0,
                      endVal:     float = 1.0,
                      tooltip:    string = "",
                      value:      float): float =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  horizSlider(id,
              x, y, w, h, startVal, endVal, tooltip,
              value)

# }}}
# {{{ vertSlider

proc vertSlider(id:         int64,
                x, y, w, h: float,
                startVal:   float = 0.0,
                endVal:     float = 1.0,
                tooltip:    string = "",
                value:      float): float =

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
  vg.roundedRect(x + SliderPad, newPosY,
                 w - SliderPad*2, y + h - newPosY - SliderPad, 5)
  vg.fillColor(sliderColor)
  vg.fill()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template vertSlider*(x, y, w, h: float,
                     startVal:   float = 0.0,
                     endVal:     float = 1.0,
                     tooltip:    string = "",
                     value:      float): float =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  vertSlider(id,
             x, y, w, h,
             startVal, endVal, tooltip,
             value)

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

# vim: et:ts=2:sw=2:fdm=marker
