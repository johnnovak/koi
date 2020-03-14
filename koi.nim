import hashes, math, options, sets, sequtils, strformat, strutils, tables,
       unicode

import utils

import glfw
from glfw/wrapper import setCursor, createStandardCursor, CursorShape
import nanovg


# {{{ Types

type ItemId = int64

# {{{ SliderState

type
  SliderState = enum
    ssDefault,
    ssDragHidden,
    ssEditValue

  SliderStateVars = object
    state:       SliderState

    # Whether the cursor was moved before releasing the LMB in drag mode
    cursorMoved:  bool

    valueText:    string
    editModeItem: ItemId
    textFieldId:  ItemId

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

    # Origin offset, used for relative coordinate handling in dialogs
    ox, oy: float

    # Widgets will be drawn on this layer by default
    currentLayer: Natural

    # Window dimensions (in virtual pixels)
    winWidth, winHeight: float

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

    # For keeping track of the cursor in hidden drag mode.
    # Dragging can be only active along the X or Y-axis, but not both:
    # - in horizontal drag mode: dragX >= 0, dragY  < 0
    # - in vertical drag mode:   dragX  < 0, dragY >= 0
    dragX, dragY:   float

    # Widget-specific states
    # **********************
    radioButtonsActiveItem: Natural

    dropdownState:  DropdownStateVars
    textFieldState: TextFieldStateVars
    scrollBarState: ScrollBarStateVars
    sliderState:    SliderStateVars

    # Internal tooltip state
    # **********************
    tooltipState:     TooltipStateVars

    # Dialog state
    # **********************
    activeDialogTitle: Option[string]

    # Only true when we're in a dialog (this is needed so widgets outside
    # of the dialog won't register any events).
    insideDialog:      bool

# }}}
# {{{ DrawState

type DrawState = enum
  dsNormal, dsHover, dsActive

# }}}
# }}}
# {{{ Globals

var
  g_nvgContext: NVGContext
  g_uiState: UIState

  g_cursorArrow:       Cursor
  g_cursorIBeam:       Cursor
  g_cursorHorizResize: Cursor

  # TODO remove these once theming is implemented
  RED*       : Color
  GRAY_MID*  : Color
  GRAY_HI*   : Color
  GRAY_LO*   : Color
  GRAY_LOHI* : Color

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

  TextVertAlignFactor = 0.55

# }}}

# {{{ Utils

proc setFont*(vg: NVGContext, size: float, face: string = "sans-bold",
              ha: HorizontalAlign = haLeft, va: VerticalAlign = vaMiddle) =
  vg.fontFace(face)
  vg.fontSize(size)
  vg.textAlign(ha, va)

proc hideCursor*() =
  glfw.currentContext().cursorMode = cmDisabled

proc showCursor*() =
  glfw.currentContext().cursorMode = cmNormal

proc showArrowCursor*() =
  let win = glfw.currentContext()
  wrapper.setCursor(win.getHandle, g_cursorArrow)

proc showIBeamCursor*() =
  let win = glfw.currentContext()
  wrapper.setCursor(win.getHandle, g_cursorIBeam)

proc showHorizResizeCursor*() =
  let win = glfw.currentContext()
  wrapper.setCursor(win.getHandle, g_cursorHorizResize)

proc setCursorPosX*(x: float) =
  let win = glfw.currentContext()
  let (_, currY) = win.cursorPos()
  win.cursorPos = (x, currY)

proc setCursorPosY*(y: float) =
  let win = glfw.currentContext()
  let (currX, _) = win.cursorPos()
  win.cursorPos = (currX, y)

proc toClipboard*(s: string) =
  glfw.currentContext().clipboardString = s

proc fromClipboard*(): string =
  $glfw.currentContext().clipboardString

# }}}
# {{{ Draw layers

const
  BottomLayer  = 0
  DefaultLayer = 10
  TopLayer     = 20

type
  DrawProc = proc (vg: NVGContext)

  DrawLayers = object
    layers:        array[BottomLayer..TopLayer, seq[DrawProc]]
    lastUsedLayer: Natural

var
  g_drawLayers: DrawLayers

proc init(dl: var DrawLayers) =
  for i in 0..dl.layers.high:
    dl.layers[i] = @[]

proc add(dl: var DrawLayers, layer: Natural, p: DrawProc) =
  dl.layers[layer].add(p)
  dl.lastUsedLayer = layer

template addDrawLayer(layer: Natural, vg, body: untyped) =
  g_drawLayers.add(layer, proc (vg: NVGContext) =
    body
  )

proc removeLastAdded(dl: var DrawLayers) =
  discard dl.layers[dl.lastUsedLayer].pop()

proc draw(dl: DrawLayers, vg: NVGContext) =
  # Draw all layers on top of each other
  for layer in dl.layers:
    for drawProc in layer:
      drawProc(vg)

# }}}
# {{{ UI helpers

const KoiInternalIdPrefix = "~-=[//.K0i:iN73Rn4L:!D.//]=-~"  # unique enough?!

template generateId(id: string): ItemId =
  let hash32 = hash(id).uint32
  # Make sure the IDs are always positive integers
  let h = int64(hash32) - int32.low + 1
  assert h > 0
  h

template generateId(filename: string, line: int, id: string): ItemId =
  generateId(filename & ":" & $line & ":" & id)

proc mouseInside(x, y, w, h: float): bool =
  alias(ui, g_uiState)
  ui.mx >= x and ui.mx <= x+w and
  ui.my >= y and ui.my <= y+h

template isHot(id: ItemId): bool =
  alias(ui, g_uiState)
  ui.hotItem == id

template setHot(id: ItemId) =
  alias(ui, g_uiState)
  ui.hotItem = id

template isActive(id: ItemId): bool =
  alias(ui, g_uiState)
  ui.activeItem == id

template setActive(id: ItemId) =
  alias(ui, g_uiState)
  ui.activeItem = id

template isHotAndActive(id: ItemId): bool =
  alias(ui, g_uiState)
  isHot(id) and isActive(id)

template noActiveItem(): bool =
  alias(ui, g_uiState)
  ui.activeItem == 0

template hasActiveItem(): bool =
  alias(ui, g_uiState)
  ui.activeItem > 0

