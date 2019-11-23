import math, unicode, strformat

import glfw
import nanovg
import xxhash
import utils


# {{{ Types

type ItemId = int64

# {{{ SliderState

type
  SliderState = enum
    ssDefault,
    ssDragHidden

# }}}
# {{{ ScrollBarState

type
  ScrollBarState = enum
    sbsDefault,
    sbsDragNormal,
    sbsDragHidden,
    sbsTrackClickFirst,
    sbsTrackClickDelay,
    sbsTrackClickRepeat

  ScrollBarStateVars = object
    state:    ScrollBarState

    # Set when the LMB is pressed inside the scroll bar's track but outside of
    # the knob:
    # -1 = LMB pressed on the left side of the knob
    #  1 = LMB pressed on the right side of the knob
    clickDir: float

# }}}
# {{{ DropdownState

type
  DropdownState = enum
    dsClosed, dsOpenLMBPressed, dsOpen

  DropdownStateVars = object
    state:      DropdownState

    # Dropdown in open mode, 0 if no dropdown is open currently.
    activeItem: ItemId

# }}}
# {{{ TextFieldState

type
  TextFieldState = enum
    tfDefault, tfEditLMBPressed, tfEdit

  TextFieldStateVars = object
    state:           TextFieldState

    # Text field item in edit mode, 0 if no text field is being edited.
    activeItem:      ItemId

    # The cursor is before the Rune with this index. If the cursor is at the end
    # of the text, the cursor pos equals the lenght of the text. From this
    # follow that the cursor position for an empty text is 0.
    cursorPos:       Natural

    # Index of the start Rune in the selection, -1 if nothing is selected.
    selStartPos:     int

    # Index of the last Rune in the selection.
    selEndPos:       Natural

    # The text is displayed starting from the Rune with this index.
    displayStartPos: Natural
    displayStartX:   float

    # The original text is stored when going into edit mode so it can be
    # restored if the editing is cancelled.
    originalText:    string

# }}}
# {{{ TooltipState

type
  TooltipState = enum
    tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

  TooltipStateVars = object
    state:     TooltipState
    lastState: TooltipState

    # Used for the various tooltip delays & timeouts.
    t0:        float
    text:      string

# }}}
# {{{ UIState

type
  UIState = object
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
    radioButtonsActiveItem: Natural

    dropdownState:  DropdownStateVars
    textFieldState: TextFieldStateVars
    scrollBarState: ScrollBarStateVars
    sliderState:    SliderState

    # Internal tooltip state
    # **********************
    tooltipState:     TooltipStateVars

# }}}
# {{{ DrawState

type DrawState = enum
  dsNormal, dsHover, dsActive

# }}}
# }}}
# {{{ Globals

var
  g_nvgContext: NVGContext
  g_uiState    {.threadvar.}: UIState

  # TODO remove these once themeing is implemented
  RED*       {.threadvar.}: Color
  GRAY_MID*  {.threadvar.}: Color
  GRAY_HI*   {.threadvar.}: Color
  GRAY_LO*   {.threadvar.}: Color
  GRAY_LOHI* {.threadvar.}: Color

# }}}
# {{{ Configuration

const
  TooltipShowDelay       = 0.4
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 0.4

  ScrollBarFineDragDivisor         = 10.0
  ScrollBarUltraFineDragDivisor    = 100.0
  ScrollBarTrackClickRepeatDelay   = 0.3
  ScrollBarTrackClickRepeatTimeout = 0.05

  SliderFineDragDivisor      = 10.0
  SliderUltraFineDragDivisor = 100.0

# }}}

# {{{ Utils

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
# {{{ Draw layers

const
  BottomLayer  = 0
  DefaultLayer = 10
  TopLayer     = 20

type DrawProc = proc (vg: NVGContext)

var g_drawLayers {.threadvar.}: array[BottomLayer..TopLayer, seq[DrawProc]]

proc initDrawLayers() =
  for i in 0..g_drawLayers.high:
    g_drawLayers[i] = @[]

proc drawLayerAdd(layer: Natural = DefaultLayer, p: DrawProc) =
  g_drawLayers[layer].add(p)

proc drawLayers(vg: NVGContext) =
  # Draw all layers on top of each other
  for layer in g_drawLayers:
    for drawProc in layer:
      drawProc(vg)

# }}}
# {{{ UI helpers

