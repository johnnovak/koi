import math, unicode, strformat

import glfw
import nanovg
import xxhash


# {{{ Types

type ItemId = int64

type
  DropdownState = enum
    dsClosed, dsOpenLMBPressed, dsOpen

  SliderState = enum
    ssDefault,
    ssDragHidden

  ScrollBarState = enum
    sbsDefault,
    sbsDragNormal,
    sbsDragHidden,
    sbsTrackClickFirst,
    sbsTrackClickDelay,
    sbsTrackClickRepeat

  TextFieldState = enum
    tfDefault, tfEditLMBPressed, tfEdit

  TooltipState = enum
    tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut


type GuiState = object
  # General state
  # *************

  # Set if a widget has captured the focus (e.g. a textfield in edit mode) so
  # all other UI interactions (hovers, tooltips, etc.) should be disabled.
  focusCaptured:  bool

  # Mouse state
  # -----------
  mx, my:         float

  # Mouse cursor position from the last frame.
  lastmx, lastmy: float

  mbLeftDown:     bool
  mbRightDown:    bool
  mbMiddleDown:   bool

  # Keyboard state
  # --------------
  shiftDown:      bool
  altDown:        bool
  ctrlDown:       bool
  superDown:      bool

  # Active & hot items
  # ------------------
  hotItem:        ItemId
  activeItem:     ItemId

  # Hot item from the last frame
  lastHotItem:    ItemId

  # General purpose widget states
  # -----------------------------
  # For relative mouse movement calculations
  x0, y0:         float

  # For delays & timeouts
  t0:             float

  # For keeping track of the cursor in hidden drag mode
  dragX, dragY:   float

  # Widget-specific states
  # **********************
  radioButtonsActiveButton: Natural

  # Dropdown
  # --------
  dropdownState:      DropdownState

  # Dropdown in open mode, 0 if no dropdown is open currently.
  dropdownActiveItem: ItemId

  # Slider
  # ------
  sliderState:        SliderState

  # Scroll bar
  # ----------
  scrollBarState:     ScrollBarState

  # Set when the LMB is pressed inside the scroll bar's track but outside of
  # the knob:
  # -1 = LMB pressed on the left side of the knob
  #  1 = LMB pressed on the right side of the knob
  scrollBarClickDir:  float

  # Text field
  # ----------
  textFieldState:           TextFieldState

  # Text field item in edit mode, 0 if no text field is being edited.
  textFieldActiveItem:      ItemId

  # The cursor is before the Rune with this index. If the cursor is at the end
  # of the text, the cursor pos equals the lenght of the text. From this
  # follow that the cursor position for an empty text is 0.
  textFieldCursorPos:       Natural

  # Index of the start Rune in the selection, -1 if nothing is selected.
  textFieldSelFirst:        int

  # Index of the last Rune in the selection.
  textFieldSelLast:         Natural

  # The text is displayed starting from the Rune with this index.
  textFieldDisplayStartPos: Natural
  textFieldDisplayStartX:   float

  # The original text is stored when going into edit mode so it can be
  # restored if the editing is cancelled.
  textFieldOriginalText:    string

  # Internal tooltip state
  # **********************
  tooltipState:     TooltipState
  lastTooltipState: TooltipState

  # Used for the various tooltip delays & timeouts.
  tooltipT0:        float
  tooltipText:      string

type DrawState = enum
  dsNormal, dsHover, dsActive

# }}}
# {{{ Globals

var
  gui {.threadvar.}: GuiState
  vg: NVGContext

var
  RED*       {.threadvar.}: Color
  GRAY_MID*  {.threadvar.}: Color
  GRAY_HI*   {.threadvar.}: Color
  GRAY_LO*   {.threadvar.}: Color
  GRAY_LOHI* {.threadvar.}: Color

# }}}
# {{{ Configuration

const
  TooltipShowDelay       = 0.5
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 5.3

  ScrollBarFineDragDivisor         = 10.0
  ScrollBarUltraFineDragDivisor    = 100.0
  ScrollBarTrackClickRepeatDelay   = 0.3
  ScrollBarTrackClickRepeatTimeout = 0.05

  SliderFineDragDivisor      = 10.0
  SliderUltraFineDragDivisor = 100.0

# }}}

# {{{ Utils

proc lerp*(a, b, t: float): float =
  a + (b - a) * t

proc invLerp*(a, b, v: float): float =
  (v - a) / (b - a)


proc disableCursor*() =
  var win = glfw.currentContext()
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


template `++`(s: string, offset: int): cstring =
  cast[cstring](cast[int](cstring(s)) + offset)

proc truncate(vg: NVGContext, text: string, maxWidth: float): string =
  result = text # TODO

# }}}
# {{{ UI helpers