template isDialogActive(): bool =
  alias(ui, g_uiState)
  ui.activeDialogTitle.isSome

template isHit(x, y, w, h: float): bool =
  alias(ui, g_uiState)
  not ui.focusCaptured and (ui.insideDialog or not isDialogActive()) and
    mouseInside(x, y, w, h)

# }}}
# {{{ Keyboard handling

type KeyEvent* = object
  key*:    Key
  action*: KeyAction
  mods*:   set[ModifierKey]

type KeyShortcut* = object
  key*:    Key
  mods*:   set[ModifierKey]

template mkKeyShortcut*(k: Key, m: set[ModifierKey]): KeyShortcut =
  KeyShortcut(key: k, mods: m)

proc hash(ks: KeyShortcut): Hash =
  var h: Hash = 0
  h = h !& hash(ord(ks.key))
  for m in ks.mods:
    h = h !& hash(ord(m))
  result = !$h

# {{{ Shortcut definitions

type TextEditShortcuts = enum
  tesCursorOneCharLeft,
  tesCursorOneCharRight,
  tesCursorToPreviousWord,
  tesCursorToNextWord,
  tesCursorToLineStart,
  tesCursorToLineEnd,

  tesSelectionOneCharLeft,
  tesSelectionOneCharRight,
  tesSelectionToPreviousWord,
  tesSelectionToNextWord,
  tesSelectionToLineStart,
  tesSelectionToLineEnd,

  tesDeleteOneCharLeft,
  tesDeleteOneCharRight,
  tesDeleteWordToRight,
  tesDeleteWordToLeft,
  tesDeleteToLineStart,
  tesDeleteToLineEnd,

  tesSwitchChars,

  tesCutText,
  tesCopyText,
  tesPasteText,

  tesAccept,
  tesCancel


let textFieldEditShortcuts = {
  tesCursorOneCharLeft:    @[mkKeyShortcut(keyLeft,      {}),
                             mkKeyShortcut(keyB,         {mkCtrl})],

  tesCursorOneCharRight:   @[mkKeyShortcut(keyRight,     {}),
                             mkKeyShortcut(keyF,         {mkCtrl})],

  tesCursorToPreviousWord: @[mkKeyShortcut(keyLeft,      {mkAlt})],
  tesCursorToNextWord:     @[mkKeyShortcut(keyRight,     {mkAlt})],

  tesCursorToLineStart:    @[mkKeyShortcut(keyLeft,      {mkSuper}),
                             mkKeyShortcut(keyA,         {mkCtrl}),
                             mkKeyShortcut(keyP,         {mkCtrl}),
                             mkKeyShortcut(keyV,         {mkShift, mkCtrl}),
                             mkKeyShortcut(keyUp,        {})],

  tesCursorToLineEnd:      @[mkKeyShortcut(keyRight,     {mkSuper}),
                             mkKeyShortcut(keyE,         {mkCtrl}),
                             mkKeyShortcut(keyN,         {mkCtrl}),
                             mkKeyShortcut(keyV,         {mkCtrl}),
                             mkKeyShortcut(keyDown,      {})],

  tesSelectionOneCharLeft:    @[mkKeyShortcut(keyLeft,   {mkShift})],
  tesSelectionOneCharRight:   @[mkKeyShortcut(keyRight,  {mkShift})],
  tesSelectionToPreviousWord: @[mkKeyShortcut(keyLeft,   {mkShift, mkAlt})],
  tesSelectionToNextWord:     @[mkKeyShortcut(keyRight,  {mkShift, mkAlt})],

  tesSelectionToLineStart: @[mkKeyShortcut(keyLeft,      {mkShift, mkSuper}),
                             mkKeyShortcut(keyA,         {mkShift, mkCtrl}),
                             mkKeyShortcut(keyUp,        {mkShift})],

  tesSelectionToLineEnd:   @[mkKeyShortcut(keyRight,     {mkShift, mkSuper}),
                             mkKeyShortcut(keyE,         {mkShift, mkCtrl}),
                             mkKeyShortcut(keyDown,      {mkShift})],

  tesDeleteOneCharLeft:    @[mkKeyShortcut(keyBackspace, {}),
                             mkKeyShortcut(keyH,         {mkCtrl})],

  tesDeleteOneCharRight:   @[mkKeyShortcut(keyDelete,    {})],

  tesDeleteWordToRight:    @[mkKeyShortcut(keyDelete,    {mkAlt}),
                             mkKeyShortcut(keyD,         {mkCtrl})],

  tesDeleteWordToLeft:     @[mkKeyShortcut(keyBackspace, {mkAlt})],
  tesDeleteToLineStart:    @[mkKeyShortcut(keyBackspace, {mkSuper})],

  tesDeleteToLineEnd:      @[mkKeyShortcut(keyDelete,    {mkAlt}),
                             mkKeyShortcut(keyK,         {mkCtrl})],

  tesSwitchChars:          @[mkKeyShortcut(keyT,         {mkCtrl})],

  tesCutText:              @[mkKeyShortcut(keyX,         {mkSuper})],
  tesCopyText:             @[mkKeyShortcut(keyC,         {mkSuper})],
  tesPasteText:            @[mkKeyShortcut(keyV,         {mkSuper})],

  tesAccept:               @[mkKeyShortcut(keyEnter,     {}),
                             mkKeyShortcut(keyKpEnter,   {})],

  tesCancel:               @[mkKeyShortcut(keyEscape,    {})]
}.toTable


var textFieldEditShortcutsSet =
  toSeq(textFieldEditShortcuts.values).concat.toHashSet

# }}}

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


const KeyBufSize = 200
var
  # TODO do we need locking around this stuff? written in the callback, read
  # from the UI code
  g_keyBuf: array[KeyBufSize, KeyEvent]
  g_keyBufIdx: Natural


proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           mods: set[ModifierKey]) =

  let shortcut = mkKeyShortcut(key, mods)

  if (not g_uiState.focusCaptured) or
     (g_uiState.focusCaptured and action in {kaDown, kaRepeat} and
                                  shortcut in textFieldEditShortcutsSet):
    if g_keyBufIdx <= g_keyBuf.high:
      g_keyBuf[g_keyBufIdx] = KeyEvent(key: key, action: action, mods: mods)
      inc(g_keyBufIdx)