template generateId(filename: string, line: int, id: string): ItemId =
  # TODO collision check in debug mode
  let
    hash32 = XXH32(filename & $line & id)

  # Make sure the IDs are always positive integers
  int64(hash32) - int32.low + 1


proc mouseInside(x, y, w, h: float): bool =
  alias(gui, g_uiState)
  gui.mx >= x and gui.mx <= x+w and
  gui.my >= y and gui.my <= y+h

template isHot(id: ItemId): bool =
  alias(gui, g_uiState)
  gui.hotItem == id

template setHot(id: ItemId) =
  alias(gui, g_uiState)
  gui.hotItem = id

template isActive(id: ItemId): bool =
  alias(gui, g_uiState)
  gui.activeItem == id

template setActive(id: ItemId) =
  alias(gui, g_uiState)
  gui.activeItem = id

template isHotAndActive(id: ItemId): bool =
  alias(gui, g_uiState)
  isHot(id) and isActive(id)

template noActiveItem(): bool =
  alias(gui, g_uiState)
  gui.activeItem == 0

template hasActiveItem(): bool =
  alias(gui, g_uiState)
  gui.activeItem > 0

# }}}
# {{{ Keyboard handling

const CharBufSize = 200
var
  # TODO do we need locking around this stuff? written in the callback, read
  # from the UI code
  g_charBuf: array[CharBufSize, Rune]
  g_charBufIdx: Natural

proc charCb(win: Window, codePoint: Rune) =
  if g_charBufIdx <= g_charBuf.high:
    g_charBuf[g_charBufIdx] = codePoint
    inc(g_charBufIdx)

proc clearCharBuf() = g_charBufIdx = 0

proc charBufEmpty(): bool = g_charBufIdx == 0

proc consumeCharBuf(): string =
  for i in 0..<g_charBufIdx:
    result &= g_charBuf[i]
  clearCharBuf()


type KeyEvent = object
  key:  Key
  mods: set[ModifierKey]

template mkKeyEvent(k: Key, m: set[ModifierKey]): KeyEvent =
  KeyEvent(key: k, mods: m)

proc withoutShift(k: KeyEvent): KeyEvent =
  KeyEvent(key: k.key, mods: k.mods - {mkShift})

const KeyBufSize = 200
var
  # TODO do we need locking around this stuff? written in the callback, read
  # from the UI code
  g_keyBuf: array[KeyBufSize, KeyEvent]
  g_keyBufIdx: Natural

const EditKeys = {
  keyEscape, keyEnter, keyTab,
  keyBackspace, keyDelete,
  keyRight, keyLeft, keyDown, keyUp,
  keyPageUp, keyPageDown,
  keyHome, keyEnd
}

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           mods: set[ModifierKey]) =

  if key in EditKeys and action in {kaDown, kaRepeat}:
    if g_keyBufIdx <= g_keyBuf.high:
      g_keyBuf[g_keyBufIdx] = KeyEvent(key: key, mods: mods)
      inc(g_keyBufIdx)

proc clearKeyBuf() = g_keyBufIdx = 0

iterator keyBuf(): KeyEvent =
  var i = 0
  while i < g_keyBufIdx:
    yield g_keyBuf[i]
    inc(i)

when defined(macosx):
  const GoToPreviousWord  = @[mkKeyEvent(keyLeft,      {mkAlt})]
  const GoToNextWord      = @[mkKeyEvent(keyRight,     {mkAlt})]

  const GoToLineStart     = @[mkKeyEvent(keyLeft,      {mkSuper}),
                              mkKeyEvent(keyA,         {mkCtrl})]

  const GoToLineEnd       = @[mkKeyEvent(keyRight,     {mkSuper}),
                              mkKeyEvent(keyE,         {mkCtrl})]

  const DeleteWordToRight = @[mkKeyEvent(keyDelete,    {mkAlt})]
  const DeleteWordToLeft  = @[mkKeyEvent(keyBackspace, {mkAlt})]

else: # Windows & Linux
  const GoToPreviousWord  = @[mkKeyEvent(keyLeft,      {mkCtrl})]
  const GoToNextWord      = @[mkKeyEvent(keyRight,     {mkCtrl})]
  const GoToLineStart     = @[mkKeyEvent(keyHome,      {})]
  const GoToLineEnd       = @[mkKeyEvent(keyEnd,       {})]
  const DeleteWordToRight = @[mkKeyEvent(keyDelete,    {mkCtrl})]
  const DeleteWordToLeft  = @[mkKeyEvent(keyBackspace, {mkCtrl})]