template generateId(filename: string, line: int, id: string): ItemId =
  let
    hash32 = XXH32(filename & $line & id)

  # Make sure the IDs are always positive integers
  int64(hash32) - int32.low + 1


proc mouseInside(x, y, w, h: float): bool =
  gui.mx >= x and gui.mx <= x+w and
  gui.my >= y and gui.my <= y+h

template isHot(id: ItemId): bool =
  gui.hotItem == id

template setHot(id: ItemId) =
  gui.hotItem = id

template isActive(id: ItemId): bool =
  gui.activeItem == id

template setActive(id: ItemId) =
  gui.activeItem = id

template isHotAndActive(id: ItemId): bool =
  isHot(id) and isActive(id)

template noActiveItem(): bool =
  gui.activeItem == 0

# }}}
# {{{ Keyboard handling

# Helpers to map Ctrl consistently to Cmd on OS X
when defined(macosx):
  const CtrlModSet = {mkSuper}
  const CtrlMod    = mkSuper
else:
  const CtrlModSet = {mkCtrl}
  const CtrlMod    = mkCtrl

const CharBufSize = 200
var
  # TODO do we need locking around this stuff? written in the callback, read
  # from the UI code
  charBuf: array[CharBufSize, Rune]
  charBufIdx: Natural

proc charCb(win: Window, codePoint: Rune) =
  #echo fmt"Rune: {codePoint}"
  if charBufIdx <= charBuf.high:
    charBuf[charBufIdx] = codePoint
    inc(charBufIdx)

proc clearCharBuf() = charBufIdx = 0

proc charBufEmpty(): bool = charBufIdx == 0

proc consumeCharBuf(): string =
  for i in 0..<charBufIdx:
    result &= charBuf[i]
  clearCharBuf()


type KeyEvent = object
  key: Key
  mods: set[ModifierKey]

const KeyBufSize = 200
var
  # TODO do we need locking around this stuff? written in the callback, read
  # from the UI code
  keyBuf: array[KeyBufSize, KeyEvent]
  keyBufIdx: Natural

const EditKeys = {
  keyEscape, keyEnter, keyTab,
  keyBackspace, keyDelete,
  keyRight, keyLeft, keyDown, keyUp,
  keyPageUp, keyPageDown,
  keyHome, keyEnd
}

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           mods: set[ModifierKey]) =

  #echo fmt"Key: {key} (scan code: {scanCode}): {action} - {mods}"
  if key in EditKeys and action in {kaDown, kaRepeat}:
    if keyBufIdx <= keyBuf.high:
      keyBuf[keyBufIdx] = KeyEvent(key: key, mods: mods)
      inc(keyBufIdx)

proc clearKeyBuf() = keyBufIdx = 0

# }}}
# {{{ Tooltip handling
# {{{ handleTooltipInsideWidget

proc handleTooltipInsideWidget(id: ItemId, tooltip: string) =
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