proc clearKeyBuf*() = g_keyBufIdx = 0

# TODO maybe there's a better way to reduce duplication
iterator keyBufInternal(): KeyEvent =
  var i = 0
  while i < g_keyBufIdx:
    yield g_keyBuf[i]
    inc(i)
  clearKeyBuf()

iterator keyBuf*(): KeyEvent =
  alias(ui, g_uiState)
  var i = 0

  if not ui.focusCaptured and (ui.insideDialog or not isDialogActive()):
    while i < g_keyBufIdx:
      yield g_keyBuf[i]
      inc(i)
    clearKeyBuf()

# }}}
# {{{ Tooltip handling
# {{{ handleTooltip

proc handleTooltip(id: ItemId, tooltip: string) =
  alias(ui, g_uiState)
  alias(tt, ui.tooltipState)

  if tooltip != "":
    tt.state = tt.lastState

    # Reset the tooltip show delay if the cursor has been moved inside a
    # widget
    if tt.state == tsShowDelay:
      let cursorMoved = ui.mx != ui.lastmx or ui.my != ui.lastmy
      if cursorMoved:
        tt.t0 = getTime()

    # Hide the tooltip immediately if the LMB is pressed inside the widget
    if ui.mbLeftDown and hasActiveItem():
      tt.state = tsOff

    # Start the show delay if we just entered the widget with LMB up and no
    # other tooltip is being shown
    elif tt.state == tsOff and not ui.mbLeftDown and
         ui.lastHotItem != id:
      tt.state = tsShowDelay
      tt.t0 = getTime()

    elif tt.state >= tsShow:
      tt.state = tsShow
      tt.t0 = getTime()
      tt.text = tooltip

# }}}
# {{{ drawTooltip

proc drawTooltip(x, y: float, text: string, alpha: float = 1.0) =
  addDrawLayer(TopLayer-3, vg):
    let
      w = 150.0
      h = 40.0

    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(gray(0.1, 0.88 * alpha))
    vg.fill()

    vg.setFont(12.0)
    vg.fillColor(white(0.9 * alpha))
    discard vg.text(x + 10, y + 10, text)

# }}}
# {{{ tooltipPost

proc tooltipPost() =
  alias(ui, g_uiState)
  alias(tt, ui.tooltipState)


  let
    ttx = ui.mx + 13
    tty = ui.my + 20

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
               fontSize:   float = 14.0,
               fontFace:   string = "sans-bold") =

  alias(ui, g_uiState)

  let
    x = x + ui.ox
    y = y + ui.oy

  addDrawLayer(ui.currentLayer, vg):
    vg.scissor(x, y, w, h)

    vg.setFont(fontSize, fontFace)
    vg.fillColor(color)
    discard vg.text(x, y + h*TextVertAlignFactor, label)

    vg.resetScissor()