# }}}
# {{{ Tooltip handling
# {{{ handleTooltipInsideWidget

proc handleTooltipInsideWidget(id: ItemId, tooltip: string) =
  alias(gui, g_uiState)
  alias(tt, gui.tooltipState)

  tt.state = tt.lastState

  # Reset the tooltip show delay if the cursor has been moved inside a
  # widget
  if tt.state == tsShowDelay:
    let cursorMoved = gui.mx != gui.lastmx or gui.my != gui.lastmy
    if cursorMoved:
      tt.t0 = getTime()

  # Hide the tooltip immediately if the LMB is pressed inside the widget
  if gui.mbLeftDown and hasActiveItem():
    tt.state = tsOff

  # Start the show delay if we just entered the widget with LMB up and no
  # other tooltip is being shown
  elif tt.state == tsOff and not gui.mbLeftDown and
       gui.lastHotItem != id:
    tt.state = tsShowDelay
    tt.t0 = getTime()

  elif tt.state >= tsShow:
    tt.state = tsShow
    tt.t0 = getTime()
    tt.text = tooltip

# }}}
# {{{ drawTooltip

proc drawTooltip(x, y: float, text: string, alpha: float = 1.0) =
  drawLayerAdd(TopLayer-3, proc (vg: NVGContext) =
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
  )

# }}}
# {{{ tooltipPost

proc tooltipPost() =
  alias(gui, g_uiState)
  alias(tt, gui.tooltipState)

  # TODO the actual drawing should be moved out of here once deferred drawing
  # is implemented
  let
    ttx = gui.mx + 13
    tty = gui.my + 20

  case tt.state:
  of tsOff: discard
  of tsShowDelay:
    if getTime() - tt.t0 > TooltipShowDelay:
      tt.state = tsShow

  of tsShow:
    drawToolTip(ttx, tty, tt.text)

  of tsFadeOutDelay:
    drawToolTip(ttx, tty, tt.text)
    if getTime() - tt.t0 > TooltipFadeOutDelay:
      tt.state = tsFadeOut
      tt.t0 = getTime()

  of tsFadeOut:
    let t = getTime() - tt.t0
    if t > TooltipFadeOutDuration:
      tt.state = tsOff
    else:
      let alpha = 1.0 - t / TooltipFadeOutDuration
      drawToolTip(ttx, tty, tt.text, alpha)

  # We reset the show delay state or move into the fade out state if the
  # tooltip is being shown; this is to handle the case when the user just
  # moved the cursor outside of a widget. The actual widgets are responsible
  # for "keeping the state alive" every frame if the widget is hot/active by
  # restoring the tooltip state from lastTooltipState.
  tt.lastState = tt.state

  if tt.state == tsShowDelay:
    tt.state = tsOff
  elif tt.state == tsShow:
    tt.state = tsFadeOutDelay
    tt.t0 = getTime()

# }}}
# }}}

# {{{ Label
proc textLabel(id:         ItemId,
               x, y, w, h: float,
               label:      string,
               color:      Color,
               fontSize:   float = 19.0,
               fontFace:   string = "sans-bold") =

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
    vg.fontSize(fontSize)
    vg.fontFace(fontFace)
    vg.textAlign(haLeft, vaMiddle)
    vg.fillColor(color)
    discard vg.text(x, y+h*0.5, label)
  )


template label*(x, y, w, h: float,
                label:      string,
                color:      Color,
                fontSize:   float = 19.0,
                fontFace:   string = "sans-bold") =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  textLabel(id, x, y, w, h, label, color, fontSize, fontFace)

# }}}
# {{{ Button

proc button(id:         ItemId,
            x, y, w, h: float,
            label:      string,
            color:      Color,
            tooltip:    string = ""): bool =

  alias(gui, g_uiState)

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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
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
  )

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
# {{{ CheckBox

proc checkBox(id:      ItemId,
              x, y, w: float,
              tooltip: string = "",
              active:  bool): bool =

  alias(gui, g_uiState)

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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
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
  )

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template checkBox*(x, y, w: float,
                   tooltip: string = "",
                   active:  bool): bool =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  checkbox(id, x, y, w, tooltip, active)