# {{{ label
proc textLabel(id:         ItemId,
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

proc button(id:         ItemId,
            x, y, w, h: float,
            label:      string,
            color:      Color,
            tooltip:    string = ""): bool =

  # Hit testing
  if not gui.focusCaptured and mouseInside(x, y, w, h):
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

proc checkBox(id:      ItemId,
              x, y, w: float,
              tooltip: string = "",
              active:  bool): bool =

  const
    CheckPad = 3

  # Hit testing
  if not gui.focusCaptured and mouseInside(x, y, w, w):
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

proc radioButtons(id:           ItemId,
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

  if not gui.focusCaptured and mouseInside(x, y, w, h):
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

proc dropdown(id:           ItemId,
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
    if not gui.focusCaptured and mouseInside(x, y, w, h):
      setHot(id)
      if gui.mbLeftDown and noActiveItem():
        setActive(id)
        gui.dropdownState = dsOpenLMBPressed
        gui.dropdownActiveItem = id

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if gui.dropdownActiveItem == id and gui.dropdownState >= dsOpenLMBPressed:

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
      gui.dropdownActiveItem = 0

    hoverItem = min(int(floor((gui.my - boxY - BoxPad) / itemHeight)),
                    numItems-1)

    # LMB released inside the box selects the item under the cursor and closes
    # the dropdown
    if gui.dropdownState == dsOpenLMBPressed:
      if not gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          gui.dropdownState = dsClosed
          gui.dropdownActiveItem = 0
        else:
          gui.dropdownState = dsOpen
    else:
      if gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          gui.dropdownState = dsClosed
          gui.dropdownActiveItem = 0

        elif insideButton:
          gui.dropdownState = dsClosed
          gui.dropdownActiveItem = 0

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
# {{{ textField

proc textField(id:         ItemId,
               x, y, w, h: float,
               tooltip:    string = "",
               text:       string): string =

  var text = text

  # The text is displayed within this rectangle (used for drawing later)
  const
    PadX = 8
  let
    textBoxX = x + PadX
    textBoxW = w - PadX*2
    textBoxY = y
    textBoxH = h

  # TODO only calculate glyph positions if needed
  var glyphs: array[1000, GlyphPosition]  # TODO is this buffer large enough?
  discard vg.textGlyphPositions(0, 0, text, glyphs)

  if gui.textFieldState == tfDefault:
    # Hit testing
    if mouseInside(x, y, w, h):
      setHot(id)
      if gui.mbLeftDown and noActiveItem():
        setActive(id)
        clearCharBuf()
        clearKeyBuf()

        gui.textFieldState = tfEditLMBPressed
        gui.textFieldActiveItem = id
        gui.textFieldCursorPos = text.runeLen
        gui.textFieldSelFirst = -1
        gui.textFieldSelLast = 0
        gui.textFieldDisplayStartPos = 0
        gui.textFieldDisplayStartX = textBoxX
        gui.textFieldOriginalText = text
        gui.focusCaptured = true


  proc exitEditMode() =
    gui.textFieldState = tfDefault
    gui.textFieldActiveItem = 0
    gui.textFieldCursorPos = 0
    gui.textFieldSelFirst = -1
    gui.textFieldSelLast = 0
    gui.textFieldDisplayStartPos = 0
    gui.textFieldDisplayStartX = textBoxX
    gui.textFieldOriginalText = ""
    gui.focusCaptured = false
    clearKeyBuf()
    clearCharBuf()

  # We 'fall through' to the edit state to avoid a 1-frame delay when going
  # into edit mode
  if gui.textFieldActiveItem == id and gui.textFieldState >= tfEditLMBPressed:
    setHot(id)
    setActive(id)

    if gui.textFieldState == tfEditLMBPressed:
      if not gui.mbLeftDown:
        gui.textFieldState = tfEdit
    else:
      # LMB pressed outside the text field exits edit mode
      if gui.mbLeftDown and not mouseInside(x, y, w, h):
        exitEditMode()

    # Handle text field shortcuts
    # (If we exited edit mode above key handler, this will result in a noop as
    # exitEditMode() clears the key buffer.)
    for i in 0..<keyBufIdx:
      let k = keyBuf[i]

      # TODO OS specific shortcuts

      if k.key == keyEscape:   # Cancel edits
        text = gui.textFieldOriginalText
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

      elif k.key == keyEnter:  # Persist edits
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

      elif k.key == keyTab: discard

      elif k.key == keyBackspace:
        if gui.textFieldCursorPos > 0:
          if k.mods == CtrlModSet:
            text = ""
            gui.textFieldCursorPos = 0
          else:
            text = text.runeSubStr(0, gui.textFieldCursorPos - 1) &
                   text.runeSubStr(gui.textFieldCursorPos)
            dec(gui.textFieldCursorPos)

      elif k.key == keyDelete:
        text = text.runeSubStr(0, gui.textFieldCursorPos) &
               text.runeSubStr(gui.textFieldCursorPos + 1)

      elif k.key in {keyHome, keyUp} or
           k.key == keyLeft and k.mods == CtrlModSet:   # TODO allow alt?
        gui.textFieldCursorPos = 0

      elif k.key in {keyEnd, keyDown} or
           k.key == keyRight and k.mods == CtrlModSet:  # TODO allow alt?
        gui.textFieldCursorPos = text.runeLen

      elif k.key == keyRight:
        if k.mods == {mkAlt}:
          var p = gui.textFieldCursorPos
          while p < text.runeLen and     text.runeAt(p).isWhiteSpace: inc(p)
          while p < text.runeLen and not text.runeAt(p).isWhiteSpace: inc(p)
          gui.textFieldCursorPos = p
        else:
          gui.textFieldCursorPos = min(gui.textFieldCursorPos + 1, text.runeLen)

      elif k.key == keyLeft:
        if k.mods == {mkAlt}:
          var p = gui.textFieldCursorPos
          while p > 0 and     text.runeAt(p-1).isWhiteSpace: dec(p)
          while p > 0 and not text.runeAt(p-1).isWhiteSpace: dec(p)
          gui.textFieldCursorPos = p
        else:
          gui.textFieldCursorPos = max(gui.textFieldCursorPos - 1, 0)

    clearKeyBuf()

    # Splice newly entered characters into the string.
    # (If we exited edit mode in the above key handler, this will result in
    # a noop as exitEditMode() clears the char buffer.)
    if not charBufEmpty():
      let newChars = consumeCharBuf()

      let before = text.runeSubStr(0, gui.textFieldCursorPos)
      let after = text.runeSubStr(gui.textFieldCursorPos)

      text = before & newChars & after
      inc(gui.textFieldCursorPos, newChars.runeLen)

  result = text

  # Draw text field
  let editing = gui.textFieldActiveItem == id

  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif editing: dsActive
    else: dsNormal

  var
    textX = textBoxX
    textY = y + h*0.5

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_LO
    else:        GRAY_MID

  # Draw text field background
  vg.beginPath()
  vg.roundedRect(x, y, w, h, 5)
  vg.fillColor(fillColor)
  vg.fill()

  # Scroll content into view & draw cursor when editing
  if editing:
    var
      p = min(gui.textFieldCursorPos, text.runeLen-1)
      x0 = glyphs[p].maxX

    while p > 0 and x0 - glyphs[p].minX < textBoxW: dec(p)

    gui.textFieldDisplayStartPos = p
    gui.textFieldDisplayStartX = min(
      textBoxX - ((x0 - glyphs[p].minX) - textBoxW), textBoxX)

    textX = gui.textFieldDisplayStartX

    # Draw cursor
    let cursorX = if gui.textFieldCursorPos > 0:
      gui.textFieldDisplayStartX + glyphs[gui.textFieldCursorPos].x -
                                   glyphs[p].x
    else: textBoxX
    #text ++ text.runeOffset(gui.textFieldDisplayStartPos)

    vg.beginPath()
    vg.strokeColor(RED)
    vg.strokeWidth(1.0)
    vg.moveTo(cursorX, y + 2)
    vg.lineTo(cursorX, y+h - 2)
    vg.stroke()

  # Draw text
#  let textColor = if editing: GRAY_HI else: GRAY_LO
  let textColor = rgb(0, 0.8, 0)

  vg.fontSize(19.0)
  vg.fontFace("sans-bold")
  vg.textAlign(haLeft, vaMiddle)
  vg.fillColor(textColor)

  vg.scissor(textBoxX, textBoxY, textBoxW, textBoxH)
  let txt = text.runeSubStr(gui.textFieldDisplayStartPos)
  discard vg.text(textX, textY, txt)
  vg.resetScissor()

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template textField*(x, y, w, h: float,
                    tooltip:    string = "",
                    text:       string): string =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, tooltip, text)


# }}}
# {{{ ScrollBar
# {{{ horizScrollBar

# Must be kept in sync with vertScrollBar!
proc horizScrollBar(id:         ItemId,
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
  if not gui.focusCaptured and mouseInside(x, y, w, h):
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
proc vertScrollBar(id:         ItemId,
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
  if not gui.focusCaptured and mouseInside(x, y, w, h):
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

proc horizSlider(id:         ItemId,
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
  if not gui.focusCaptured and mouseInside(x, y, w, h):
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

proc vertSlider(id:         ItemId,
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
  if not gui.focusCaptured and mouseInside(x, y, w, h):
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

# {{{ init()

proc init*(nvg: NVGContext) =
  RED       = rgb(1.0, 0.4, 0.4)
  GRAY_MID  = gray(0.6)
  GRAY_HI   = gray(0.8)
  GRAY_LO   = gray(0.25)
  GRAY_LOHI = gray(0.35)

  vg = nvg

  let win = currentContext()
  win.keyCb  = keyCb
  win.charCb = charCb

  win.stickyMouseButtons = true

# }}}
# {{{ beginFrame()

proc beginFrame*() =
  let win = glfw.currentContext()

  # Store mouse state
  gui.lastmx = gui.mx
  gui.lastmy = gui.my

  (gui.mx, gui.my) = win.cursorPos()

  gui.mbLeftDown   = win.mouseButtonDown(mbLeft)
  gui.mbRightDown  = win.mouseButtonDown(mbRight)
  gui.mbMiddleDown = win.mouseButtonDown(mbMiddle)

  # Store modifier key state (just for convenience for the GUI functions)
  gui.shiftDown  = win.isKeyDown(keyLeftShift) or
                   win.isKeyDown(keyRightShift)

  gui.ctrlDown   = win.isKeyDown(keyLeftControl) or
                   win.isKeyDown(keyRightControl)

  gui.altDown    = win.isKeyDown(keyLeftAlt) or
                   win.isKeyDown(keyRightAlt)

  gui.superDown  = win.isKeyDown(keyLeftSuper) or
                   win.isKeyDown(keyRightSuper)

  # Reset hot item
  gui.hotItem = 0

# }}}
# {{{ endFrame

proc endFrame*() =
#  echo fmt"hotItem: {gui.hotItem}, activeItem: {gui.activeItem}, textFieldState: {gui.textFieldState}"

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

# vim: et:ts=2:sw=2:fdm=marker