template label*(x, y, w, h: float,
                label:      string,
                color:      Color,
                fontSize:   float = 14.0,
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

  alias(ui, g_uiState)

  let
    x = x + ui.ox
    y = y + ui.oy

  const TextBoxPadX = 8
  let
    textBoxX = x + TextBoxPadX
    textBoxW = w - TextBoxPadX*2
    textBoxY = y
    textBoxH = h

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHotAndActive(id):
    result = true

  # Draw button
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: RED
    else:        color

  addDrawLayer(ui.currentLayer, vg):
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(fillColor)
    vg.fill()

    vg.scissor(textBoxX, textBoxY, textBoxW, textBoxH)

    vg.setFont(14.0)
    vg.fillColor(GRAY_LO)
    let tw = vg.horizontalAdvance(label)
    discard vg.text(x + w*0.5 - tw*0.5, y + h*TextVertAlignFactor, label)

    vg.resetScissor()

  if isHot(id):
    handleTooltip(id, tooltip)


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

  alias(ui, g_uiState)

  let
    x = x + ui.ox
    y = y + ui.oy

  const
    CheckPad = 3

  # Hit testing
  if isHit(x, y, w, w):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  let active = if not ui.mbLeftDown and isHotAndActive(id): not active
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

  addDrawLayer(ui.currentLayer, vg):
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
    handleTooltip(id, tooltip)


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

  alias(ui, g_uiState)

  let
    numButtons = labels.len
    buttonW = w / numButtons.float

  var
    x = x + ui.ox
    y = y + ui.oy

  # Hit testing
  let hotButton = min(int(floor((ui.mx - x) / buttonW)), numButtons-1)

  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)
      ui.radioButtonsActiveItem = hotButton

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHotAndActive(id) and
     ui.radioButtonsActiveItem == hotButton:
    result = hotButton
  else:
    result = activeButton

  # Draw radio buttons
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  # TODO this should be done properly, with rounded rectangles, etc.
  const PadX = 2

  addDrawLayer(ui.currentLayer, vg):
    vg.setFont(14.0)

    for i, label in labels:
      let fillColor = if   drawState == dsHover  and hotButton == i: GRAY_HI
                      elif drawState == dsActive and hotButton == i and
                           ui.radioButtonsActiveItem == i: RED
                      else:
                        if activeButton == i: GRAY_LO else : GRAY_MID

      var w = buttonW - PadX

      vg.beginPath()
      vg.rect(x, y, w, h)
      vg.fillColor(fillColor)
      vg.fill()

      let
        textColor = if drawState == dsHover and hotButton == i: GRAY_LO
                    else:
                      if activeButton == i: GRAY_HI
                      else: GRAY_LO

      const TextBoxPadX = 4
      let
        textBoxX = x + TextBoxPadX
        textBoxW = w - TextBoxPadX*2
        textBoxY = y
        textBoxH = h

      vg.scissor(textBoxX, textBoxY, textBoxW, textBoxH)

      vg.fillColor(textColor)
      let tw = vg.horizontalAdvance(label)
      discard vg.text(x + buttonW*0.5 - tw*0.5, y + h*TextVertAlignFactor, label)

      vg.resetScissor()

      x += buttonW

  if isHot(id):
    handleTooltip(id, tooltips[hotButton])


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

  alias(ui, g_uiState)
  alias(ds, ui.dropdownState)

  let
    x = x + ui.ox
    y = y + ui.oy

  const TextBoxPadX = 8
  let
    textBoxX = x + TextBoxPadX
    textBoxW = w - TextBoxPadX*2
    textBoxY = y
    textBoxH = h

  const
    SelBoxPadX = 7
    SelBoxPadY = 7

  var
    selBoxX, selBoxY, selBoxW, selBoxH: float
    hoverItem = -1

  let
    numItems = items.len
    itemHeight = h  # TODO just temporarily

  result = selectedItem

  proc closeDropdown() =
    ds.state = dsClosed
    ds.activeItem = 0
    ui.focusCaptured = false

  if ds.state == dsClosed:
    if isHit(x, y, w, h):
      setHot(id)
      if ui.mbLeftDown and noActiveItem():
        setActive(id)
        ds.state = dsOpenLMBPressed
        ds.activeItem = id
        ui.focusCaptured = true

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if ds.activeItem == id and ds.state >= dsOpenLMBPressed:

    # Calculate the position of the box around the dropdown items
    var maxItemWidth = 0.0

    # TODO to be kept up to date with the draw proc
    g_nvgContext.setFont(14.0)

    for i in items:
      let tw = g_nvgContext.horizontalAdvance(i)
      maxItemWidth = max(tw, maxItemWidth)

    selBoxW = max(maxItemWidth + SelBoxPadX*2, w)
    selBoxH = float(items.len) * itemHeight + SelBoxPadY*2

    selBoxX = if x + selBoxW < ui.winWidth: x
              else: x - (selBoxW - w)

    selBoxY = if y + h + selBoxH < ui.winHeight: y + h
              else: y - selBoxH

    # Hit testing
    let
      insideButton = mouseInside(x, y, w, h)
      insideBox = mouseInside(selBoxX, selBoxY, selBoxW, selBoxH)

    if insideButton or insideBox:
      setHot(id)
      setActive(id)
    else:
      closeDropdown()

    if insideBox:
      hoverItem = min(int(floor((ui.my - selBoxY - SelBoxPadY) / itemHeight)),
                      numItems-1)

    # LMB released inside the box selects the item under the cursor and closes
    # the dropdown
    if ds.state == dsOpenLMBPressed:
      if not ui.mbLeftDown:
        if hoverItem >= 0:
          result = hoverItem
          closeDropdown()
        else:
          ds.state = dsOpen
    else:
      if ui.mbLeftDown:
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
  addDrawLayer(ui.currentLayer, vg):
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

    vg.scissor(textBoxX, textBoxY, textBoxW, textBoxH)

    vg.setFont(14.0)
    vg.fillColor(textColor)
    discard vg.text(x + ItemXPad, y + h*TextVertAlignFactor, itemText)

    vg.resetScissor()

  # Dropdown items
  addDrawLayer(ui.currentLayer + 1, vg):
    if isActive(id) and ds.state >= dsOpenLMBPressed:
      # Draw item list box
      vg.beginPath()
      vg.roundedRect(selBoxX, selBoxY, selBoxW, selBoxH, 5)
      vg.fillColor(GRAY_LO)
      vg.fill()

      # Draw items
      vg.setFont(14.0)
      vg.fillColor(GRAY_HI)

      var
        ix = selBoxX + SelBoxPadX
        iy = selBoxY + SelBoxPadY

      for i, item in items.pairs:
        var textColor = GRAY_HI
        if i == hoverItem:
          vg.beginPath()
          vg.rect(selBoxX, iy, selBoxW, h)
          vg.fillColor(RED)
          vg.fill()
          textColor = GRAY_LO

        vg.fillColor(textColor)
        discard vg.text(ix, iy + h*TextVertAlignFactor, item)
        iy += itemHeight

  if isHot(id):
    handleTooltip(id, tooltip)


template dropdown*(x, y, w, h:   float,
                   items:        seq[string],
                   tooltip:      string = "",
                   selectedItem: Natural): Natural =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  dropdown(id, x, y, w, h, items, tooltip, selectedItem)

# }}}
# {{{ TextField

# TODO
proc textFieldEnterEditMode(id: ItemId, text: string, startX: float) =
  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)

  setActive(id)
  clearCharBuf()
  clearKeyBuf()

  tf.state = tfEdit
  tf.activeItem = id
  tf.cursorPos = text.runeLen
  tf.displayStartPos = 0
  tf.displayStartX = startX
  tf.originalText = text
  tf.selStartPos = 0
  tf.selEndPos = tf.cursorPos

  ui.focusCaptured = true
  showIBeamCursor()