# }}}
# {{{ RadioButtons

proc radioButtons(id:           ItemId,
                  x, y, w, h:   float,
                  labels:       seq[string],
                  tooltips:     seq[string] = @[],
                  activeButton: Natural): Natural =

  assert activeButton >= 0 and activeButton <= labels.high
  assert tooltips.len == 0 or tooltips.len == labels.len

  alias(gui, g_uiState)

  let
    numButtons = labels.len
    buttonW = w / numButtons.float

  # Hit testing
  let hotButton = min(int(floor((gui.mx - x) / buttonW)), numButtons-1)

  if not gui.focusCaptured and mouseInside(x, y, w, h):
    setHot(id)
    if gui.mbLeftDown and noActiveItem():
      setActive(id)
      gui.radioButtonsActiveItem = hotButton

  # LMB released over active widget means it was clicked
  if not gui.mbLeftDown and isHotAndActive(id) and
     gui.radioButtonsActiveItem == hotButton:
    result = hotButton
  else:
    result = activeButton

  # Draw radio buttons
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  var x = x
  const PadX = 2

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
    vg.fontSize(19.0)
    vg.fontFace("sans-bold")
    vg.textAlign(haLeft, vaMiddle)

    for i, label in labels:
      let fillColor = if   drawState == dsHover  and hotButton == i: GRAY_HI
                      elif drawState == dsActive and hotButton == i and
                           gui.radioButtonsActiveItem == i: RED
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
  )

  if isHot(id):
    handleTooltipInsideWidget(id, tooltips[hotButton])


template radioButtons*(x, y, w, h:   float,
                       labels:       seq[string],
                       tooltips:     seq[string] = @[],
                       activeButton: Natural): Natural =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  radioButtons(id, x, y, w, h, labels, tooltips, activeButton)

# }}}
# {{{ Dropdown

proc dropdown(id:           ItemId,
              x, y, w, h:   float,
              items:        seq[string],
              tooltip:      string = "",
              selectedItem: Natural): Natural =

  assert items.len > 0
  assert selectedItem <= items.high

  alias(gui, g_uiState)
  alias(ds, gui.dropdownState)

  const BoxPad = 7

  var
    boxX, boxY, boxW, boxH: float
    hoverItem = -1

  let
    numItems = items.len
    itemHeight = h  # TODO just temporarily

  result = selectedItem

  proc closeDropdown() =
    ds.state = dsClosed
    ds.activeItem = 0
    gui.focusCaptured = false

  if ds.state == dsClosed:
    if not gui.focusCaptured and mouseInside(x, y, w, h):
      setHot(id)
      if gui.mbLeftDown and noActiveItem():
        setActive(id)
        ds.state = dsOpenLMBPressed
        ds.activeItem = id
        gui.focusCaptured = true

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if ds.activeItem == id and ds.state >= dsOpenLMBPressed:

    # Calculate the position of the box around the dropdown items
    var maxItemWidth = 0.0

    # TODO to be kept up to date with the draw proc
    g_nvgContext.fontSize(19.0)
    g_nvgContext.fontFace("sans-bold")

    for i in items:
      let tw = g_nvgContext.horizontalAdvance(0, 0, i)
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
      closeDropdown()

    hoverItem = min(int(floor((gui.my - boxY - BoxPad) / itemHeight)),
                    numItems-1)

    # LMB released inside the box selects the item under the cursor and closes
    # the dropdown
    if ds.state == dsOpenLMBPressed:
      if not gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          closeDropdown()
        else:
          ds.state = dsOpen
    else:
      if gui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          closeDropdown()
        elif insideButton:
          closeDropdown()

  # Draw button
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  # Dropdown button
  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
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
  )

  # Dropdown items
  drawLayerAdd(DefaultLayer+1, proc (vg: NVGContext) =
    if isActive(id) and ds.state >= dsOpenLMBPressed:
      # Draw item list box
      vg.beginPath()
      vg.roundedRect(boxX, boxY, boxW, boxH, 5)
      vg.fillColor(GRAY_LO)
      vg.fill()

      # Draw items
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
  )

  if isHot(id):
    handleTooltipInsideWidget(id, tooltip)