proc textField(id:         ItemId,
               x, y, w, h: float,
               tooltip:    string = "",
               drawWidget: bool = true,
               text:       string): string =

  # TODO maxlength parameter
  # TODO only int & float parameter

  const MaxTextLen = 1000

  assert text.runeLen <= MaxTextLen

  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)

  let
    x = x + ui.ox
    y = y + ui.oy

  # The text is displayed within this rectangle (used for drawing later)
  const TextBoxPadX = 8
  let
    textBoxX = x + TextBoxPadX
    textBoxW = w - TextBoxPadX*2
    textBoxY = y
    textBoxH = h

  var
    text = text
    glyphs: array[MaxTextLen, GlyphPosition]  # TODO is this buffer large enough?

  proc calcGlyphPos() =
    # TODO to be kept up to date with the draw proc
    g_nvgContext.setFont(14.0)
    discard g_nvgContext.textGlyphPositions(0, 0, text, glyphs)

  proc hasSelection(): bool =
    tf.selStartPos > -1 and tf.selStartPos != tf.selEndPos

  proc getSelection(): (int, int) =
    if (tf.selStartPos < tf.selEndPos):
      (tf.selStartPos, tf.selEndPos.int)
    else:
      (tf.selEndPos.int, tf.selStartPos)

  if tf.state == tfDefault:
    # Hit testing
    if isHit(x, y, w, h):
      setHot(id)
      if ui.mbLeftDown and noActiveItem():
        textFieldEnterEditMode(id, text, textBoxX)
        tf.state = tfEditLMBPressed

  proc clearSelection() =
    tf.selStartPos = -1
    tf.selEndPos = 0

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

    ui.focusCaptured = false
    showArrowCursor()

  # We 'fall through' to the edit state to avoid a 1-frame delay when going
  # into edit mode
  if tf.activeItem == id and tf.state >= tfEditLMBPressed:
    setHot(id)
    setActive(id)

    if tf.state == tfEditLMBPressed:
      if not ui.mbLeftDown:
        tf.state = tfEdit
    else:
      # LMB pressed outside the text field exits edit mode
      if ui.mbLeftDown and not mouseInside(x, y, w, h):
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

    proc insertString(s: string) =
      if s.len > 0:
        if hasSelection():
          let (startPos, endPos) = getSelection()
          text = text.runeSubStr(0, startPos) & s & text.runeSubStr(endPos)
          tf.cursorPos = startPos + s.runeLen()
          clearSelection()
        else:
          let insertPos = tf.cursorPos
          if insertPos == text.runeLen():
            text.add(s)
          else:
            text.insert(s, text.runeOffset(insertPos))
          inc(tf.cursorPos, s.runeLen())

    for ke in keyBufInternal():
      alias(shortcuts, textFieldEditShortcuts)
      let sc = mkKeyShortcut(ke.key, ke.mods)

      if sc in shortcuts[tesCursorOneCharLeft]:
        let newCursorPos = max(tf.cursorPos - 1, 0)
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesCursorOneCharRight]:
        let newCursorPos = min(tf.cursorPos + 1, text.runeLen)
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesCursorToPreviousWord]:
        let newCursorPos = findPrevWordStart()
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesCursorToNextWord]:
        let newCursorPos = findNextWordEnd()
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesCursorToLineStart]:
        let newCursorPos = 0
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesCursorToLineEnd]:
        let newCursorPos = text.runeLen
        clearSelection()
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionOneCharLeft]:
        let newCursorPos = max(tf.cursorPos - 1, 0)
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionOneCharRight]:
        let newCursorPos = min(tf.cursorPos + 1, text.runeLen)
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionToPreviousWord]:
        let newCursorPos = findPrevWordStart()
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionToNextWord]:
        let newCursorPos = findNextWordEnd()
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionToLineStart]:
        let newCursorPos = 0
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesSelectionToLineEnd]:
        let newCursorPos = text.runeLen
        updateSelection(newCursorPos)
        tf.cursorPos = newCursorPos

      elif sc in shortcuts[tesDeleteOneCharLeft]:
        if hasSelection():
          deleteSelection()
        elif tf.cursorPos > 0:
          text = text.runeSubStr(0, tf.cursorPos - 1) &
                 text.runeSubStr(tf.cursorPos)
          dec(tf.cursorPos)

      elif sc in shortcuts[tesDeleteOneCharRight]:
        if hasSelection():
          deleteSelection()
        elif text.len > 0:
            text = text.runeSubStr(0, tf.cursorPos) &
                   text.runeSubStr(tf.cursorPos + 1)

      elif sc in shortcuts[tesDeleteWordToRight]:
        if hasSelection():
          deleteSelection()
        else:
          let p = findNextWordEnd()
          text = text.runeSubStr(0, tf.cursorPos) & text.runeSubStr(p)

      elif sc in shortcuts[tesDeleteWordToLeft]:
        if hasSelection():
          deleteSelection()
        else:
          let p = findPrevWordStart()
          text = text.runeSubStr(0, p) & text.runeSubStr(tf.cursorPos)
          tf.cursorPos = p

      elif sc in shortcuts[tesDeleteToLineStart]:
        text = text.runeSubStr(tf.cursorPos)
        tf.cursorPos = 0

      elif sc in shortcuts[tesDeleteToLineEnd]:
        text = text.runeSubStr(0, tf.cursorPos)

      elif sc in shortcuts[tesSwitchChars]:
        discard # TODO

      elif sc in shortcuts[tesCutText]:
        if hasSelection():
          let (startPos, endPos) = getSelection()
          toClipboard(text.runeSubStr(startPos, endPos - startPos))
          deleteSelection()

      elif sc in shortcuts[tesCopyText]:
        if hasSelection():
          let (startPos, endPos) = getSelection()
          toClipboard(text.runeSubStr(startPos, endPos - startPos))

      elif sc in shortcuts[tesPasteText]:
        let s = fromClipboard()
        insertString(s)

      elif sc in shortcuts[tesAccept]:
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

      elif sc in shortcuts[tesCancel]:
        text = tf.originalText
        exitEditMode()
        # Note we won't process any remaining characters in the buffer
        # because exitEditMode() clears the key buffer.

    # Splice newly entered characters into the string.
    # (If we exited edit mode in the above key handler, this will result in
    # a noop as exitEditMode() clears the char buffer.)
    if not charBufEmpty():
      var newChars = consumeCharBuf()
      insertString(newChars)

  result = text

  # Draw text field
  let editing = tf.activeItem == id

  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif editing: dsActive
    else: dsNormal

  var
    textX = textBoxX
    textY = y + h*TextVertAlignFactor

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_LO
    else:        GRAY_MID

  let layer = if editing: TopLayer-3 else: ui.currentLayer

  addDrawLayer(layer, vg):
    # Draw text field background
    if drawWidget:
      vg.beginPath()
      vg.roundedRect(x, y, w, h, 5)
      vg.fillColor(fillColor)
      vg.fill()

    elif editing:
      vg.beginPath()
      vg.rect(textBoxX, textBoxY + 2, textBoxW, textBoxH - 2*2)
      vg.fillColor(fillColor)
      vg.fill()

    # Make scissor region slightly wider because of the cursor
    vg.scissor(textBoxX-3, textBoxY, textBoxW+3, textBoxH)

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

    vg.setFont(14.0)
    vg.fillColor(textColor)

    discard vg.text(textX, textY, text)

    vg.resetScissor()

  if isHot(id):
    handleTooltip(id, tooltip)


template rawTextField*(x, y, w, h: float,
                       tooltip:    string = "",
                       text:       string): string =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, tooltip, drawWidget = false, text)


template textField*(x, y, w, h: float,
                    tooltip:    string = "",
                    text:       string): string =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, tooltip, drawWidget = true, text)


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

  alias(ui, g_uiState)
  alias(sb, ui.scrollBarState)

  let
    x = x + ui.ox
    y = y + ui.oy

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
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
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
        ui.x0 = ui.mx
        if ui.shiftDown:
          hideCursor()
          sb.state = sbsDragHidden
        else:
          sb.state = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if ui.mx < thumbX: sb.clickDir = -1 * s
        else:               sb.clickDir =  1 * s
        sb.state = sbsTrackClickFirst
        ui.t0 = getTime()

    of sbsDragNormal:
      if ui.shiftDown:
        hideCursor()
        sb.state = sbsDragHidden
      else:
        let dx = ui.mx - ui.x0

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        ui.x0 = clamp(ui.mx, thumbMinX, thumbMaxX + thumbW)

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if ui.shiftDown:
        let d = if ui.altDown: ScrollBarUltraFineDragDivisor
                else:           ScrollBarFineDragDivisor
        let dx = (ui.mx - ui.x0) / d

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        ui.x0 = ui.mx
        ui.dragX = newThumbX + thumbW*0.5
        ui.dragY = -1.0
      else:
        sb.state = sbsDragNormal
        showCursor()
        setCursorPosX(ui.dragX)
        ui.mx = ui.dragX
        ui.x0 = ui.dragX

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbX = calcThumbX(newValue)

      sb.state = sbsTrackClickDelay
      ui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - ui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - ui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbX = calcThumbX(newValue)

          if sb.clickDir * sgn(endVal - startVal).float > 0:
            if newThumbX + thumbW > ui.mx:
              newThumbX = thumbX
              newValue = value
          else:
            if newThumbX < ui.mx:
              newThumbX = thumbX
              newValue = value

          ui.t0 = getTime()
      else:
        ui.t0 = getTime()

  result = newValue

  # Draw track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let trackColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
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

    vg.setFont(14.0)
    vg.fillColor(white())
    let valueString = fmt"{newValue:.3f}"
    let tw = vg.horizontalAdvance(valueString)
    discard vg.text(x + w*0.5 - tw*0.5, y + h*TextVertAlignFactor, valueString)

  if isHot(id):
    handleTooltip(id, tooltip)


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

  alias(ui, g_uiState)
  alias(sb, ui.scrollBarState)

  let
    x = x + ui.ox
    y = y + ui.oy

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
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
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
        ui.y0 = ui.my
        if ui.shiftDown:
          hideCursor()
          sb.state = sbsDragHidden
        else:
          sb.state = sbsDragNormal
      else:
        let s = sgn(endVal - startVal).float
        if ui.my < thumbY: sb.clickDir = -1 * s
        else:               sb.clickDir =  1 * s
        sb.state = sbsTrackClickFirst
        ui.t0 = getTime()

    of sbsDragNormal:
      if ui.shiftDown:
        hideCursor()
        sb.state = sbsDragHidden
      else:
        let dy = ui.my - ui.y0

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        ui.y0 = clamp(ui.my, thumbMinY, thumbMaxY + thumbH)

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if ui.shiftDown:
        let d = if ui.altDown: ScrollBarUltraFineDragDivisor
                else:           ScrollBarFineDragDivisor
        let dy = (ui.my - ui.y0) / d

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        ui.y0 = ui.my
        ui.dragX = -1.0
        ui.dragY = newThumbY + thumbH*0.5
      else:
        sb.state = sbsDragNormal
        showCursor()
        setCursorPosY(ui.dragY)
        ui.my = ui.dragY
        ui.y0 = ui.dragY

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick()
      newThumbY = calcThumbY(newValue)

      sb.state = sbsTrackClickDelay
      ui.t0 = getTime()

    of sbsTrackClickDelay:
      if getTime() - ui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat

    of sbsTrackClickRepeat:
      if isHot(id):
        if getTime() - ui.t0 > ScrollBarTrackClickRepeatTimeout:
          newValue = calcNewValueTrackClick()
          newThumbY = calcThumbY(newValue)

          if sb.clickDir * sgn(endVal - startVal).float > 0:
            if newThumbY + thumbH > ui.my:
              newThumbY = thumbY
              newValue = value
          else:
            if newThumbY < ui.my:
              newThumbY = thumbY
              newValue = value

          ui.t0 = getTime()
      else:
        ui.t0 = getTime()

  result = newValue

  # Draw track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let trackColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: GRAY_MID
    else:        GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
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

  if isHot(id):
    handleTooltip(id, tooltip)


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
  alias(ui, g_uiState)
  alias(sb, ui.scrollBarState)

  # Handle release active scrollbar outside of the widget
  if not ui.mbLeftDown and hasActiveItem():
    case sb.state:
    of sbsDragHidden:
      sb.state = sbsDefault
      showCursor()
      if ui.dragX > -1.0:
        setCursorPosX(ui.dragX)
      else:
        setCursorPosY(ui.dragY)

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

  alias(ui, g_uiState)
  alias(ss, ui.sliderState)

  let
    x = x + ui.ox
    y = y + ui.oy

  const SliderPad = 3

  let
    posMinX = x + SliderPad
    posMaxX = x + w - SliderPad

  # Calculate current slider position
  proc calcPosX(val: float): float =
    let t = invLerp(startVal, endVal, val)
    lerp(posMinX, posMaxX, t)

  let posX = calcPosX(value)

  # Hit testing
  if ss.editModeItem == id:
    setActive(id)
  elif isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # New position & value calculation
  var
    newPosX = posX
    value = value

  if isActive(id):
    case ss.state:
    of ssDefault:
      ui.x0 = ui.mx
      ui.dragX = ui.mx
      ui.dragY = -1.0
      ss.state = ssDragHidden
      ss.cursorMoved = false
      hideCursor()

    of ssDragHidden:
      if ui.dragX != ui.mx:
        ss.cursorMoved = true

      if not ui.mbLeftDown and not ss.cursorMoved:
        ss.state = ssEditValue
        ss.valueText = fmt"{value:.6f}"
        trimZeros(ss.valueText)
        ss.textFieldId = generateId(KoiInternalIdPrefix &
                                    "EditHorizSliderValue")
        const TextBoxPadX = 8
        textFieldEnterEditMode(ss.textFieldId, ss.valueText, x + TextBoxPadX)
        ss.editModeItem = id
        showCursor()
      else:
        # Technically, the cursor can move outside the widget when it's
        # disabled in "drag hidden" mode, and then it will cease to be "hot".
        # But in order to not break the tooltip processing logic, we're making
        # here sure the widget is always hot in "drag hidden" mode.
        setHot(id)

        let d = if ui.shiftDown:
          if ui.altDown: SliderUltraFineDragDivisor
          else:           SliderFineDragDivisor
        else: 1

        let dx = (ui.mx - ui.x0) / d

        newPosX = clamp(posX + dx, posMinX, posMaxX)
        let t = invLerp(posMinX, posMaxX, newPosX)
        value = lerp(startVal, endVal, t)
        ui.x0 = ui.mx

    of ssEditValue:
      # The textfield will only work correctly if it thinks it's active
      setActive(ss.textFieldId)

      ss.valueText = koi.textField(ss.textFieldId, x, y, w, h,
                                   tooltip = "", drawWidget = false,
                                   ss.valueText)

      if ui.textFieldState.state == tfDefault:
        value = try:
          let f = parseFloat(ss.valueText)
          if startVal < endVal: clamp(f, startVal, endVal)
          else:                 clamp(f, endVal, startVal)
        except: value

        newPosX = calcPosX(value)

        ss.editModeItem = -1
        ss.state = ssDefault

        # Needed for the tooltips to work correctly
        setHot(id)

        # The edit field is drawn on the top of everything else; we'll need
        # to remove it so we can draw the slider correctly
        g_drawLayers.removeLastAdded()

      else:
        # Reset hot & active to the current item so we won't confuse the
        # tooltip processing (among other things)
        setActive(id)
        setHot(id)


  result = value

  # Draw slider track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover: GRAY_HI
    else:       GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
    # Draw slider background
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(fillColor)
    vg.fill()

    if not (ss.editModeItem == id and ss.state == ssEditValue):
      # Draw slider value bar
      let sliderColor = case drawState
        of dsHover:  GRAY_LOHI
        of dsActive: RED
        else:        GRAY_LO

      vg.beginPath()
      vg.roundedRect(x + SliderPad, y + SliderPad,
                     newPosX - x - SliderPad, h - SliderPad*2, 5)
      vg.fillColor(sliderColor)
      vg.fill()

      # Draw slider text
      vg.setFont(14.0)
      vg.fillColor(white())
      let valueString = fmt"{value:.3f}"
      let tw = vg.horizontalAdvance(valueString)
      discard vg.text(x + w*0.5 - tw*0.5, y + h*TextVertAlignFactor, valueString)

  if isHot(id):
    handleTooltip(id, tooltip)


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

  alias(ui, g_uiState)
  alias(ss, ui.sliderState)

  let
    x = x + ui.ox
    y = y + ui.oy

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
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # New position & value calculation
  var
    newPosY = posY
    newValue = value

  if isActive(id):
    case ss.state:
    of ssDefault:
      ui.y0 = ui.my
      ui.dragX = -1.0
      ui.dragY = ui.my
      hideCursor()
      ss.state = ssDragHidden

    of ssDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      let d = if ui.shiftDown:
        if ui.altDown: SliderUltraFineDragDivisor
        else:           SliderFineDragDivisor
      else: 1

      let dy = (ui.my - ui.y0) / d

      newPosY = clamp(posY + dy, posMaxY, posMinY)
      let t = invLerp(posMinY, posMaxY, newPosY)
      newValue = lerp(startVal, endVal, t)
      ui.y0 = ui.my

    of ssEditValue:
      discard

  result = newValue

  # Draw slider track
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover: GRAY_HI
    else:       GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
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
    handleTooltip(id, tooltip)


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
  alias(ui, g_uiState)
  alias(ss, ui.sliderState)

  # Handle release active slider outside of the widget
  if not ui.mbLeftDown and hasActiveItem():
    if ss.state == ssDragHidden:
      ss.state = ssDefault
      showCursor()
      if ui.dragX > -1.0:
        setCursorPosX(ui.dragX)
      else:
        setCursorPosY(ui.dragY)