template dropdown*(x, y, w, h:   float,
                   items:        seq[string],
                   tooltip:      string = "",
                   selectedItem: Natural): Natural =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  dropdown(id, x, y, w, h, items, tooltip, selectedItem)

# }}}
# {{{ TextField

proc textField(id:         ItemId,
               x, y, w, h: float,
               tooltip:    string = "",
               text:       string): string =

  # TODO maxlength parameter
  # TODO only int & float parameter

  const
    MaxTextLen = 1000
    PadX = 8

  assert text.runeLen <= MaxTextLen

  alias(gui, g_uiState)
  alias(tf, gui.textFieldState)

  var text = text

  # The text is displayed within this rectangle (used for drawing later)
  let
    textBoxX = x + PadX
    textBoxW = w - PadX*2
    textBoxY = y
    textBoxH = h

  var
    glyphs: array[MaxTextLen, GlyphPosition]  # TODO is this buffer large enough?
    glyphsCalculated = false

  proc hasSelection(): bool =
    tf.selStartPos > -1 and tf.selStartPos != tf.selEndPos

  proc getSelection(): (int, int) =
    if (tf.selStartPos < tf.selEndPos):
      (tf.selStartPos, tf.selEndPos.int)
    else:
      (tf.selEndPos.int, tf.selStartPos)

  proc clearSelection() =
    tf.selStartPos = -1
    tf.selEndPos = 0

  proc calcGlyphPos(force: bool = false) =
    # TODO to be kept up to date with the draw proc
    g_nvgContext.fontSize(19.0)
    g_nvgContext.fontFace("sans-bold")

    if force or not glyphsCalculated:
      discard g_nvgContext.textGlyphPositions(0, 0, text, glyphs)

  if tf.state == tfDefault:
    # Hit testing
    if mouseInside(x, y, w, h):
      setHot(id)
      if gui.mbLeftDown and noActiveItem():
        setActive(id)
        clearCharBuf()
        clearKeyBuf()

        tf.state = tfEditLMBPressed
        tf.activeItem = id
        tf.cursorPos = text.runeLen
        tf.displayStartPos = 0
        tf.displayStartX = textBoxX
        tf.originalText = text
        clearSelection()

        gui.focusCaptured = true

  proc exitEditMode() =
    clearKeyBuf()
    clearCharBuf()

    tf.state = tfDefault
    tf.activeItem = 0
    tf.cursorPos = 0
    tf.displayStartPos = 0
    tf.displayStartX = textBoxX
    tf.originalText = ""
    clearSelection()

    gui.focusCaptured = false

  # We 'fall through' to the edit state to avoid a 1-frame delay when going
  # into edit mode
  if tf.activeItem == id and tf.state >= tfEditLMBPressed:
    setHot(id)
    setActive(id)

    if tf.state == tfEditLMBPressed:
      if not gui.mbLeftDown:
        tf.state = tfEdit
    else:
      # LMB pressed outside the text field exits edit mode
      if gui.mbLeftDown and not mouseInside(x, y, w, h):
        exitEditMode()

    # Handle text field shortcuts
    # (If we exited edit mode above key handler, this will result in a noop as
    # exitEditMode() clears the key buffer.)

    proc findNextWordEnd(): Natural =
      var p = tf.cursorPos
      while p < text.runeLen and     text.runeAt(p).isWhiteSpace: inc(p)
      while p < text.runeLen and not text.runeAt(p).isWhiteSpace: inc(p)
      result = p

    proc findPrevWordStart(): Natural =
      var p = tf.cursorPos
      while p > 0 and     text.runeAt(p-1).isWhiteSpace: dec(p)
      while p > 0 and not text.runeAt(p-1).isWhiteSpace: dec(p)
      result = p

    proc updateSelection(newCursorPos: Natural) =
      if tf.selStartPos == -1:
        tf.selStartPos = tf.cursorPos
        tf.selEndPos   = tf.cursorPos
      tf.selEndPos = newCursorPos

    proc deleteSelection() =
      let (startPos, endPos) = getSelection()
      text = text.runeSubStr(0, startPos) & text.runeSubStr(endPos)
      tf.cursorPos = startPos
      clearSelection()

    for ke in keyBuf():
      let keNoShift = withoutShift(ke)

      if keNoShift in GoToNextWord:
        let newCursorPos = findNextWordEnd()
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif keNoShift in GoToPreviousWord:
        let newCursorPos = findPrevWordStart()
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif keNoShift in GoToLineStart or ke.key == keyUp:
        let newCursorPos = 0
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif keNoShift in GoToLineEnd or ke.key == keyDown:
        let newCursorPos = text.runeLen
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif ke in DeleteWordToRight:
        if hasSelection():
          deleteSelection()
        else:
          let p = findNextWordEnd()
          text = text.runeSubStr(0, tf.cursorPos) & text.runeSubStr(p)

      elif ke in DeleteWordToLeft:
        if hasSelection():
          deleteSelection()
        else:
          let p = findPrevWordStart()
          text = text.runeSubStr(0, p) & text.runeSubStr(tf.cursorPos)
          tf.cursorPos = p

      elif ke.key == keyRight:
        let newCursorPos = min(tf.cursorPos + 1, text.runeLen)
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif ke.key == keyLeft:
        let newCursorPos = max(tf.cursorPos - 1, 0)
        if mkShift in ke.mods:
          updateSelection(newCursorPos)
        else:
          clearSelection()
        tf.cursorPos = newCursorPos

      elif ke.key == keyBackspace:
        if hasSelection():
          deleteSelection()
        elif tf.cursorPos > 0:
          text = text.runeSubStr(0, tf.cursorPos - 1) &
                 text.runeSubStr(tf.cursorPos)
          dec(tf.cursorPos)

      elif ke.key == keyDelete:
        if hasSelection():
          deleteSelection()
        elif text.len > 0:
            text = text.runeSubStr(0, tf.cursorPos) &
                   text.runeSubStr(tf.cursorPos + 1)

      elif ke.key == keyEscape:   # Cancel edits
        text = tf.originalText
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

      elif ke.key == keyEnter:  # Persist edits
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

      elif ke.key == keyTab: discard  # TODO

    clearKeyBuf()

    # Splice newly entered characters into the string.
    # (If we exited edit mode in the above key handler, this will result in
    # a noop as exitEditMode() clears the char buffer.)
    if not charBufEmpty():
      var newChars = consumeCharBuf()

      if hasSelection():
        let (startPos, endPos) = getSelection()
        text = text.runeSubStr(0, startPos) & newChars & text.runeSubStr(endPos)
        tf.cursorPos = startPos + newChars.runeLen()
        clearSelection()
      else:
        let insertPos = tf.cursorPos
        if insertPos == text.runeLen():
          text.add(newChars)
        else:
          text.insert(newChars, text.runeOffset(insertPos))

        inc(tf.cursorPos, newChars.runeLen())

      if text.runeLen > MaxTextLen:
        text = text.runeSubStr(0, MaxTextLen)
        tf.cursorPos = MaxTextLen

      # We need to force glyp position recalculation here because the
      # text has changed.
      calcGlyphPos(force = true)

  result = text

  # Draw text field
  let editing = tf.activeItem == id

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
  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(fillColor)
    vg.fill()

    vg.scissor(textBoxX, textBoxY, textBoxW, textBoxH)

    # Scroll content into view & draw cursor when editing
    if editing:
      calcGlyphPos()
      let textLen = text.runeLen

      if textLen == 0:
        tf.cursorPos = 0
        tf.selStartPos = -1
        tf.selEndPos = 0
        tf.displayStartPos = 0
        tf.displayStartX = textBoxX

      else:
        # Text fits into the text box
        if glyphs[textLen-1].maxX < textBoxW:
          tf.displayStartPos = 0
          tf.displayStartX = textBoxX
        else:
          var p = min(tf.cursorPos, textLen-1)
          let startOffsetX = textBoxX - tf.displayStartX

          proc calcDisplayStart(fromPos: Natural): (Natural, float) =
            let x0 = glyphs[fromPos].maxX
            var p = fromPos

            while p > 0 and x0 - glyphs[p].minX < textBoxW: dec(p)

            let
              displayStartPos = p
              textW = x0 - glyphs[p].minX
              startOffsetX = textW - textBoxW
              displayStartX = min(textBoxX - startOffsetX, textBoxX)

            (displayStartPos, displayStartX)

          # Cursor past the right edge of the text box
          if glyphs[p].maxX -
             glyphs[tf.displayStartPos].minX - startOffsetX > textBoxW:

            (tf.displayStartPos, tf.displayStartX) = calcDisplayStart(p)

          # Make sure the text is always aligned to the right edge of the text
          # box
          elif glyphs[textLen-1].maxX -
               glyphs[tf.displayStartPos].minX - startOffsetX < textBoxW:

            (tf.displayStartPos, tf.displayStartX) = calcDisplayStart(textLen-1)

          # Cursor past the left edge of the text box
          elif glyphs[p].minX < glyphs[tf.displayStartPos].minX + startOffsetX:
            tf.displayStartX = textBoxX
            tf.displayStartPos = min(tf.displayStartPos, p)

      textX = tf.displayStartX

      # Draw selection
      if hasSelection():
        var (startPos, endPos) = getSelection()
        endPos = max(endPos - 1, 0)

        let
          selStartX = tf.displayStartX + glyphs[startPos].minX -
                                         glyphs[tf.displayStartPos].x

          selEndX = tf.displayStartX + glyphs[endPos].maxX -
                                       glyphs[tf.displayStartPos].x

        vg.beginPath()
        vg.rect(selStartX, y + 2, selEndX - selStartX, h - 4)
        vg.fillColor(rgb(0.5, 0.15, 0.15))
        vg.fill()

      # Draw cursor
      let cursorX = if tf.cursorPos == 0:
        textBoxX

      elif tf.cursorPos == text.runeLen:
        tf.displayStartX + glyphs[tf.cursorPos-1].maxX -
                           glyphs[tf.displayStartPos].x

      elif tf.cursorPos > 0:
        tf.displayStartX + glyphs[tf.cursorPos].x -
                           glyphs[tf.displayStartPos].x
      else: textBoxX

      vg.beginPath()
      vg.strokeColor(RED)
      vg.strokeWidth(1.0)
      vg.moveTo(cursorX, y + 2)
      vg.lineTo(cursorX, y+h - 2)
      vg.stroke()

      text = text.runeSubStr(tf.displayStartPos)

    # Draw text
    let textColor = if editing: GRAY_HI else: GRAY_LO

    vg.fontSize(19.0)
    vg.fontFace("sans-bold")
    vg.textAlign(haLeft, vaMiddle)
    vg.fillColor(textColor)

    discard vg.text(textX, textY, text)

    vg.resetScissor()
  )

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

  alias(gui, g_uiState)
  alias(sb, gui.scrollBarState)

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
    clamp(newValue + sb.clickDir * clickStep, s, e)

  if isActive(id):
    case sb.state
    of sbsDefault:
      if insideThumb:
        gui.x0 = gui.mx
        if gui.shiftDown:
          disableCursor()
          sb.state = sbsDragHidden
        else:
          sb.state = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if gui.mx < thumbX: sb.clickDir = -1 * s
        else:               sb.clickDir =  1 * s
        sb.state = sbsTrackClickFirst
        gui.t0 = getTime()

    of sbsDragNormal:
      if gui.shiftDown:
        disableCursor()
        sb.state = sbsDragHidden
      else:
        let dx = gui.mx - gui.x0

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = clamp(gui.mx, thumbMinX, thumbMaxX + thumbW)

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

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        gui.x0 = gui.mx
        gui.dragX = newThumbX + thumbW*0.5
        gui.dragY = -1.0
      else:
        sb.state = sbsDragNormal
        enableCursor()
        setCursorPosX(gui.dragX)
        gui.mx = gui.dragX
        gui.x0 = gui.dragX

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbX = calcThumbX(newValue)

      sb.state = sbsTrackClickDelay
      gui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - gui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - gui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbX = calcThumbX(newValue)

          if sb.clickDir * sgn(endVal - startVal).float > 0:
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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(trackColor)
    vg.fill()

    # Draw thumb
    let thumbColor = case drawState
      of dsHover: GRAY_LOHI
      of dsActive:
        if sb.state < sbsTrackClickFirst: RED
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
    let valueString = fmt"{newValue:.3f}"
    let tw = vg.horizontalAdvance(0,0, valueString)
    discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, valueString)
  )

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

  alias(gui, g_uiState)
  alias(sb, gui.scrollBarState)

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
    clamp(newValue + sb.clickDir * clickStep, s, e)

  if isActive(id):
    case sb.state
    of sbsDefault:
      if insideThumb:
        gui.y0 = gui.my
        if gui.shiftDown:
          disableCursor()
          sb.state = sbsDragHidden
        else:
          sb.state = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if gui.my < thumbY: sb.clickDir = -1 * s
        else:               sb.clickDir =  1 * s
        sb.state = sbsTrackClickFirst
        gui.t0 = getTime()

    of sbsDragNormal:
      if gui.shiftDown:
        disableCursor()
        sb.state = sbsDragHidden
      else:
        let dy = gui.my - gui.y0

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        gui.y0 = clamp(gui.my, thumbMinY, thumbMaxY + thumbH)

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

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        gui.y0 = gui.my
        gui.dragX = -1.0
        gui.dragY = newThumbY + thumbH*0.5
      else:
        sb.state = sbsDragNormal
        enableCursor()
        setCursorPosY(gui.dragY)
        gui.my = gui.dragY
        gui.y0 = gui.dragY

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbY = calcThumbY(newValue)

      sb.state = sbsTrackClickDelay
      gui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - gui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - gui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbY = calcThumbY(newValue)

          if sb.clickDir * sgn(endVal - startVal).float > 0:
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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(trackColor)
    vg.fill()

    # Draw thumb
    let thumbColor = case drawState
      of dsHover: GRAY_LOHI
      of dsActive:
        if sb.state < sbsTrackClickFirst: RED
        else: GRAY_LO
      else:   GRAY_LO

    vg.beginPath()
    vg.roundedRect(x + ThumbPad, newThumbY, thumbW, thumbH, 5)
    vg.fillColor(thumbColor)
    vg.fill()
  )

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
  alias(gui, g_uiState)
  alias(sb, gui.scrollBarState)

  # Handle release active scrollbar outside of the widget
  if not gui.mbLeftDown and hasActiveItem():
    case sb.state:
    of sbsDragHidden:
      sb.state = sbsDefault
      enableCursor()
      if gui.dragX > -1.0:
        setCursorPosX(gui.dragX)
      else:
        setCursorPosY(gui.dragY)

    else: sb.state = sbsDefault

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

  alias(gui, g_uiState)

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

      newPosX = clamp(posX + dx, posMinX, posMaxX)
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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
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
    let valueString = fmt"{newValue:.3f}"
    let tw = vg.horizontalAdvance(0,0, valueString)
    discard vg.text(x + w*0.5 - tw*0.5, y+h*0.5, valueString)
  )

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

  alias(gui, g_uiState)

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

      newPosY = clamp(posY + dy, posMaxY, posMinY)
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

  drawLayerAdd(DefaultLayer, proc (vg: NVGContext) =
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
  )

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
  alias(gui, g_uiState)

  # Handle release active slider outside of the widget
  if not gui.mbLeftDown and hasActiveItem():
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

  g_nvgContext = nvg

  let win = currentContext()
  win.keyCb  = keyCb
  win.charCb = charCb

  win.stickyMouseButtons = true