# }}}
# }}}

# {{{ Dialog

type
  DialogProc = proc ()

var
  g_dialogs = initTable[string, DialogProc]()

template dialog*(w, h: float, title: string, body: untyped) =
  alias(ui, g_uiState)

  let
    x = floor((ui.winWidth - w) / 2)
    y = floor((ui.winHeight - h) / 2)

  g_dialogs[title] = proc() =
    let oldCurrLayer = ui.currentLayer
    ui.currentLayer = oldCurrLayer + 2

    addDrawLayer(ui.currentLayer, vg):
      const TitleBarHeight = 30.0

      vg.beginPath()
      vg.fillColor(gray(0.1, 0.55))
      vg.rect(0, 0, ui.winWidth, ui.winHeight)
      vg.fill()

      vg.beginPath()
      vg.fillColor(gray(0.37))
      vg.rect(x, y, w, h)
      vg.fill()

      vg.beginPath()
      vg.fillColor(gray(0.1))
      vg.rect(x, y, w, TitleBarHeight)
      vg.fill()

      vg.fontFace("sans-bold")
      vg.fontSize(15.0)
      vg.textAlign(haLeft, vaMiddle)
      vg.fillColor(gray(0.5))
      discard vg.text(x+10.0, y + TitleBarHeight * TextVertAlignFactor, title)

    ui.ox = x
    ui.oy = y
    ui.insideDialog = true

    body

    ui.ox = 0
    ui.oy = 0
    ui.insideDialog = false
    ui.currentLayer = oldCurrLayer


proc openDialog*(title: string) =
  alias(ui, g_uiState)
  if ui.activeDialogTitle.isNone:
    if g_dialogs.hasKey(title):
      ui.activeDialogTitle = some(title)

proc closeDialog*() =
  alias(ui, g_uiState)
  ui.activeDialogTitle = none(string)

# }}}
# {{{ Menus
# {{{ menuBar