# }}}
# {{{ beginFrame()

proc beginFrame*() =
  let win = glfw.currentContext()

  alias(gui, g_uiState)

  # Store mouse state
  gui.lastmx = gui.mx
  gui.lastmy = gui.my

  (gui.mx, gui.my) = win.cursorPos()

  gui.mbLeftDown   = win.mouseButtonDown(mbLeft)
  gui.mbRightDown  = win.mouseButtonDown(mbRight)
  gui.mbMiddleDown = win.mouseButtonDown(mbMiddle)

  # Store modifier key state (just for convenience for the GUI functions)
  gui.shiftDown = win.isKeyDown(keyLeftShift) or
                  win.isKeyDown(keyRightShift)

  gui.ctrlDown  = win.isKeyDown(keyLeftControl) or
                  win.isKeyDown(keyRightControl)

  gui.altDown   = win.isKeyDown(keyLeftAlt) or
                  win.isKeyDown(keyRightAlt)

  gui.superDown = win.isKeyDown(keyLeftSuper) or
                  win.isKeyDown(keyRightSuper)

  # Reset hot item
  gui.hotItem = 0

  initDrawLayers()

# }}}
# {{{ endFrame

proc endFrame*() =
#  echo fmt"hotItem: {gui.hotItem}, activeItem: {gui.activeItem}, textFieldState: {gui.textFieldState}"

  alias(gui, g_uiState)

  tooltipPost()
  drawLayers(g_nvgContext)

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