proc menuBar(id:         ItemId,
             x, y, w, h: float,
             names:      seq[string]): string =

  alias(ui, g_uiState)

  const PadX = 10

  var menuPosX: seq[float] = @[]

  var posX = x
  for name in names:
    posX += PadX
    menuPosX.add(posX)
    let tw = g_nvgContext.horizontalAdvance(name)
    posX += tw + PadX

  menuPosX.add(posX)

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    for i in 0..<menuPosX.high:
      if ui.mx >= menuPosX[i] and ui.mx < menuPosX[i+1]:
        echo fmt"inside {names[i]}"
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
#  if not ui.mbLeftDown and isHotAndActive(id):
#    result = true

  # Draw menu bar
  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif isHotAndActive(id): dsActive
    else: dsNormal

  let fillColor = case drawState
    of dsHover:  GRAY_HI
    of dsActive: RED
    else:        GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
    # Draw bar
    vg.beginPath()
    vg.rect(x, y, w, h)
    vg.fillColor(fillColor)
    vg.fill()

    vg.scissor(x, y, w, h)

    vg.setFont(14.0)
    vg.fillColor(GRAY_LO)

    for i in 0..names.high:
      discard vg.text(menuPosX[i], y + h*TextVertAlignFactor, names[i])

    vg.resetScissor()


template menuBar*(x, y, w, h: float, names: seq[string]): string =

  let i = instantiationInfo(fullPaths = true)
  let id = generateId(i.filename, i.line, "")

  menuBar(id, x, y, w, h, names)


proc beginMenuParentItem(name: string,
                         shortcut: Option[KeyEvent] = none(KeyEvent)) =
  discard

proc endMenuParentItem() =
  discard

template menuParentItem*(name: string,
                         shortcut: Option[KeyEvent] = none(KeyEvent)): bool =
  beginMenuParentItem(name, shortcut)
  endMenuParentItem()
  false


proc beginMenuBarItem(name: string) =
  discard

proc endMenuBarItem() =
  discard

template menuBarItem*(name: string, menuItems: untyped): untyped =
  beginMenuBarItem(name)
  menuItems
  endMenuBarItem()


proc menuItem*(name: string,
               shortcut: Option[KeyEvent] = none(KeyEvent),
               disabled = false,
               tooltip: string = ""): bool =
  result = false

proc menuItemSeparator*() =
  discard

# }}}
# }}}

# {{{ init*()

proc init*(nvg: NVGContext) =
  RED       = rgb(1.0, 0.4, 0.4)
  GRAY_MID  = gray(0.6)
  GRAY_HI   = gray(0.8)
  GRAY_LO   = gray(0.25)
  GRAY_LOHI = gray(0.35)

  g_nvgContext = nvg

  g_cursorArrow       = wrapper.createStandardCursor(csArrow)
  g_cursorIBeam       = wrapper.createStandardCursor(csIBeam)
  g_cursorHorizResize = wrapper.createStandardCursor(csHorizResize)

  let win = currentContext()
  win.keyCb  = keyCb
  win.charCb = charCb

  win.stickyMouseButtons = true

# }}}
# {{{ deinit*()

proc deinit*() =
  wrapper.destroyCursor(g_cursorArrow)
  wrapper.destroyCursor(g_cursorIBeam)
  wrapper.destroyCursor(g_cursorHorizResize)

# }}}
# {{{ beginFrame*()

proc beginFrame*(winWidth, winHeight: float) =
  let win = glfw.currentContext()

  alias(ui, g_uiState)

  ui.ox = 0
  ui.oy = 0
  ui.currentLayer = DefaultLayer

  ui.winWidth = winWidth
  ui.winHeight = winHeight

  # Store mouse state
  ui.lastmx = ui.mx
  ui.lastmy = ui.my

  (ui.mx, ui.my) = win.cursorPos()

  ui.mbLeftDown   = win.mouseButtonDown(mbLeft)
  ui.mbRightDown  = win.mouseButtonDown(mbRight)
  ui.mbMiddleDown = win.mouseButtonDown(mbMiddle)

  # Store modifier key state (just for convenience for the GUI functions)
  ui.shiftDown = win.isKeyDown(keyLeftShift) or
                 win.isKeyDown(keyRightShift)

  ui.ctrlDown  = win.isKeyDown(keyLeftControl) or
                 win.isKeyDown(keyRightControl)

  ui.altDown   = win.isKeyDown(keyLeftAlt) or
                 win.isKeyDown(keyRightAlt)

  ui.superDown = win.isKeyDown(keyLeftSuper) or
                 win.isKeyDown(keyRightSuper)

  # Reset hot item
  ui.hotItem = 0

  g_drawLayers.init()

# }}}
# {{{ endFrame*()

proc endFrame*() =
  alias(ui, g_uiState)

  # Dialogs need some special handling
  if ui.activeDialogTitle.isSome:
    let dialogProc = g_dialogs[ui.activeDialogTitle.get]
    dialogProc()

  # Post-frame processing
  tooltipPost()

  g_drawLayers.draw(g_nvgContext)

  ui.lastHotItem = ui.hotItem

  g_dialogs.clear()

  # Widget specific postprocessing
  #
  # NOTE: These must be called before the "Active state reset" section below
  # as they usually depend on the pre-reset value of the activeItem!
  scrollBarPost()
  sliderPost()

  # Active state reset
  if ui.mbLeftDown:
    if ui.activeItem == 0 and ui.hotItem == 0:
      # LMB was pressed outside of any widget. We need to mark this as
      # a separate state so we can't just "drag into" a widget while the LMB
      # is being depressed and activate it.
      ui.activeItem = -1
  else:
    if ui.activeItem != 0:
      # If the LMB was released inside the active widget, that has already
      # been handled at this point--we're just clearing the active item here.
      # This also takes care of the case when the LMB was depressed inside the
      # widget but released outside of it.
      ui.activeItem = 0

# }}}

# {{{ Read-only UI state properties

proc winWidth*():  float = g_uiState.winWidth
proc winHeight*(): float = g_uiState.winHeight

proc mx*(): float = g_uiState.mx
proc my*(): float = g_uiState.my

proc lastmx*(): float = g_uiState.lastmx
proc lastmy*(): float = g_uiState.lastmy

proc mbLeftDown*():   bool = g_uiState.mbLeftDown
proc mbRightDown*():  bool = g_uiState.mbRightDown
proc mbMiddleDown*(): bool = g_uiState.mbMiddleDown

proc shiftDown*(): bool = g_uiState.shiftDown
proc altDown*():   bool = g_uiState.altDown
proc ctrlDown*():  bool = g_uiState.ctrlDown
proc superDown*(): bool = g_uiState.superDown

# }}}

# vim: et:ts=2:sw=2:fdm=marker
