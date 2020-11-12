import hashes
import math
import lenientops
import options
import sets
import sequtils
import strformat
import strutils
import tables
import unicode

import glfw
from glfw/wrapper import setCursor, createStandardCursor, CursorShape
import nanovg

import ringbuffer
import utils

export CursorShape

# {{{ Types

type ItemId = int64

# {{{ TextSelection
type
  TextSelection = object
    # Rune position of the start of the selection (inclusive),
    # -1 if nothing is selected.
    startPos: int

    # Rune position of the end of the selection (exclusive)
    endPos:   Natural

# }}}

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
    tfsDefault,
    tfsEditLMBPressed,
    tfsEdit
    tfsDragStart,
    tfsDragDelay,
    tfsDragScroll,
    tfsDoubleClicked

  TextFieldStateVars = object
    state:           TextFieldState

    # The cursor is before the Rune with this index. If the cursor is at the end
    # of the text, the cursor pos equals the length of the text. From this
    # follows that the cursor position for an empty string is 0.
    cursorPos:       Natural

    # Current text selection
    selection:       TextSelection

    # Text field item in edit mode, 0 if no text field is being edited.
    activeItem:      ItemId

    # The text is displayed starting from the Rune with this index.
    displayStartPos: Natural

    # The text will be drawn at thix X coordinate (can be smaller than the
    # starting X coordinate of the textbox)
    displayStartX:   float

    # The original text is stored when going into edit mode so it can be
    # restored if the editing is cancelled.
    originalText:    string

    # State variables for tabbing back and forth between textfields
    prevItem:        ItemId
    lastActiveItem:  ItemId
    itemToActivate:  ItemId
    activateNext:    bool
    activatePrev:    bool

# }}}
# {{{ TextAreaState
type
  TextAreaState = enum
    tasDefault
    tasEditEntered,
    tasEdit
#    tasDragStart,
#    tasDragDelay,
#    tasDragScroll,
#    tasDoubleClicked

  TextAreaStateVars = object
    state:           TextAreaState

    # The cursor is before the Rune with this index. If the cursor is at the end
    # of the text, the cursor pos equals the length of the text. From this
    # follows that the cursor position for an empty string is 0.
    cursorPos:       Natural

    # Current text selection
    selection:       TextSelection

    # Text area item in edit mode, 0 if no text area is being edited.
    activeItem:      ItemId

    # The original text is stored when going into edit mode so it can be
    # restored if the editing is cancelled.
    originalText:    string

    # Used by the move cursor to next/previous line actions
    lastCursorXPos:  Option[float]

    # State variables for tabbing back and forth between textfields
    prevItem:        ItemId
    lastActiveItem:  ItemId
    itemToActivate:  ItemId
    activateNext:    bool
    activatePrev:    bool

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

# {{{ DrawState

type DrawState* = enum
  dsNormal, dsHover, dsActive, dsDisabled

# }}}

# {{{ UIState

type
  EventKind* = enum
    ekKey, ekMouse

  Event* = object
    case kind*: EventKind
    of ekKey:
      key*:     Key
      action*:  KeyAction

    of ekMouse:
      button*:  MouseButton
      pressed*: bool
      x*, y*:   float64

    mods*:      set[ModifierKey]


  UIState = object
    # General state
    # *************

    hasEvent:       bool
    currEvent:      Event
    eventHandled:   bool

    # Frames left to render
    framesLeft:     Natural

    # Origin offset, used for relative coordinate handling in dialogs
    ox, oy:         float

    # Widgets will be drawn on this layer by default
    currentLayer:   Natural

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

    # Time and position of the last left mouse button down event (for
    # double-click detenction)
    mbLeftDownT:     float
    mbLeftDownX:     float
    mbLeftDownY:     float
    lastMbLeftDownT: float
    lastMbLeftDownX: float
    lastMbLeftDownY: float

    cursorShape:     CursorShape

    # Keyboard state
    # --------------
    keyStates:      array[ord(Key.high), bool]

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
    textAreaState:  TextAreaStateVars
    scrollBarState: ScrollBarStateVars
    sliderState:    SliderStateVars

    # Internal tooltip state
    # **********************
    tooltipState:   TooltipStateVars

    # Dialog state
    # **********************
    # Only true when we're in a dialog (this is needed so widgets outside
    # of the dialog won't register any events).
    isDialogOpen:   bool
    insideDialog:   bool


# }}}
# }}}
# {{{ Globals

var
  g_nvgContext: NVGContext
  g_uiState: UIState

  g_cursorArrow:       Cursor
  g_cursorIBeam:       Cursor
  g_cursorCrosshair:   Cursor
  g_cursorHorizResize: Cursor
  g_cursorVertResize:  Cursor
  g_cursorHand:        Cursor

  # TODO remove these once theming is implemented
  HILITE     = rgb(1.0, 0.4, 0.4)
  HILITE_LO  = rgb(0.9, 0.3, 0.3)
  GRAY_MID   = gray(0.6)
  GRAY_HI    = gray(0.7)
  GRAY_LO    = gray(0.25)
  GRAY_LOHI  = gray(0.35)


# }}}
# {{{ Configuration

const
  TooltipShowDelay       = 0.4
  TooltipFadeOutDelay    = 0.1
  TooltipFadeOutDuration = 0.4

  TextFieldScrollDelay   = 0.1

  ScrollBarFineDragDivisor         = 10.0
  ScrollBarUltraFineDragDivisor    = 100.0
  ScrollBarTrackClickRepeatDelay   = 0.3
  ScrollBarTrackClickRepeatTimeout = 0.05

  SliderFineDragDivisor      = 10.0
  SliderUltraFineDragDivisor = 100.0

  TextVertAlignFactor = 0.55

  DoubleClickMaxDelay = 0.1
  DoubleClickMaxXOffs = 4
  DoubleClickMaxYOffs = 4

# }}}

# {{{ Utils

func snapToGrid(x, y, w, h, sw: float): (float, float, float, float) =
  let s = (sw mod 2) / 2
  let
    x = x - s
    y = y - s
    w = w + s*2
    h = h + s*2
  result = (x, y, w, h)

proc setFont*(vg: NVGContext, size: float, name: string = "sans-bold",
              horizAlign: HorizontalAlign = haLeft,
              vertAlign: VerticalAlign = vaMiddle) =
  vg.fontFace(name)
  vg.fontSize(size)
  vg.textAlign(horizAlign, vertAlign)

# {{{ drawLabel()
proc drawLabel(vg: NVGContext, x, y, w, h, padHoriz: float,
               label: string, color: Color,
               fontSize: float, fontFace: string, align: HorizontalAlign,
               multiLine: bool = false, lineHeight: float = 1.4) =
  let
    textBoxX = x + padHoriz
    textBoxW = w - padHoriz*2
    textBoxY = y
    textBoxH = h

  let tx = case align:
  of haLeft:   textBoxX
  of haCenter: textBoxX + textBoxW*0.5
  of haRight:  textBoxX + textBoxW

  let ty = y + h*TextVertAlignFactor

  vg.save()

  vg.intersectScissor(textBoxX, textBoxY, textBoxW, textBoxH)

  vg.setFont(fontSize, fontFace, align)
  vg.fillColor(color)

  if multiLine:
    vg.textLineHeight(lineHeight)
    vg.textBox(tx, ty, textBoxW, label)
  else:
    discard vg.text(tx, ty, label)

  vg.restore()


# }}}

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

template generateId*(filename: string, line: int, id: string): ItemId =
  generateId(filename & ":" & $line & ":" & id)

proc setFramesLeft*(i: Natural = 2) =
  alias(ui, g_uiState)
  ui.framesLeft = 2

proc mouseInside*(x, y, w, h: float): bool =
  alias(ui, g_uiState)
  ui.mx >= x and ui.mx <= x+w and
  ui.my >= y and ui.my <= y+h

proc isHot*(id: ItemId): bool =
  g_uiState.hotItem == id

proc setHot*(id: ItemId) =
  alias(ui, g_uiState)
  ui.hotItem = id

proc isActive*(id: ItemId): bool =
  g_uiState.activeItem == id

proc setActive*(id: ItemId) =
  g_uiState.activeItem = id

# TODO remove
proc isHotAndActive*(id: ItemId): bool =
  isHot(id) and isActive(id)

proc hasHotItem*(): bool =
  g_uiState.hotItem > 0

proc noActiveItem*(): bool =
  g_uiState.activeItem == 0

proc hasActiveItem*(): bool =
  g_uiState.activeItem > 0

proc isDialogOpen*(): bool =
  g_uiState.isDialogOpen

proc isHit*(x, y, w, h: float): bool =
  alias(ui, g_uiState)
  let hit = not ui.focusCaptured and
            (ui.insideDialog or not ui.isDialogOpen) and
            mouseInside(x, y, w, h)

  # TODO
  # Draw another frame after the current frame (some widgets need one extra
  # frame to refresh properly after finishing the interaction with them).
  hit

proc winWidth*():  float = g_uiState.winWidth
proc winHeight*(): float = g_uiState.winHeight

proc mx*(): float = g_uiState.mx
proc my*(): float = g_uiState.my

proc lastmx*(): float = g_uiState.lastmx
proc lastmy*(): float = g_uiState.lastmy


proc hasEvent*(): bool =
  alias(ui, g_uiState)

  template calcHasEvent(): bool =
    ui.hasEvent and (not ui.eventHandled) and not ui.focusCaptured

  if ui.isDialogOpen:
    if ui.insideDialog: calcHasEvent()
    else: false
  else: calcHasEvent()


proc currEvent*(): Event = g_uiState.currEvent

proc mbLeftDown*():   bool = g_uiState.mbLeftDown
proc mbRightDown*():  bool = g_uiState.mbRightDown
proc mbMiddleDown*(): bool = g_uiState.mbMiddleDown

proc keyDown*(key: Key): bool =
  if key == keyUnknown: false
  else: g_uiState.keyStates[ord(key)]

proc shiftDown*(): bool = keyDown(keyLeftShift)   or keyDown(keyRightShift)
proc altDown*():   bool = keyDown(keyLeftAlt)     or keyDown(keyRightAlt)
proc ctrlDown*():  bool = keyDown(keyLeftControl) or keyDown(keyRightControl)
proc superDown*(): bool = keyDown(keyLeftSuper)   or keyDown(keyRightSuper)

# }}}
# {{{ Keyboard handling

type KeyShortcut* = object
  key*:    Key
  mods*:   set[ModifierKey]

proc mkKeyShortcut*(k: Key, m: set[ModifierKey]): KeyShortcut {.inline.} =
  # always ignore caps lock state
  var m = m - {mkCapsLock}

  # ignore numlock state mod non-keypad shortcuts
  if not (k >= keyKp0 and k <= keyKpDecimal):
    m =  m - {mkNumLock}

  KeyShortcut(key: k, mods: m)


# {{{ Shortcut definitions

type TextEditShortcuts = enum
  tesCursorOneCharLeft,
  tesCursorOneCharRight,
  tesCursorToPreviousWord,
  tesCursorToNextWord,
  tesCursorToPreviousLine,
  tesCursorToNextLine,
  tesCursorToLineStart,
  tesCursorToLineEnd,
  tesCursorToDocumentStart,
  tesCursorToDocumentEnd,

  tesSelectionAll,
  tesSelectionOneCharLeft,
  tesSelectionOneCharRight,
  tesSelectionToPreviousWord,
  tesSelectionToNextWord,
  tesSelectionToPreviousLine,
  tesSelectionToNextLine,
  tesSelectionToLineStart,
  tesSelectionToLineEnd,
  tesSelectionToDocumentStart,
  tesSelectionToDocumentEnd,

  tesDeleteOneCharLeft,
  tesDeleteOneCharRight,
  tesDeleteWordToRight,
  tesDeleteWordToLeft,
  tesDeleteToLineStart,
  tesDeleteToLineEnd,

  tesCutText,
  tesCopyText,
  tesPasteText,

  tesPrevTextField, # TODO "global" widget level shortcut
  tesNextTextField, # TODO "global" widget level shortcut

  tesAccept,
  tesCancel


# {{{ Shortcuts - Windows/Linux

let g_textFieldEditShortcuts_WinLinux = {

  # Cursor movement
  tesCursorOneCharLeft:       @[mkKeyShortcut(keyLeft,    {}),
                                mkKeyShortcut(keyKp4,     {})],

  tesCursorOneCharRight:      @[mkKeyShortcut(keyRight,   {}),
                                mkKeyShortcut(keyKp6,     {})],

  tesCursorToPreviousWord:    @[mkKeyShortcut(keyLeft,    {mkCtrl}),
                                mkKeyShortcut(keyKp4,     {mkCtrl}),
                                mkKeyShortcut(keySlash,   {mkCtrl})],

  tesCursorToNextWord:        @[mkKeyShortcut(keyRight,   {mkCtrl}),
                                mkKeyShortcut(keyKp6,     {mkCtrl})],

  tesCursorToPreviousLine:    @[mkKeyShortcut(keyUp,      {}),
                                mkKeyShortcut(keyKp8,     {})],

  tesCursorToNextLine:       @[mkKeyShortcut(Key.keyDown, {}),
                               mkKeyShortcut(keyKp2,      {})],

  tesCursorToLineStart:       @[mkKeyShortcut(keyHome,    {}),
                                mkKeyShortcut(keyKp7,     {})],

  tesCursorToLineEnd:         @[mkKeyShortcut(keyEnd,     {}),
                                mkKeyShortcut(keyKp1,     {})],

  tesCursorToDocumentStart:   @[mkKeyShortcut(keyHome,    {mkCtrl}),
                                mkKeyShortcut(keyKp7,     {mkCtrl})],

  tesCursorToDocumentEnd:     @[mkKeyShortcut(keyEnd,     {mkCtrl}),
                                mkKeyShortcut(keyKp1,     {mkCtrl})],

  # Selection
  tesSelectionAll:            @[mkKeyShortcut(keyA,       {mkCtrl})],

  tesSelectionOneCharLeft:    @[mkKeyShortcut(keyLeft,    {mkShift}),
                                mkKeyShortcut(keyKp4,     {mkShift})],

  tesSelectionOneCharRight:   @[mkKeyShortcut(keyRight,   {mkShift}),
                                mkKeyShortcut(keyKp6,     {mkShift})],

  tesSelectionToPreviousWord: @[mkKeyShortcut(keyLeft,    {mkCtrl, mkShift}),
                                mkKeyShortcut(keykp4,     {mkCtrl, mkShift})],

  tesSelectionToNextWord:     @[mkKeyShortcut(keyRight,   {mkCtrl, mkShift}),
                                mkKeyShortcut(keykp6,     {mkCtrl, mkShift})],

  tesSelectionToPreviousLine: @[mkKeyShortcut(keyUp,      {mkShift}),
                                mkKeyShortcut(keyKp8,     {mkShift})],

  tesSelectionToNextLine:    @[mkKeyShortcut(Key.keyDown, {mkShift}),
                               mkKeyShortcut(keyKp2,      {mkShift})],

  tesSelectionToLineStart:    @[mkKeyShortcut(keyHome,    {mkShift}),
                                mkKeyShortcut(keyKp7,     {mkShift})],

  tesSelectionToLineEnd:      @[mkKeyShortcut(keyEnd,     {mkShift}),
                                mkKeyShortcut(keyKp1,     {mkShift})],

  tesSelectionToDocumentStart:   @[mkKeyShortcut(keyHome, {mkCtrl, mkShift}),
                                mkKeyShortcut(keyKp7,     {mkCtrl, mkShift})],

  tesSelectionToDocumentEnd:  @[mkKeyShortcut(keyEnd,     {mkCtrl, mkShift}),
                                mkKeyShortcut(keyKp1,     {mkCtrl, mkShift})],

  # Delete
  tesDeleteOneCharLeft:     @[mkKeyShortcut(keyBackspace, {})],

  tesDeleteOneCharRight:    @[mkKeyShortcut(keyDelete,    {}),
                              mkKeyShortcut(keyKpDecimal, {})],

  tesDeleteWordToRight:     @[mkKeyShortcut(keyDelete,    {mkCtrl}),
                              mkKeyShortcut(keykpDecimal, {mkCtrl})],

  tesDeleteWordToLeft:      @[mkKeyShortcut(keyBackspace, {mkCtrl})],

  tesDeleteToLineStart:     @[mkKeyShortcut(keyBackspace, {mkCtrl, mkShift})],

  tesDeleteToLineEnd:       @[mkKeyShortcut(keyDelete,    {mkCtrl, mkShift}),
                              mkKeyShortcut(keykpDecimal, {mkCtrl, mkShift})],

  # Clipboard
  tesCutText:                 @[mkKeyShortcut(keyX,       {mkCtrl})],
  tesCopyText:                @[mkKeyShortcut(keyC,       {mkCtrl})],
  tesPasteText:               @[mkKeyShortcut(keyV,       {mkCtrl})],

  # General
  tesPrevTextField:           @[mkKeyShortcut(keyTab,     {mkShift})],
  tesNextTextField:           @[mkKeyShortcut(keyTab,     {})],

  tesAccept:                  @[mkKeyShortcut(keyEnter,   {}),
                                mkKeyShortcut(keyKpEnter, {})],

  tesCancel:              @[mkKeyShortcut(keyEscape,      {}),
                            mkKeyShortcut(keyLeftBracket, {mkCtrl})]
}.toTable

# }}}
# {{{ Shortcuts - Mac
# TODO update
let g_textFieldEditShortcuts_Mac = {
  tesPrevTextField:        @[mkKeyShortcut(keyTab,       {mkShift})],
  tesNextTextField:        @[mkKeyShortcut(keyTab,       {})],


  tesCursorOneCharLeft:    @[mkKeyShortcut(keyLeft,      {}),
                             mkKeyShortcut(keyB,         {mkCtrl})],

  tesCursorOneCharRight:   @[mkKeyShortcut(keyRight,     {}),
                             mkKeyShortcut(keyF,         {mkCtrl})],

  tesCursorToPreviousWord: @[mkKeyShortcut(keyLeft,      {mkAlt})],
  tesCursorToNextWord:     @[mkKeyShortcut(keyRight,     {mkAlt})],

  tesCursorToPreviousLine,
  tesCursorToNextLine,

  tesCursorToLineStart:    @[mkKeyShortcut(keyLeft,      {mkSuper}),
                             mkKeyShortcut(keyA,         {mkCtrl}),
                             mkKeyShortcut(keyP,         {mkCtrl}),
                             mkKeyShortcut(keyV,         {mkShift, mkCtrl}),
                             mkKeyShortcut(keyUp,        {})],

  tesCursorToLineEnd:      @[mkKeyShortcut(keyRight,     {mkSuper}),
                             mkKeyShortcut(keyE,         {mkCtrl}),
                             mkKeyShortcut(keyN,         {mkCtrl}),
                             mkKeyShortcut(keyV,         {mkCtrl}),
                             mkKeyShortcut(Key.keyDown,  {})],

  tesCursorToDocumentStart,
  tesCursorToDocumentEnd,


  tesSelectionAll,

  tesSelectionOneCharLeft:    @[mkKeyShortcut(keyLeft,   {mkShift})],
  tesSelectionOneCharRight:   @[mkKeyShortcut(keyRight,  {mkShift})],
  tesSelectionToPreviousWord: @[mkKeyShortcut(keyLeft,   {mkShift, mkAlt})],
  tesSelectionToNextWord:     @[mkKeyShortcut(keyRight,  {mkShift, mkAlt})],

  tesSelectionToLineStart: @[mkKeyShortcut(keyLeft,      {mkShift, mkSuper}),
                             mkKeyShortcut(keyA,         {mkShift, mkCtrl}),
                             mkKeyShortcut(keyUp,        {mkShift})],

  tesSelectionToLineEnd:   @[mkKeyShortcut(keyRight,     {mkShift, mkSuper}),
                             mkKeyShortcut(keyE,         {mkShift, mkCtrl}),
                             mkKeyShortcut(Key.keyDown,  {mkShift})],


  tesDeleteOneCharLeft:    @[mkKeyShortcut(keyBackspace, {}),
                             mkKeyShortcut(keyH,         {mkCtrl})],

  tesDeleteOneCharRight:   @[mkKeyShortcut(keyDelete,    {})],

  tesDeleteWordToRight:    @[mkKeyShortcut(keyDelete,    {mkAlt}),
                             mkKeyShortcut(keyD,         {mkCtrl})],

  tesDeleteWordToLeft:     @[mkKeyShortcut(keyBackspace, {mkAlt})],
  tesDeleteToLineStart:    @[mkKeyShortcut(keyBackspace, {mkSuper})],

  tesDeleteToLineEnd:      @[mkKeyShortcut(keyDelete,    {mkAlt}),
                             mkKeyShortcut(keyK,         {mkCtrl})],

  tesCutText:              @[mkKeyShortcut(keyX,         {mkSuper})],
  tesCopyText:             @[mkKeyShortcut(keyC,         {mkSuper})],
  tesPasteText:            @[mkKeyShortcut(keyV,         {mkSuper})],

  tesAccept:               @[mkKeyShortcut(keyEnter,     {}),
                             mkKeyShortcut(keyKpEnter,   {})],

  tesCancel:               @[mkKeyShortcut(keyEscape,    {}),
                             mkKeyShortcut(keyLeftBracket, {mkCtrl})]
}.toTable

# }}}

# TODO make this configurable
let g_textFieldEditShortcuts = g_textFieldEditShortcuts_WinLinux

# }}}

const CharBufSize = 256
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


# TODO do we need locking around this stuff? written in the callback, read
# from the UI code
const EventBufSize = 64
var g_eventBuf = initRingBuffer[Event](EventBufSize)


proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           mods: set[ModifierKey]) =

  alias(ui, g_uiState)

  let keyIdx = ord(key)
  if keyIdx >= 0 and keyIdx <= ui.keyStates.high:
    case action
    of kaDown, kaRepeat: ui.keyStates[keyIdx] = true
    of kaUp:             ui.keyStates[keyIdx] = false

  let event = Event(
    kind: ekKey,
    key: key, action: action, mods: mods
  )
  discard g_eventBuf.write(event)


proc clearEventBuf*() = g_eventBuf.clear()


# }}}
# {{{ Mouse handling

proc mouseButtonCb(win: Window, button: MouseButton, pressed: bool,
                   modKeys: set[ModifierKey]) =

  let (x, y) = win.cursorPos()

  discard g_eventBuf.write(
    Event(
      kind: ekMouse,
      button: button,
      pressed: pressed,
      x: x,
      y: y,
      mods: modKeys
    )
  )

proc showCursor*() =
  glfw.currentContext().cursorMode = cmNormal

proc hideCursor*() =
  glfw.currentContext().cursorMode = cmHidden

proc disableCursor*() =
  glfw.currentContext().cursorMode = cmDisabled

proc setCursorShape*(cs: CursorShape) =
  g_uiState.cursorShape = cs

proc setCursorMode(cs: CursorShape) =
  let win = glfw.currentContext()

  var c: Cursor
  if   cs == csArrow:       c = g_cursorArrow
  elif cs == csIBeam:       c = g_cursorIBeam
  elif cs == csCrosshair:   c = g_cursorCrosshair
  elif cs == csHand:        c = g_cursorHand
  elif cs == csHorizResize: c = g_cursorHorizResize
  elif cs == csVertResize:  c = g_cursorVertResize

  wrapper.setCursor(win.getHandle, c)


proc setCursorPosX*(x: float) =
  let win = glfw.currentContext()
  let (_, currY) = win.cursorPos()
  win.cursorPos = (x, currY)

proc setCursorPosY*(y: float) =
  let win = glfw.currentContext()
  let (currX, _) = win.cursorPos()
  win.cursorPos = (currX, y)


proc isDoubleClick*(): bool =
  alias(ui, g_uiState)

  ui.mbLeftDown and
  getTime() - ui.lastMbLeftDownT <= DoubleClickMaxDelay and
  abs(ui.lastMbLeftDownX - ui.mx) <= DoubleClickMaxXOffs and
  abs(ui.lastMbLeftDownY - ui.my) <= DoubleClickMaxYOffs

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
      setFramesLeft()

    # Hide the tooltip immediately if the LMB is pressed inside the widget
    if ui.mbLeftDown and hasActiveItem():
      tt.state = tsOff

    # Start the show delay if we just entered the widget with LMB up and no
    # other tooltip is being shown
    elif tt.state == tsOff and not ui.mbLeftDown and
         ui.lastHotItem != id:
      tt.state = tsShowDelay
      tt.t0 = getTime()
      setFramesLeft()

    elif tt.state >= tsShow:
      tt.state = tsShow
      tt.t0 = getTime()
      tt.text = tooltip
      setFramesLeft()

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

    vg.setFont(13.0)
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

  # Make sure to keep drawing until the tooltip animation cycle is over
  if tt.state > tsOff:
    setFramesLeft()

  if tt.state == tsShow:
    ui.framesLeft = 0

# }}}
# }}}

# {{{ Label

type LabelStyle* = ref object
  multiLine*:  bool
  fontSize*:   float
  fontFace*:   string
  align*:      HorizontalAlign
  lineHeight*: float
  color*:      Color

var DefaultLabelStyle = LabelStyle(
  multiLine  : false,
  fontSize   : 14.0,
  fontFace   : "sans-bold",
  align      : haCenter,
  lineHeight : 1.4,
  color      : GRAY_LO
)

proc getDefaultLabelStyle*(): LabelStyle =
  DefaultLabelStyle.deepCopy

proc setDefaultLabelStyle*(style: LabelStyle) =
  DefaultLabelStyle = style.deepCopy

proc textLabel(id:         ItemId,
               x, y, w, h: float,
               label:      string,
               style:      LabelStyle) =

  alias(ui, g_uiState)
  alias(s, style)

  let x = x + ui.ox
  let y = y + ui.oy

  addDrawLayer(ui.currentLayer, vg):
    vg.drawLabel(x, y, w, h, padHoriz = 0, label, s.color,
                 s.fontSize, s.fontFace, s.align, s.multiLine, s.lineHeight)


template label*(x, y, w, h: float,
                label:      string,
                style:      LabelStyle = DefaultLabelStyle) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textLabel(id, x, y, w, h, label, style)

# }}}
# {{{ Button

type ButtonStyle* = ref object
  buttonCornerRadius*:        float
  buttonStrokeWidth*:         float
  buttonStrokeColor*:         Color
  buttonStrokeColorHover*:    Color
  buttonStrokeColorDown*:     Color
  buttonStrokeColorDisabled*: Color
  buttonFillColor*:           Color
  buttonFillColorHover*:      Color
  buttonFillColorDown*:       Color
  buttonFillColorDisabled*:   Color
  labelPadHoriz*:             float
  labelFontSize*:             float
  labelFontFace*:             string
  labelOnly*:                 bool
  labelAlign*:                HorizontalAlign
  labelColor*:                Color
  labelColorHover*:           Color
  labelColorDown*:            Color
  labelColorDisabled*:        Color

var DefaultButtonStyle = ButtonStyle(
  buttonCornerRadius        : 5,
  buttonStrokeWidth         : 0,
  buttonStrokeColor         : black(),
  buttonStrokeColorHover    : black(),
  buttonStrokeColorDown     : black(),
  buttonStrokeColorDisabled : black(),
  buttonFillColor           : gray(0.6),
  buttonFillColorHover      : GRAY_HI,
  buttonFillColorDown       : HILITE,
  buttonFillColorDisabled   : GRAY_LO,
  labelPadHoriz             : 8,
  labelFontSize             : 14.0,
  labelFontFace             : "sans-bold",
  labelOnly                 : false,
  labelAlign                : haCenter,
  labelColor                : GRAY_LO,
  labelColorHover           : GRAY_LO,
  labelColorDown            : GRAY_LO,
  labelColorDisabled        : GRAY_MID
)

proc getDefaultButtonStyle*(): ButtonStyle =
  DefaultButtonStyle.deepCopy

proc setDefaultButtonStyle*(style: ButtonStyle) =
  DefaultButtonStyle = style.deepCopy


proc button(id:         ItemId,
            x, y, w, h: float,
            label:      string,
            tooltip:    string,
            disabled:   bool,
            style:      ButtonStyle): bool =

  alias(ui, g_uiState)
  alias(s, style)

  let x = x + ui.ox
  let y = y + ui.oy

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if not disabled and ui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHotAndActive(id):
    result = true

  addDrawLayer(ui.currentLayer, vg):
    let sw = s.buttonStrokeWidth
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let drawState = if disabled: dsDisabled
      elif isHot(id) and noActiveItem(): dsHover
      elif isHotAndActive(id): dsActive
      else: dsNormal

    let (fillColor, strokeColor, labelColor) =
      case drawState
      of dsNormal:
        (s.buttonFillColor, s.buttonStrokeColor, s.labelColor)
      of dsHover:
        (s.buttonFillColorHover, s.buttonStrokeColorHover, s.labelColorHover)
      of dsActive:
        (s.buttonFillColorDown, s.buttonStrokeColorDown, s.labelColorDown)
      of dsDisabled:
        (s.buttonFillColorDisabled, s.buttonStrokeColorDisabled,
         s.labelColorDisabled)

    if not s.labelOnly:
      vg.fillColor(fillColor)
      vg.strokeColor(strokeColor)
      vg.strokeWidth(sw)
      vg.beginPath()
      vg.roundedRect(x, y, w, h, s.buttonCornerRadius)
      vg.fill()
      vg.stroke()

    vg.drawLabel(x, y, w, h, s.labelPadHoriz, label, labelColor,
                 s.labelFontSize, s.labelFontFace, s.labelAlign)

  if isHot(id):
    handleTooltip(id, tooltip)


template button*(x, y, w, h: float,
                 label:      string,
                 tooltip:    string = "",
                 disabled:   bool = false,
                 style:      ButtonStyle = DefaultButtonStyle): bool =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  button(id, x, y, w, h, label, tooltip, disabled, style)

# }}}
# {{{ CheckBox

type CheckBoxStyle* = ref object
  cornerRadius*:        float
  strokeWidth*:         float
  strokeColor*:         Color
  strokeColorHover*:    Color
  strokeColorDown*:     Color
  strokeColorActive*:   Color
  fillColor*:           Color
  fillColorHover*:      Color
  fillColorDown*:       Color
  fillColorActive*:     Color
  iconColor*:           Color
  iconColorHover*:      Color
  iconColorDown*:       Color
  iconColorActive*:     Color
  iconFontSize*:        float
  iconFontFace*:        string
  iconActive*:          string
  iconInactive*:        string

var DefaultCheckBoxStyle = CheckBoxStyle(
  cornerRadius      : 5,
  strokeWidth       : 0,
  strokeColor       : black(),
  strokeColorHover  : black(),
  strokeColorDown   : black(),
  strokeColorActive : black(),
  fillColor         : GRAY_MID,
  fillColorHover    : GRAY_HI,
  fillColorDown     : GRAY_LOHI,
  fillColorActive   : GRAY_LO,
  iconColor         : GRAY_LO,
  iconColorHover    : GRAY_LO,
  iconColorDown     : GRAY_HI,
  iconColorActive   : GRAY_HI,
  iconFontSize      : 14.0,
  iconFontFace      : "sans-bold",
  iconActive        : "X",
  iconInactive      : "/"
)

proc getDefaultCheckBoxStyle*(): CheckBoxStyle =
  DefaultCheckBoxStyle.deepCopy

proc setDefaultCheckBoxStyle*(style: CheckBoxStyle) =
  DefaultCheckBoxStyle = style.deepCopy


proc checkBox(id:      ItemId,
              x, y, w: float,
              active:  bool,
              tooltip: string,
              style:   CheckBoxStyle): bool =

  alias(ui, g_uiState)
  alias(s, style)

  let x = x + ui.ox
  let y = y + ui.oy

  # Hit testing
  if isHit(x, y, w, w):
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  let active = if not ui.mbLeftDown and isHotAndActive(id): not active
               else: active

  result = active

  addDrawLayer(ui.currentLayer, vg):
    let sw = s.strokeWidth
    let (x, y, w, _) = snapToGrid(x, y, w, w, sw)

    let drawState = if isHot(id) and noActiveItem(): dsHover
      elif isHotAndActive(id): dsActive
      else: dsNormal

    var (fillColor, strokeColor, iconColor) =
      if active:
        (s.fillColorActive, s.strokeColorActive, s.iconColorActive)
      else:
        case drawState
        of dsNormal:
          (s.fillColor, s.strokeColor, s.iconColor)
        of dsHover:
          (s.fillColorHover, s.strokeColorHover, s.iconColorHover)
        of dsActive:
          (s.fillColorDown, s.strokeColorDown, s.iconColorDown)
        of dsDisabled:
          # TODO
          (s.fillColorDown, s.strokeColorDown, s.iconColorDown)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)
    vg.beginPath()
    vg.roundedRect(x, y, w, w, s.cornerRadius)
    vg.fill()
    vg.stroke()

    let icon = if active: s.iconActive else: s.iconInactive
    if icon != "":
      vg.drawLabel(x, y, w, w, 0, icon, iconColor,
                   s.iconFontSize, s.iconFontFace, haCenter)

  if isHot(id):
    handleTooltip(id, tooltip)


template checkBox*(x, y, w: float,
                   active:  bool,
                   tooltip: string = "",
                   style:   CheckBoxStyle = DefaultCheckBoxStyle): bool =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  checkbox(id, x, y, w, active, tooltip, style)

# }}}
# {{{ RadioButtons

type RadioButtonsStyle* = ref object
  buttonPadHoriz*:           float
  buttonPadVert*:            float
  buttonCornerRadius*:       float
  buttonStrokeWidth*:        float
  buttonStrokeColor*:        Color
  buttonStrokeColorHover*:   Color
  buttonStrokeColorDown*:    Color
  buttonStrokeColorActive*:  Color
  buttonFillColor*:          Color
  buttonFillColorHover*:     Color
  buttonFillColorDown*:      Color
  buttonFillColorActive*:    Color
  labelPadHoriz*:            float
  labelFontSize*:            float
  labelFontFace*:            string
  labelOnly*:                bool
  labelAlign*:               HorizontalAlign
  labelColor*:               Color
  labelColorHover*:          Color
  labelColorActive*:         Color
  labelColorDown*:           Color

var DefaultRadioButtonsStyle = RadioButtonsStyle(
  buttonPadHoriz           : 3,
  buttonPadVert            : 3,
  buttonCornerRadius       : 5,
  buttonStrokeWidth        : 0,
  buttonStrokeColor        : black(),
  buttonStrokeColorHover   : black(),
  buttonStrokeColorDown    : black(),
  buttonStrokeColorActive  : black(),
  buttonFillColor          : GRAY_MID,
  buttonFillColorHover     : GRAY_HI,
  buttonFillColorDown      : HILITE_LO,
  buttonFillColorActive    : HILITE,
  labelPadHoriz            : 8,
  labelFontSize            : 14.0,
  labelFontFace            : "sans-bold",
  labelOnly                : false,
  labelAlign               : haCenter,
  labelColor               : GRAY_LO,
  labelColorHover          : GRAY_LO,
  labelColorActive         : GRAY_LO,
  labelColorDown           : GRAY_LO
)

proc getDefaultRadioButtonsStyle*(): RadioButtonsStyle =
  DefaultRadioButtonsStyle.deepCopy

proc setDefaultRadioButtonsStyle*(style: RadioButtonsStyle) =
  DefaultRadioButtonsStyle = style.deepCopy


type
  RadioButtonsLayoutKind* = enum
    rblHoriz, rblGridHoriz, rblGridVert

  RadioButtonsLayout* = object
    case kind*: RadioButtonsLayoutKind
    of rblHoriz: discard
    of rblGridHoriz: itemsPerRow*:    Natural
    of rblGridVert:  itemsPerColumn*: Natural

  RadioButtonsDrawProc* = proc (vg: NVGContext, buttonIdx: Natural,
                                label: string,
                                hover, active, down, first, last: bool,
                                x, y, w, h: float,
                                style: RadioButtonsStyle)


let DefaultRadioButtonDrawProc: RadioButtonsDrawProc =
  proc (vg: NVGContext, buttonIdx: Natural, label: string,
        hover, active, down, first, last: bool,
        x, y, w, h: float, style: RadioButtonsStyle) =

    alias(s, style)

    let (fillColor, strokeColor, labelColor) =
      if active: (s.buttonFillColorActive, s.buttonStrokeColorActive,
                  s.labelColorActive)
      else:
        if hover:
          (s.buttonFillColorHover, s.buttonStrokeColorHover, s.labelColorHover)
        elif down:
          (s.buttonFillColorDown, s.buttonStrokeColorDown, s.labelColorDown)
        else:
          (s.buttonFillColor, s.buttonStrokeColor, s.labelColor)

    let
      sw = s.buttonStrokeWidth
      buttonW = w - s.buttonPadHoriz
      bx = round(x)
      bw = round(x + buttonW) - bx
      bh = h - s.buttonPadVert

    vg.save()

    vg.setFont(s.labelFontSize)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)
    vg.beginPath()

    let cr = s.buttonCornerRadius
    if   first: vg.roundedRectVarying(bx, y, bw, bh, cr, 0, 0, cr)
    elif last:  vg.roundedRectVarying(bx, y, bw, bh, 0, cr, cr, 0)
    else:       vg.rect(bx, y, bw, bh)

    vg.fill()
    vg.stroke()

    let
      textBoxX = bx + s.labelPadHoriz
      textBoxW = bw - s.labelPadHoriz*2
      textBoxY = y
      textBoxH = bh

    vg.intersectScissor(textBoxX, textBoxY, textBoxW, textBoxH)

    vg.fillColor(labelColor)
    let tw = vg.textWidth(label)
    discard vg.text(bx + bw*0.5 - tw*0.5, y + bh*TextVertAlignFactor,
                    label)

    vg.restore()


proc radioButtons(
  id:           ItemId,
  x, y, w, h:   float,
  labels:       seq[string],
  activeButton: Natural,
  tooltips:     seq[string],
  layout:       RadioButtonsLayout = RadioButtonsLayout(kind: rblHoriz),
  drawProc:     Option[RadioButtonsDrawProc] = RadioButtonsDrawProc.none,
  style:        RadioButtonsStyle = DefaultRadioButtonsStyle
): Natural =

  assert activeButton >= 0 and activeButton <= labels.high
  assert tooltips.len == 0 or tooltips.len == labels.len

  alias(ui, g_uiState)

  let numButtons = labels.len

  let x = x + ui.ox
  let y = y + ui.oy

  # Hit testing
  var hotButton = -1

  proc setHot() =
    setHot(id)
    if ui.mbLeftDown and noActiveItem():
      setActive(id)
      ui.radioButtonsActiveItem = hotButton

  let buttonW = w / numButtons.float

  case layout.kind
  of rblHoriz:
    hotButton = min(((ui.mx - x) / buttonW).int, numButtons-1)

    if isHit(x, y, w, h): setHot()

  of rblGridHoriz:
    let
      bbWidth = layout.itemsPerRow * w
      numRows = ceil(numButtons.float / layout.itemsPerRow).Natural
      bbHeight = numRows * h
      row = ((ui.my - y) / h).int
      col = ((ui.mx - x) / w).int
      button = row * layout.itemsPerRow + col

    if row >= 0 and col >= 0 and button < numButtons:
      hotButton = button

    if isHit(x, y, bbWidth, bbHeight) and hotButton > -1: setHot()

  of rblGridVert:
    let
      bbHeight = layout.itemsPerColumn * h
      numCols = ceil(numButtons.float / layout.itemsPerColumn).Natural
      bbWidth = numCols * w
      row = ((ui.my - y) / h).int
      col = ((ui.mx - x) / w).int
      button = col * layout.itemsPerColumn + row

    if row >= 0 and col >= 0 and button < numButtons:
      hotButton = button

    if isHit(x, y, bbWidth, bbHeight) and hotButton > -1: setHot()

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHotAndActive(id) and
     ui.radioButtonsActiveItem == hotButton:
    result = hotButton
  else:
    result = activeButton

  # Draw radio buttons
  proc buttonDrawState(i: Natural): (bool, bool, bool) =
    let drawState = if isHot(id) and noActiveItem(): dsHover
      elif isHotAndActive(id): dsActive
      else: dsNormal

    let hover = drawState == dsHover and hotButton == i
    let active = activeButton == i
    let down = drawState == dsActive and hotButton == i and
                  ui.radioButtonsActiveItem == i

    result = (hover, active, down)

  addDrawLayer(ui.currentLayer, vg):
    var x = x
    var y = y
    let drawProc = if drawProc.isSome: drawProc.get
                   else: DefaultRadioButtonDrawProc

    case layout.kind
    of rblHoriz:
      for i, label in labels:
        let
          (hover, active, down) = buttonDrawState(i)
          first = i == 0
          last = i == labels.len-1
          w = round(x + buttonW) - round(x)

        drawProc(vg, i, label, hover, active, down, first, last,
                 round(x), y, w, h, style)
        x += buttonW

    of rblGridHoriz:
      let startX = x
      var itemsInRow = 0
      for i, label in labels:
        let (hover, active, down) = buttonDrawState(i)
        drawProc(vg, i, label, hover, active, down, first=false, last=false,
                 x, y, w, h, style)

        inc(itemsInRow)
        if itemsInRow == layout.itemsPerRow:
          y += h
          x = startX
          itemsInRow = 0
        else:
          x += w

    of rblGridVert:
      let startY = y
      var itemsInColumn = 0
      for i, label in labels:
        let (hover, active, down) = buttonDrawState(i)
        drawProc(vg, i, label, hover, active, down, first=false, last=false,
                 x, y, w, h, style)

        inc(itemsInColumn)
        if itemsInColumn == layout.itemsPerColumn:
          x += w
          y = startY
          itemsInColumn = 0
        else:
          y += h

  if isHot(id):
    let tt = if hotButton <= tooltips.high: tooltips[hotButton] else: ""
    handleTooltip(id, tt)


template radioButtons*(
  x, y, w, h:   float,
  labels:       seq[string],
  activeButton: Natural,
  tooltips:     seq[string] = @[],
  layout:       RadioButtonsLayout = RadioButtonsLayout(kind: rblHoriz),
  drawProc:     Option[RadioButtonsDrawProc] = RadioButtonsDrawProc.none,
  style:        RadioButtonsStyle = DefaultRadioButtonsStyle
): Natural =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  radioButtons(id, x, y, w, h, labels, activeButton, tooltips,
               layout, drawProc, style)

# }}}
# {{{ Dropdown

type DropdownStyle* = ref object
  buttonCornerRadius*:        float
  buttonStrokeWidth*:         float
  buttonStrokeColor*:         Color
  buttonStrokeColorHover*:    Color
  buttonStrokeColorDown*:     Color
  buttonStrokeColorActive*:   Color
  buttonStrokeColorDisabled*: Color
  buttonFillColor*:           Color
  buttonFillColorHover*:      Color
  buttonFillColorDown*:       Color
  buttonFillColorActive*:     Color
  buttonFillColorDisabled*:   Color
  labelPadHoriz*:             float
  labelFontSize*:             float
  labelFontFace*:             string
  labelAlign*:                HorizontalAlign
  labelColor*:                Color
  labelColorHover*:           Color
  labelColorDown*:            Color
  labelColorActive*:          Color
  labelColorDisabled*:        Color
  itemListAlign*:             HorizontalAlign
  itemListPadHoriz*:          float
  itemListPadVert*:           float
  itemListCornerRadius*:      float
  itemListStrokeWidth*:       float
  itemListStrokeColor*:       Color
  itemListFillColor*:         Color
  itemFontSize*:              float
  itemFontFace*:              string
  itemAlign*:                 HorizontalAlign
  itemColor*:                 Color
  itemColorHover*:            Color
  itemBackgroundColorHover*:  Color

var DefaultDropdownStyle = DropdownStyle(
  buttonCornerRadius        : 5,
  buttonStrokeWidth         : 0,
  buttonStrokeColor         : black(),
  buttonStrokeColorHover    : black(),
  buttonStrokeColorDown     : black(),
  buttonStrokeColorActive   : black(),
  buttonStrokeColorDisabled : black(),
  buttonFillColor           : GRAY_MID,
  buttonFillColorHover      : GRAY_HI,
  buttonFillColorDown       : GRAY_MID,
  buttonFillColorActive     : GRAY_MID,
  buttonFillColorDisabled   : GRAY_LO,
  labelPadHoriz             : 8,
  labelFontSize             : 14.0,
  labelFontFace             : "sans-bold",
  labelAlign                : haLeft,
  labelColor                : GRAY_LO,
  labelColorHover           : GRAY_LO,
  labelColorDown            : GRAY_LO,
  labelColorActive          : GRAY_LO,
  labelColorDisabled        : GRAY_MID,
  itemListAlign             : haCenter,
  itemListPadHoriz          : 7,
  itemListPadVert           : 7,
  itemListCornerRadius      : 5,
  itemListStrokeWidth       : 0,
  itemListStrokeColor       : black(),
  itemListFillColor         : GRAY_LO,
  itemFontSize              : 14.0,
  itemFontFace              : "sans-bold",
  itemAlign                 : haLeft,
  itemColor                 : GRAY_HI,
  itemColorHover            : GRAY_LO,
  itemBackgroundColorHover  : HILITE
)


proc getDefaultDropdownStyle*(): DropdownStyle =
  DefaultDropdownStyle.deepCopy

proc setDefaultDropdownStyle*(style: DropdownStyle) =
  DefaultDropdownStyle = style.deepCopy


proc dropdown(id:           ItemId,
              x, y, w, h:   float,
              items:        seq[string],
              selectedItem: Natural,
              tooltip:      string,
              disabled:     bool,
              style:        DropdownStyle): Natural =

  assert items.len > 0
  assert selectedItem <= items.high

  alias(ui, g_uiState)
  alias(ds, ui.dropdownState)
  alias(s, style)

  let x = x + ui.ox
  let y = y + ui.oy

  var
    itemListX, itemListY, itemListW, itemListH: float
    hoverItem = -1

  let
    numItems = items.len
    itemHeight = h  # TODO just temporarily

  result = selectedItem

  proc closeDropdown() =
    ds.state = dsClosed
    ds.activeItem = 0
    ui.focusCaptured = false
    setFramesLeft()
    clearCharBuf()
    clearEventBuf()

  if ds.state == dsClosed:
    if isHit(x, y, w, h):
      setHot(id)
      if not disabled and ui.mbLeftDown and noActiveItem():
        setActive(id)
        ds.state = dsOpenLMBPressed
        ds.activeItem = id
        ui.focusCaptured = true

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if ds.activeItem == id and ds.state >= dsOpenLMBPressed:

    # Calculate the position of the box around the dropdown items
    var maxItemWidth = 0.0

    g_nvgContext.setFont(s.itemFontSize)

    for i in items:
      let tw = g_nvgContext.textWidth(i)
      maxItemWidth = max(tw, maxItemWidth)

    itemListW = max(maxItemWidth + s.itemListPadHoriz*2, w)
    itemListH = float(items.len) * itemHeight + s.itemListPadVert*2

    itemListX = case s.itemListAlign
    of haLeft:   x
    of haRight:  x + w - itemListW
    of haCenter: x + (w - itemListW)*0.5

    const WindowEdgePad = 5

    if itemListX < WindowEdgePad:
      itemListX = WindowEdgePad

    elif itemListX + itemListW > ui.winWidth - WindowEdgePad:
      itemListX = ui.winWidth - itemListW - WindowEdgePad

    itemListY = if y + h + itemListH < ui.winHeight: y + h
                else: y - itemListH

    let (itemListX, itemListY, itemListW, itemListH) = snapToGrid(
      itemListX, itemListY, itemListW, itemListH, s.itemListStrokeWidth
    )

    # Hit testing
    let
      insideButton = mouseInside(x, y, w, h)
      insideBox = mouseInside(itemListX, itemListY, itemListW, itemListH)

    if insideButton or insideBox:
      setHot(id)
      setActive(id)
    else:
      closeDropdown()

    if insideBox:
      hoverItem = min(
        ((ui.my - itemListY - s.itemListPadVert) / itemHeight).int,
        numItems-1
      )

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

  # Dropdown button
  addDrawLayer(ui.currentLayer, vg):
    let sw = s.buttonStrokeWidth
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let drawState =
      if disabled: dsDisabled
      elif isHot(id) and noActiveItem(): dsHover
      elif isHotAndActive(id): dsActive
      else: dsNormal

    let (fillColor, strokeColor, textColor) = case drawState
      of dsNormal:
        (s.buttonFillColor, s.buttonStrokeColor, s.labelColor)
      of dsHover:
        (s.buttonFillColorHover, s.buttonStrokeColorHover, s.labelColorHover)
      of dsActive:
        (s.buttonFillColorActive, s.buttonStrokeColorActive, s.labelColorActive)
      of dsDisabled:
        (s.buttonFillColorDisabled, s.buttonStrokeColorDisabled,
         s.labelColorDisabled)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.buttonCornerRadius)
    vg.fill()
    vg.stroke()

    let itemText = items[selectedItem]

    vg.drawLabel(x, y, w, h, s.labelPadHoriz, itemText, textColor,
                 s.labelFontSize, s.labelFontFace, s.labelAlign)

  # Dropdown items
  addDrawLayer(ui.currentLayer + 1, vg):
    if isActive(id) and ds.state >= dsOpenLMBPressed:
      # Draw item list box
      vg.fillColor(s.itemListFillColor)
      vg.strokeColor(s.itemListStrokeColor)
      vg.strokeWidth(s.itemListStrokeWidth)

      vg.beginPath()
      vg.roundedRect(itemListX, itemListY, itemListW, itemListH,
                     s.itemListCornerRadius)
      vg.fill()
      vg.stroke()

      # Draw items
      var
        ix = itemListX + s.itemListPadHoriz
        iy = itemListY + s.itemListPadVert

      for i, item in items.pairs:
        var textColor = s.itemColor
        if i == hoverItem:
          vg.beginPath()
          vg.rect(itemListX, iy, itemListW, h)
          vg.fillColor(s.itemBackgroundColorHover)
          vg.fill()
          textColor = s.itemColorHover

        vg.drawLabel(ix, iy, itemListW, h, 0, item, textColor,
                     s.itemFontSize, s.itemFontFace, s.itemAlign)

        iy += itemHeight

  if isHot(id):
    handleTooltip(id, tooltip)


template dropdown*(
  x, y, w, h:   float,
  items:        seq[string],
  selectedItem: Natural,
  tooltip:      string = "",
  disabled:     bool = false,
  style:        DropdownStyle = DefaultDropdownStyle
): Natural =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  dropdown(id, x, y, w, h, items, selectedItem, tooltip, disabled, style)

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
        if shiftDown():
          disableCursor()
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
      if shiftDown():
        disableCursor()
        sb.state = sbsDragHidden
      else:
        let dx = ui.mx - ui.x0

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        ui.x0 = clamp(ui.mx, thumbMinX, thumbMaxX + thumbW)

      setFramesLeft()

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if shiftDown():
        let d = if altDown(): ScrollBarUltraFineDragDivisor
                else:         ScrollBarFineDragDivisor
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
      setFramesLeft()

    of sbsTrackClickDelay:
      if getTime() - ui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat
      setFramesLeft()

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
      setFramesLeft()

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
        if sb.state < sbsTrackClickFirst: HILITE
        else: GRAY_LO
      else:   GRAY_LO

    vg.beginPath()
    vg.roundedRect(newThumbX, y + ThumbPad, thumbW, thumbH, 5)
    vg.fillColor(thumbColor)
    vg.fill()

    vg.setFont(14.0)
    vg.fillColor(white())
    let valueString = fmt"{newValue:.3f}"
    let tw = vg.textWidth(valueString)
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

  let i = instantiationInfo(fullPaths=true)
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
        if shiftDown():
          disableCursor()
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
      if shiftDown():
        disableCursor()
        sb.state = sbsDragHidden
      else:
        let dy = ui.my - ui.y0

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        ui.y0 = clamp(ui.my, thumbMinY, thumbMaxY + thumbH)

      setFramesLeft()

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if shiftDown():
        let d = if altDown(): ScrollBarUltraFineDragDivisor
                else:         ScrollBarFineDragDivisor
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
      setFramesLeft()

    of sbsTrackClickDelay:
      if getTime() - ui.t0 > ScrollBarTrackClickRepeatDelay:
        sb.state = sbsTrackClickRepeat
      setFramesLeft()

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
      setFramesLeft()

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
        if sb.state < sbsTrackClickFirst: HILITE
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

  let i = instantiationInfo(fullPaths=true)
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

    else:
      sb.state = sbsDefault

# }}}
# }}}

# {{{ Text functions

type TextEditResult = object
  text:      string
  cursorPos: Natural
  selection: TextSelection

const NoSelection =TextSelection(startPos: -1, endPos: 0)


proc hasSelection(sel: TextSelection): bool =
  sel.startPos > -1 and sel.startPos != sel.endPos

proc normaliseSelection(sel: TextSelection): TextSelection =
  if (sel.startPos < sel.endPos):
    TextSelection(
      startPos: sel.startPos,
      endPos:   sel.endPos.int
    )
  else:
    TextSelection(
      startPos: sel.endPos.int,
      endPos:   sel.startPos
    )

proc updateSelection(sel: TextSelection,
                     cursorPos, newCursorPos: Natural): TextSelection =
  var sel = sel
  if sel.startPos == -1:
    sel.startPos = cursorPos
    sel.endPos   = cursorPos
  sel.endPos = newCursorPos
  result = sel

proc isAlphanumeric(r: Rune): bool =
  if r.isAlpha: return true
  let s = $r
  if s[0] == '_' or s[0].isDigit: return true

proc findNextWordEnd(text: string, cursorPos: Natural): Natural =
  var p = cursorPos
  while p < text.runeLen and     text.runeAtPos(p).isAlphanumeric: inc(p)
  while p < text.runeLen and not text.runeAtPos(p).isAlphanumeric: inc(p)
  result = p

proc findPrevWordStart(text: string, cursorPos: Natural): Natural =
  var p = cursorPos
  while p > 0 and not text.runeAtPos(p-1).isAlphanumeric: dec(p)
  while p > 0 and     text.runeAtPos(p-1).isAlphanumeric: dec(p)
  result = p

proc drawCursor(vg: NVGContext, x, y1, y2: float, color: Color, width: float) =
  vg.beginPath()
  vg.strokeColor(color)
  vg.strokeWidth(width)
  vg.moveTo(x+0.5, y1)
  vg.lineTo(x+0.5, y2)
  vg.stroke()

# {{{ insertString()
proc insertString(
  text: string, cursorPos: Natural, selection: TextSelection, toInsert: string
): TextEditResult =

  if toInsert.len > 0:
    if hasSelection(selection):
      let ns = normaliseSelection(selection)
      result.text = text.runeSubStr(0, ns.startPos) & toInsert &
                    text.runeSubStr(ns.endPos)
      result.cursorPos = ns.startPos + toInsert.runeLen()

    else:
      result.text = text

      let insertPos = cursorPos
      if insertPos == text.runeLen():
        result.text.add(toInsert)
      else:
        result.text.insert(toInsert, text.runeOffset(insertPos))
      result.cursorPos = cursorPos + toInsert.runeLen()

    result.selection = NoSelection

# }}}
# {{{ deleteSelection()
proc deleteSelection(text: string, selection: TextSelection,
                     cursorPos: Natural): TextEditResult =
  let ns = normaliseSelection(selection)
  result.text = text.runeSubStr(0, ns.startPos) & text.runeSubStr(ns.endPos)
  result.cursorPos = ns.startPos
  result.selection = NoSelection

# }}}
# {{{ handleCommonTextEditingShortcuts()
proc handleCommonTextEditingShortcuts(
  sc: KeyShortcut, text: string, cursorPos: Natural, selection: TextSelection
): Option[TextEditResult] =

  alias(shortcuts, g_textFieldEditShortcuts)

  var eventHandled = true

  var res: TextEditResult
  res.text = text
  res.cursorPos = cursorPos
  res.selection = selection

  # Cursor movement

  if sc in shortcuts[tesCursorOneCharLeft]:
    if hasSelection(selection):
      res.cursorPos = normaliseSelection(selection).startPos
      res.selection = NoSelection
    else:
      res.cursorPos = max(cursorPos - 1, 0)

  elif sc in shortcuts[tesCursorOneCharRight]:
    if hasSelection(selection):
      res.cursorPos = normaliseSelection(selection).endPos
      res.selection = NoSelection
    else:
      res.cursorPos = min(cursorPos + 1, text.runeLen)

  elif sc in shortcuts[tesCursorToPreviousWord]:
    res.cursorPos = findPrevWordStart(text, cursorPos)
    res.selection = NoSelection

  elif sc in shortcuts[tesCursorToNextWord]:
    res.cursorPos = findNextWordEnd(text, cursorPos)
    res.selection = NoSelection

  elif sc in shortcuts[tesCursorToDocumentStart]:
    res.cursorPos = 0
    res.selection = NoSelection

  elif sc in shortcuts[tesCursorToDocumentEnd]:
    res.cursorPos = text.runeLen
    res.selection = NoSelection

  # Selection

  elif sc in shortcuts[tesSelectionAll]:
    res.selection.startPos = 0
    res.selection.endPos = text.runeLen
    res.cursorPos = text.runeLen

  elif sc in shortcuts[tesSelectionOneCharLeft]:
    let newCursorPos = max(cursorPos - 1, 0)
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  elif sc in shortcuts[tesSelectionOneCharRight]:
    let newCursorPos = min(cursorPos+1, text.runeLen)
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  elif sc in shortcuts[tesSelectionToPreviousWord]:
    let newCursorPos = findPrevWordStart(text, cursorPos)
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  elif sc in shortcuts[tesSelectionToNextWord]:
    let newCursorPos = findNextWordEnd(text, cursorPos)
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  elif sc in shortcuts[tesSelectionToDocumentStart]:
    let newCursorPos = 0
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  elif sc in shortcuts[tesSelectionToDocumentEnd]:
    let newCursorPos = text.runeLen
    res.selection = updateSelection(selection, cursorPos, newCursorPos)
    res.cursorPos = newCursorPos

  # Delete

  elif sc in shortcuts[tesDeleteOneCharLeft]:
    if hasSelection(selection):
      res = deleteSelection(text, selection, cursorPos)
    elif cursorPos > 0:
      res.text = text.runeSubStr(0, cursorPos-1) &
                 text.runeSubStr(cursorPos)
      res.cursorPos = cursorPos-1
      res.selection = NoSelection

  elif sc in shortcuts[tesDeleteOneCharRight]:
    if hasSelection(selection):
      res = deleteSelection(text, selection, cursorPos)
    elif text.len > 0:
      res.text = text.runeSubStr(0, cursorPos) &
                 text.runeSubStr(cursorPos+1)

  elif sc in shortcuts[tesDeleteWordToRight]:
    if hasSelection(selection):
      res = deleteSelection(text, selection, cursorPos)
    else:
      let p = findNextWordEnd(text, cursorPos)
      res.text = text.runeSubStr(0, cursorPos) & text.runeSubStr(p)

  elif sc in shortcuts[tesDeleteWordToLeft]:
    if hasSelection(selection):
      res = deleteSelection(text, selection, cursorPos)
    else:
      let p = findPrevWordStart(text, cursorPos)
      res.text = text.runeSubStr(0, p) & text.runeSubStr(cursorPos)
      res.cursorPos = p

  # Clipboard

  elif sc in shortcuts[tesCutText]:
    if hasSelection(selection):
      let ns = normaliseSelection(selection)
      toClipboard(text.runeSubStr(ns.startPos, ns.endPos - ns.startPos))
      res = deleteSelection(text, selection, cursorPos)

  elif sc in shortcuts[tesCopyText]:
    if hasSelection(selection):
      let ns = normaliseSelection(selection)
      toClipboard(text.runeSubStr(ns.startPos, ns.endPos - ns.startPos))

  elif sc in shortcuts[tesPasteText]:
    let toInsert = fromClipboard()
    res = insertString(text, cursorPos, selection, toInsert)

  else:
    eventHandled = false

  result = if eventHandled: res.some else: TextEditResult.none

# }}}
# {{{ breakLines*()
type
  TextRow* = object
    startPos*: Natural
    startBytePos*: Natural

    endPos*: Natural
    endBytePos*: Natural

    nextRowPos*: int
    nextRowBytePos*: int

    width*: float
    # TODO
#    minX*:  cfloat
#    maxX*:  cfloat


const BreakingRunes = @[
  # Breaking spaces
  "\u0020", # space
  "\u2000", # en quad
  "\u2001", # em quad
  "\u2002", # en space
  "\u2003", # em space
  "\u2004", # three-per-em space
  "\u2005", # four-per-em space
  "\u2006", # six-per-em space
  "\u2008", # punctuation space
  "\u2009", # thin space
  "\u200a", # hair space
  "\u205f", # medium mathematical space
  "\u3000", # ideographic space

  # Breaking hyphens
  "\u002d", # hyphen-minus
  "\u00ad", # soft hyphen (shy)
  "\u2010", # hyphen
  "\u2012", # figure dash
  "\u2013", # en dash
  "\u007c", # vertical line
].mapIt(it.runeAt(0))


# TODO support for start & end pos
proc textBreakLines*(text: string, maxWidth: float,
                     maxRows: int = -1): seq[TextRow] =
  var glyphs: array[1024, GlyphPosition]
  result = newSeq[TextRow]()

  let textLen = text.runeLen

  proc fillGlyphsBuffer(textPos, textBytePos: Natural) =
    glyphs[0] = glyphs[^2]
    glyphs[1] = glyphs[^1]
    # TODO using maxX as the next start pos might not be entirely accurate
    # we should use the x pos of the next glyph
    discard g_nvgContext.textGlyphPositions(glyphs[1].maxX, 0, text,
                                            startPos = textBytePos,
                                            toOpenArray(glyphs, 2, glyphs.high))
  const
    NewLine = "\n".runeAt(0)

  var
    prevRune: Rune

    textPos = 0       # current rune position
    textBytePos = 0   # byte offset of the current rune
    prevTextPos = 0
    prevTextBytePos = 0

    # glyphPos is ahead by 1 rune, so glyphs[glyphPos].x will give us the end
    # of the current rune
    glyphPos = 3

    rowStartPos, rowStartBytePos: Natural
    rowStartX = glyphs[0].x

    lastBreakPos = -1
    lastBreakBytePos = -1
    lastBreakPosStartX: float
    lastBreakPosPrev, lastBreakBytePosPrev: Natural


  fillGlyphsBuffer(textPos, textBytePos)

  for rune in text.runes:
    if glyphPos >= glyphs.len:
      fillGlyphsBuffer(textPos, textBytePos)
      glyphPos = 2


    if rune == NewLine and prevRune != NewLine:
      discard

    else:
      if prevRune == NewLine:
        # we're at the rune after the endline
        let newLineEndX           = glyphs[glyphPos-1].x
        let runeBeforeNewLineEndX = glyphs[glyphPos-2].x
        let newLinePos = textPos - 1

        let row = TextRow(
          startPos:       rowStartPos,
          startBytePos:   rowStartBytePos,
          endPos:         prevTextPos,
          endBytePos:     prevTextBytePos,
          nextRowPos:     textPos,
          nextRowBytePos: textBytePos,
          width:          runeBeforeNewLineEndX - rowStartX
        )
        result.add(row)

        rowStartPos = row.nextRowPos
        rowStartBytePos = row.nextRowBytePos
        rowStartX = newLineEndX
        lastBreakPos = -1
        lastBreakBytePos = -1

      else: # not a new line

        # are we at the start of a new word?
        if prevRune in BreakingRunes and rune notin BreakingRunes:
          lastBreakPos = textPos
          lastBreakBytePos = textBytePos

          lastBreakPosPrev = prevTextPos
          lastBreakBytePosPrev = prevTextBytePos

          let prevRuneEndX = glyphs[glyphPos-1].x
          lastBreakPosStartX = prevRuneEndX

        let currRuneEndX = glyphs[glyphPos].x

        if currRuneEndX - rowStartX > maxWidth:
          # break line at the last found break position
          if lastBreakPos > 0:
            let row = TextRow(
              startPos:       rowStartPos,
              startBytePos:   rowStartBytePos,
              endPos:         lastBreakPosPrev,
              endBytePos:     lastBreakBytePosPrev,
              nextRowPos:     lastBreakPos,
              nextRowBytePos: lastBreakBytePos,
              width:          lastBreakPosStartX - rowStartX
            )
            result.add(row)

            rowStartPos = row.nextRowPos
            rowStartBytePos = row.nextRowBytePos
            rowStartX = lastBreakPosStartX
            lastBreakPos = -1
            lastBreakBytePos = -1

          # no break position has been found (the line is basically a single
          # long word)
          else:
            let prevRuneEndX = glyphs[glyphPos-1].x
            let row = TextRow(
              startPos:       rowStartPos,
              startBytePos:   rowStartBytePos,
              endPos:         prevTextPos,
              endBytePos:     prevTextBytePos,
              nextRowPos:     textPos,
              nextRowBytePos: textBytePos,
              width:          prevRuneEndX - rowStartX
            )
            result.add(row)

            rowStartPos = row.nextRowPos
            rowStartBytePos = row.nextRowBytePos
            rowStartX = prevRuneEndX
            lastBreakPos = -1
            lastBreakBytePos = -1

    # flush last row if we're processing the last rune
    if textPos == textLen-1:
      if rune == NewLine:
        let runeBeforeNewLineEndX = glyphs[glyphPos-1].x
        result.add(TextRow(
          startPos:       rowStartPos,
          startBytePos:   rowStartBytePos,
          endPos:         textPos,
          endBytePos:     textBytePos,
          nextRowPos:     -1,
          nextRowBytePos: -1,
          width:          runeBeforeNewLineEndX - rowStartX
        ))
      else:
        let currRuneEndX = glyphs[glyphPos].x
        result.add(TextRow(
          startPos:       rowStartPos,
          startBytePos:   rowStartBytePos,
          endPos:         textPos,
          endBytePos:     textBytePos,
          nextRowPos:     -1,
          nextRowBytePos: -1,
          width:          currRuneEndX - rowStartX
        ))

    prevRune = rune
    prevTextPos = textPos
    prevTextBytePos = textBytePos

    inc(textPos)
    inc(textBytePos, rune.size)
    inc(glyphPos)

# }}}
# }}}
# {{{ TextField

type TextFieldStyle* = ref object
  bgCornerRadius*:      float
  bgStrokeWidth*:       float
  bgStrokeColor*:       Color
  bgStrokeColorHover*:  Color
  bgStrokeColorActive*: Color
  bgFillColor*:         Color
  bgFillColorHover*:    Color
  bgFillColorActive*:   Color
  textPadHoriz*:        float
  textPadVert*:         float
  textFontSize*:        float
  textFontFace*:        string
  textColor*:           Color
  textColorHover*:      Color
  textColorActive*:     Color
  cursorWidth*:         float
  cursorColor*:         Color
  selectionColor*:      Color

var DefaultTextFieldStyle = TextFieldStyle(
  bgCornerRadius      : 5,
  bgStrokeWidth       : 0,
  bgStrokeColor       : black(),
  bgStrokeColorHover  : black(),
  bgStrokeColorActive : black(),
  bgFillColor         : GRAY_MID,
  bgFillColorHover    : GRAY_HI,
  bgFillColorActive   : GRAY_LO,
  textPadHoriz        : 8.0,
  textPadVert         : 2.0,
  textFontSize        : 14.0,
  textFontFace        : "sans",
  textColor           : GRAY_LO,
  textColorHover      : GRAY_LO,
  textColorActive     : GRAY_HI,
  cursorColor         : HILITE,
  cursorWidth         : 1.0,
  selectionColor      : rgb(0.5, 0.15, 0.15)
)

proc getDefaultTextFieldStyle*(): TextFieldStyle =
  DefaultTextFieldStyle.deepCopy

proc setDefaultTextFieldStyle*(style: TextFieldStyle) =
  DefaultTextFieldStyle = style.deepCopy


proc textFieldEnterEditMode(id: ItemId, text: string, startX: float) =
  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)

  setActive(id)
  clearCharBuf()
  clearEventBuf()

  tf.state = tfsEdit
  tf.activeItem = id
  tf.cursorPos = text.runeLen
  tf.displayStartPos = 0
  tf.displayStartX = startX
  tf.originalText = text
  tf.selection.startPos = 0
  tf.selection.endPos = tf.cursorPos

  ui.focusCaptured = true


type
  TextFieldConstraintKind* = enum
    tckString, tckInteger

  TextFieldConstraint* = object
    case kind*: TextFieldConstraintKind
    of tckString:
      minLen*: Natural
      maxLen*: int

    of tckInteger:
      min*, max*: int


proc textField(
  id:         ItemId,
  x, y, w, h: float,
  text:       string,
  tooltip:    string = "",
  activate:   bool = false,
  drawWidget: bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
): string =

  const MaxTextLen = 5000

  assert text.runeLen <= MaxTextLen

  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)
  alias(s, style)

  let
    x = x + ui.ox
    y = y + ui.oy

  # The text is displayed within this rectangle (used for drawing later)
  let
    textBoxX = x + s.textPadHoriz
    textBoxW = w - s.textPadhOriz*2
    textBoxY = y
    textBoxH = h

  var
    text = text
    glyphs: array[MaxTextLen, GlyphPosition]

  var tabActivate = false

  if tf.state == tfsDefault:
    if tf.activateNext and tf.lastActiveItem == tf.prevItem and
       id != tf.prevItem:  # exit editing textfield if there's just one
      tf.activateNext = false
      tabActivate = true

    elif tf.activatePrev and id == tf.itemToActivate and
         id != tf.prevItem:  # exit editing textfield if there's just one
      tf.activatePrev = false
      tabActivate = true

    # Hit testing
    if isHit(x, y, w, h) or activate or tabActivate:
      setHot(id)
      if (ui.mbLeftDown and noActiveItem()) or activate or tabActivate:
        textFieldEnterEditMode(id, text, textBoxX)
        tf.state = tfsEditLMBPressed


  proc calcGlyphPos() =
    g_nvgContext.setFont(s.textFontSize)
    discard g_nvgContext.textGlyphPositions(0, 0, text, glyphs)


  proc exitEditMode() =
    clearEventBuf()
    clearCharBuf()

    tf.state = tfsDefault
    tf.activeItem = 0
    tf.cursorPos = 0
    tf.selection = NoSelection
    tf.displayStartPos = 0
    tf.displayStartX = textBoxX
    tf.originalText = ""
    tf.lastActiveItem = id

    ui.focusCaptured = false
    setCursorShape(csArrow)


  proc enforceConstraint(text, originalText: string): string =
    var text = unicode.strip(text)
    result = text
    if constraint.isSome:
      alias(c, constraint.get)

      case c.kind
      of tckString:
        if text.len < c.minLen:
          result = originalText

        if c.maxLen > -1 and text.len > c.maxLen:
          result = text[0..<c.maxLen]

      of tckInteger:
        try:
          let i = parseInt(text)
          if   i < c.min: result = $c.min
          elif i > c.max: result = $c.max
          else:           result = $i
        except ValueError:
          result = originalText


  proc getCursorPosAtXPos(x: float): Natural =
    for p in tf.displayStartPos..max(text.runeLen-1, 0):
      let midX = glyphs[p].minX + (glyphs[p].maxX - glyphs[p].minX) / 2
      if x < tf.displayStartX + midX - glyphs[tf.displayStartPos].x:
        return p

    result = text.runeLen


  proc getCursorXPos(): float =
    if tf.cursorPos == 0: textBoxX

    elif tf.cursorPos == text.runeLen:
      tf.displayStartX + glyphs[tf.cursorPos-1].maxX -
                         glyphs[tf.displayStartPos].x

    elif tf.cursorPos > 0:
      tf.displayStartX + glyphs[tf.cursorPos].x -
                         glyphs[tf.displayStartPos].x
    else: textBoxX


  const ScrollRightOffset = 10

  # We 'fall through' to the edit state to avoid a 1-frame delay when going
  # into edit mode
  if tf.activeItem == id and tf.state >= tfsEditLMBPressed:
    calcGlyphPos()  # required for the mouse interactions

    setHot(id)
    setActive(id)
    setCursorShape(csIBeam)

    if tf.state == tfsEditLMBPressed:
      if not ui.mbLeftDown:
        tf.state = tfsEdit

    elif tf.state == tfsDragStart:
      let cursorX = getCursorXPos()
      if ui.mbLeftDown:
        if (ui.mx < textBoxX and cursorX < textBoxX + 10) or
           (ui.mx > textBoxX + textBoxW - ScrollRightOffset and
            cursorX > textBoxX + textBoxW - ScrollRightOffset - 10):
          ui.t0 = getTime()
          tf.state = tfsDragDelay
        else:
          let mouseCursorPos = getCursorPosAtXPos(ui.mx)
          tf.selection = updateSelection(tf.selection, tf.cursorPos,
                                         newCursorPos = mouseCursorPos)
          tf.cursorPos = mouseCursorPos
      else:
        tf.state = tfsEdit

    elif tf.state == tfsDragDelay:
      if ui.mbLeftDown:
        var dx = ui.mx - textBoxX
        if dx > 0:
          dx = (textBoxX + textBoxW - ScrollRightOffset) - ui.mx

        if dx < 0:
          if getTime() - ui.t0 > TextFieldScrollDelay / (-dx/10):
            tf.state = tfsDragScroll
        else:
          tf.state = tfsDragStart
        setFramesLeft()
      else:
        tf.state = tfsEdit

    elif tf.state == tfsDragScroll:
      if ui.mbLeftDown:
        let newCursorPos = if ui.mx < textBoxX:
          max(tf.cursorPos - 1, 0)
        elif ui.mx > textBoxX + textBoxW - ScrollRightOffset:
          min(tf.cursorPos + 1, text.runeLen)
        else:
          tf.cursorPos

        tf.selection = updateSelection(tf.selection, tf.cursorPos,
                                       newCursorPos)
        tf.cursorPos = newCursorPos
        ui.t0 = getTime()
        tf.state = tfsDragDelay
        setFramesLeft()
      else:
        tf.state = tfsEdit

    # This state is needed to prevent going into drag-select mode after
    # selecting a word by double-clicking
    elif tf.state == tfsDoubleClicked:
      if not ui.mbLeftDown:
        tf.state = tfsEdit

    else:
      if ui.mbLeftDown:
        if mouseInside(x, y, w, h):
          tf.selection = NoSelection
          tf.cursorPos = getCursorPosAtXPos(ui.mx)

          if isDoubleClick():
            tf.selection.startPos = findPrevWordStart(text, tf.cursorPos)
            tf.selection.endPos = findNextWordEnd(text, tf.cursorPos)
            tf.cursorPos = tf.selection.endPos
            tf.state = tfsDoubleClicked
          else:
            ui.x0 = ui.mx
            tf.state = tfsDragStart

        # LMB pressed outside the text field exits edit mode
        else:
          text = enforceConstraint(text, tf.originalText)
          exitEditMode()

    # Handle text field shortcuts
    # (If we exited edit mode above key handler, this will result in a noop as
    # exitEditMode() clears the key buffer.)

    # "Fall-through" into edit mode happens here
    if ui.hasEvent and (not ui.eventHandled) and
       ui.currEvent.kind == ekKey and
       ui.currEvent.action in {kaDown, kaRepeat}:

      alias(shortcuts, g_textFieldEditShortcuts)
      let sc = mkKeyShortcut(ui.currEvent.key, ui.currEvent.mods)

      ui.eventHandled = true

      let res = handleCommonTextEditingShortcuts(sc, text,
                                                 tf.cursorPos, tf.selection)
      if res.isSome:
        text = res.get.text
        tf.cursorPos = res.get.cursorPos
        tf.selection = res.get.selection

      else:
        # Cursor movement
        if sc in shortcuts[tesCursorToLineStart]:
          tf.cursorPos = 0
          tf.selection = NoSelection

        elif sc in shortcuts[tesCursorToLineEnd]:
          tf.cursorPos = text.runeLen
          tf.selection = NoSelection

        # Selection
        elif sc in shortcuts[tesSelectionToLineStart]:
          let newCursorPos = 0
          tf.selection = updateSelection(tf.selection, tf.cursorPos,
                                         newCursorPos)
          tf.cursorPos = newCursorPos

        elif sc in shortcuts[tesSelectionToLineEnd]:
          let newCursorPos = text.runeLen
          tf.selection = updateSelection(tf.selection, tf.cursorPos,
                                         newCursorPos)
          tf.cursorPos = newCursorPos

        # Delete
        elif sc in shortcuts[tesDeleteToLineStart] or
             sc in shortcuts[tesDeleteToLineEnd]:

          if hasSelection(tf.selection):
            let res = deleteSelection(text, tf.selection, tf.cursorPos)
            text = res.text
            tf.cursorPos = res.cursorPos
            tf.selection = res.selection
          else:

            if sc in shortcuts[tesDeleteToLineStart]:
              text = text.runeSubStr(tf.cursorPos)
              tf.cursorPos = 0
            else:
              text = text.runeSubStr(0, tf.cursorPos)

        # General
        elif sc in shortcuts[tesPrevTextField]:
          text = enforceConstraint(text, tf.originalText)
          exitEditMode()
          tf.activatePrev = true
          tf.itemToActivate = tf.prevItem
          setFramesLeft()

        elif sc in shortcuts[tesNextTextField]:
          text = enforceConstraint(text, tf.originalText)
          exitEditMode()
          tf.activateNext = true
          setFramesLeft()

        elif sc in shortcuts[tesAccept]:
          text = enforceConstraint(text, tf.originalText)
          exitEditMode()
          # Note we won't process any remaining characters in the buffer
          # because exitEditMode() clears the key buffer.

        elif sc in shortcuts[tesCancel]:
          text = tf.originalText
          exitEditMode()
          # Note we won't process any remaining characters in the buffer
          # because exitEditMode() clears the key buffer.

        else:
          ui.eventHandled = false

    # Splice newly entered characters into the string.
    # (If we exited edit mode in the above key handler, this will result in
    # a noop as exitEditMode() clears the char buffer.)
    if not charBufEmpty():
      var newChars = consumeCharBuf()
      let res = insertString(text, tf.cursorPos, tf.selection, newChars)
      text = res.text
      tf.cursorPos = res.cursorPos
      tf.selection = res.selection

    # Update textfield state vars based on the new text & current cursor
    # position
    let textLen = text.runeLen

    if textLen == 0:
      tf.cursorPos = 0
      tf.selection = NoSelection
      tf.displayStartPos = 0
      tf.displayStartX = textBoxX

    else:
      # Need to recalculate glyph positions as the text might have changed
      calcGlyphPos()

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

  result = text


  # Draw text field
  let editing = tf.activeItem == id

  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif editing: dsActive
    else: dsNormal

  var
    textX = textBoxX
    textY = y + h*TextVertAlignFactor

  let (fillColor, strokeColor) = case drawState
    of dsHover:  (s.bgFillColorHover,  s.bgStrokeColorHover)
    of dsActive: (s.bgFillColorActive, s.bgStrokeColorActive)
    else:        (s.bgFillColor,       s.bgStrokeColor)

  let layer = if editing: TopLayer-3 else: ui.currentLayer

  addDrawLayer(layer, vg):
    vg.save()

    # Draw text field background
    if drawWidget:
      vg.beginPath()
      vg.roundedRect(x, y, w, h, s.bgCornerRadius)
      vg.fillColor(fillColor)
      vg.fill()

    elif editing:
      vg.beginPath()
      vg.rect(
        textBoxX, textBoxY + s.textPadVert,
        textBoxW, textBoxH - s.textPadVert*2
      )
      vg.fillColor(fillColor)
      vg.fill()

    # Make scissor region slightly wider because of the cursor
    # TODO convert constants into style params?
    vg.intersectScissor(textBoxX-3, textBoxY, textBoxW+3, textBoxH)

    # Scroll content into view & draw cursor when editing
    if editing:
      textX = tf.displayStartX

      # Draw selection
      if hasSelection(tf.selection):
        var ns = normaliseSelection(tf.selection)
        ns.endPos = max(ns.endPos-1, 0)

        let
          selStartX = tf.displayStartX + glyphs[ns.startPos].minX -
                                         glyphs[tf.displayStartPos].x

          selEndX = tf.displayStartX + glyphs[ns.endPos].maxX -
                                       glyphs[tf.displayStartPos].x

        vg.beginPath()
        # TODO convert constants into style params?
        vg.rect(selStartX, y+2, selEndX - selStartX, h-4)
        vg.fillColor(s.selectionColor)
        vg.fill()

      # Draw cursor
      let cursorX = getCursorXPos()
      drawCursor(vg, cursorX, y+2, y+h-2, s.cursorColor, s.cursorWidth)

      text = text.runeSubStr(tf.displayStartPos)

    # Draw text
    # TODO text color hover
    let textColor = if editing: s.textColorActive else: s.textColor

    vg.setFont(s.textFontSize)
    vg.fillColor(textColor)
    discard vg.text(textX, textY, text)

    vg.restore()

  if isHot(id):
    handleTooltip(id, tooltip)

  # TODO a bit hacky, why is it needed?
  if activate or tabActivate:
    ui.tooltipState.state = tsOff

  tf.prevItem = id


template rawTextField*(
  x, y, w, h: float,
  text:       string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
): string =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, text, tooltip, activate, drawWidget = false,
            constraint, style)


template textField*(
  x, y, w, h: float,
  text:       string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
): string =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, text, tooltip, activate, drawWidget = true,
            constraint, style)


# }}}
# {{{ TextArea

type TextAreaStyle* = object
  bgCornerRadius*:      float
  bgStrokeWidth*:       float
  bgStrokeColor*:       Color
  bgStrokeColorHover*:  Color
  bgStrokeColorActive*: Color
  bgFillColor*:         Color
  bgFillColorHover*:    Color
  bgFillColorActive*:   Color
  textPadHoriz*:        float
  textPadVert*:         float
  textFontSize*:        float
  textFontFace*:        string
  textLineHeight*:      float
  textColor*:           Color
  textColorHover*:      Color
  textColorActive*:     Color
  cursorWidth*:         float
  cursorColor*:         Color
  selectionColor*:      Color

var DefaultTextAreaStyle = TextAreaStyle(
  bgCornerRadius      : 5,
  bgStrokeWidth       : 0,
  bgStrokeColor       : black(),
  bgStrokeColorHover  : black(),
  bgStrokeColorActive : black(),
  bgFillColor         : GRAY_MID,
  bgFillColorHover    : GRAY_HI,
  bgFillColorActive   : GRAY_LO,
  textPadHoriz        : 8.0,
  textPadVert         : 2.0,
  textFontSize        : 14.0,
  textFontFace        : "sans",
  textLineHeight      : 1.4,
  textColor           : GRAY_LO,
  textColorHover      : GRAY_LO,
  textColorActive     : GRAY_HI,
  cursorColor         : HILITE,
  cursorWidth         : 1.0,
  selectionColor      : rgb(0.5, 0.15, 0.15)
)

proc getDefaultTextAreaStyle*(): TextAreaStyle =
  DefaultTextAreaStyle.deepCopy

proc setDefaultTextAreaStyle*(style: TextAreaStyle) =
  DefaultTextAreaStyle = style.deepCopy


type
  TextAreaConstraint* = object
    minLen*: Natural
    maxLen*: int


proc textArea(
  id:         ItemId,
  x, y, w, h: float,
  text:       string,
  tooltip:    string = "",
  activate:   bool = false,
  drawWidget: bool = false,
  constraint: Option[TextAreaConstraint] = TextAreaConstraint.none,
  style:      TextAreaStyle = DefaultTextAreaStyle
): string =

  alias(ui, g_uiState)
  alias(ta, ui.textAreaState)
  alias(s, style)

  const MaxLineLen = 1000
  assert text.runeLen <= MaxLineLen

  let TextRightPad = s.textFontSize

  let
    x = x + ui.ox
    y = y + ui.oy

  # The text is displayed within this rectangle (used for drawing later)
  let
    textBoxX = x + s.textPadHoriz
    textBoxW = w - s.textPadHoriz*2
    textBoxY = y
    textBoxH = h

  var
    text = text
    glyphs: array[MaxLineLen, GlyphPosition]


  proc enterEditMode(id: ItemId, text: string, startX: float) =
    setActive(id)
    clearCharBuf()
    clearEventBuf()

    ta.state = tasEdit
    ta.activeItem = id
    ta.cursorPos = text.runeLen
    ta.originalText = text
    ta.selection.startPos = 0
    ta.selection.endPos = ta.cursorPos

    ui.focusCaptured = true


  proc exitEditMode() =
    clearEventBuf()
    clearCharBuf()

    ta.state = tasDefault
    ta.activeItem = 0
    ta.cursorPos = 0
    ta.selection = NoSelection
    ta.originalText = ""
    ta.lastActiveItem = id

    ui.focusCaptured = false
    setCursorShape(csArrow)


  var tabActivate = false

  if ta.state == tasDefault:
    if ta.activateNext and ta.lastActiveItem == ta.prevItem and
       id != ta.prevItem:  # exit editing textarea if there's just one
      ta.activateNext = false
      tabActivate = true

    elif ta.activatePrev and id == ta.itemToActivate and
         id != ta.prevItem:  # exit editing textarea if there's just one
      ta.activatePrev = false
      tabActivate = true

    # Hit testing
    if isHit(x, y, w, h) or activate or tabActivate:
      setHot(id)
      if (ui.mbLeftDown and noActiveItem()) or activate or tabActivate:
        enterEditMode(id, text, textBoxX)
        ta.state = tasEditEntered


  proc calcGlypPosForRow(x, y: float, row: TextRow): Natural =
    g_nvgContext.setFont(s.textFontSize)
    return g_nvgContext.textGlyphPositions(x, y, text,
                                           row.startBytePos, row.endBytePos,
                                           glyphs)

  # We 'fall through' to the edit state to avoid a 1-frame delay when going
  # into edit mode
  if ta.activeItem == id and ta.state >= tasEditEntered:
    setHot(id)
    setActive(id)
    setCursorShape(csIBeam)

    if ta.state == tasEditEntered:
      if not ui.mbLeftDown:
        ta.state = tasEdit

    else:
      if ui.mbLeftDown:
        if mouseInside(x, y, w, h):
          discard
        else:
          exitEditMode()

    # Handle text field shortcuts
    # (If we exited edit mode above key handler, this will result in a noop as
    # exitEditMode() clears the key buffer.)

    # "Fall-through" into edit mode happens here
    if ui.hasEvent and (not ui.eventHandled) and
       ui.currEvent.kind == ekKey and
       ui.currEvent.action in {kaDown, kaRepeat}:

      alias(shortcuts, g_textFieldEditShortcuts)
      let sc = mkKeyShortcut(ui.currEvent.key, ui.currEvent.mods)

      ui.eventHandled = true

      # Only use the stored X position for consecutive prev/next line
      # actions
      if not (sc in shortcuts[tesCursorToPreviousLine] or
              sc in shortcuts[tesCursorToNextLine] or
              sc in shortcuts[tesSelectionToPreviousLine] or
              sc in shortcuts[tesSelectionToNextLine]):
        ta.lastCursorXPos = float.none

      let res = handleCommonTextEditingShortcuts(sc, text, ta.cursorPos,
                                                 ta.selection)

      if res.isSome:
        text = res.get.text
        ta.cursorPos = res.get.cursorPos
        ta.selection = res.get.selection

      else:
        # We only need to break the text into rows when handling
        # textarea-specific shortcuts
        g_nvgContext.setFont(s.textFontSize, vertAlign=vaBaseline)
        let rows = textBreakLines(text, textBoxW)

        var currRow: TextRow
        var currRowIdx: Natural

        if ta.cursorPos == text.runeLen:
          currRow = rows[^1]
          currRowIdx = rows.high
        else:
          for i, row in rows.pairs:
            if ta.cursorPos >= row.startPos and
               ta.cursorPos <= row.endPos:
              currRow = row
              currRowIdx = i
              break

        # Cursor movement
        proc findClosestCursorPos(row: TextRow, cx: float): Natural = 
          result = row.endPos
          for pos in 0..(row.endPos - row.startPos):
            if glyphs[pos].x > cx:
              let prevPos = max(pos-1, 0)
              if (glyphs[pos].x - cx) < (cx - glyphs[prevPos].x):
                return row.startPos + pos
              else:
                return row.startPos + prevPos

        proc setLastCursorXPos() =
          if ta.lastCursorXPos.isNone:
            let numGlyphs = calcGlypPosForRow(textBoxX, 0, currRow)
            if ta.cursorPos >= text.runeLen:
              ta.lastCursorXPos = glyphs[numGlyphs-1].maxX.float.some
            else:
              let pos = ta.cursorPos - currRow.startPos
              ta.lastCursorXPos = glyphs[pos].x.float.some

        if sc in shortcuts[tesCursorToPreviousLine]:
          if currRowIdx > 0:
            setLastCursorXPos()
            let prevRow = rows[currRowIdx-1]
            discard calcGlypPosForRow(textBoxX, 0, prevRow)
            ta.cursorPos = findClosestCursorPos(prevRow, ta.lastCursorXPos.get)
            ta.selection = NoSelection

        elif sc in shortcuts[tesCursorToNextLine]:
          if currRowIdx < rows.high:
            setLastCursorXPos()
            let nextRow = rows[currRowIdx+1]
            discard calcGlypPosForRow(textBoxX, 0, nextRow)
            ta.cursorPos = findClosestCursorPos(nextRow, ta.lastCursorXPos.get)
            ta.selection = NoSelection

        elif sc in shortcuts[tesCursorToLineStart]:
          ta.cursorPos = currRow.startPos
          ta.selection = NoSelection

        elif sc in shortcuts[tesCursorToLineEnd]:
          ta.cursorPos = if currRow.nextRowPos > 0: currRow.endPos
                         else: text.runeLen
          ta.selection = NoSelection

        # Selection
        elif sc in shortcuts[tesSelectionToPreviousLine]:
          if currRowIdx > 0:
            setLastCursorXPos()
            let prevRow = rows[currRowIdx-1]
            discard calcGlypPosForRow(textBoxX, 0, prevRow)

            let newCursorPos = findClosestCursorPos(prevRow,
                                                    ta.lastCursorXPos.get)
            ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                           newCursorPos)
            ta.cursorPos = newCursorPos

        elif sc in shortcuts[tesSelectionToNextLine]:
          if currRowIdx < rows.high:
            setLastCursorXPos()
            let nextRow = rows[currRowIdx+1]
            discard calcGlypPosForRow(textBoxX, 0, nextRow)

            let newCursorPos = findClosestCursorPos(nextRow,
                                                    ta.lastCursorXPos.get)
            ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                           newCursorPos)
            ta.cursorPos = newCursorPos

        elif sc in shortcuts[tesSelectionToLineStart]:
          let newCursorPos = currRow.startPos
          ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                         newCursorPos)
          ta.cursorPos = newCursorPos

        elif sc in shortcuts[tesSelectionToLineEnd]:
          let newCursorPos = if currRow.nextRowPos > 0: currRow.endPos
                             else: text.runeLen

          ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                         newCursorPos)
          ta.cursorPos = newCursorPos

        # Delete
        elif sc in shortcuts[tesDeleteToLineStart] or
             sc in shortcuts[tesDeleteToLineEnd]:

          if hasSelection(ta.selection):
            let res = deleteSelection(text, ta.selection, ta.cursorPos)
            text = res.text
            ta.cursorPos = res.cursorPos
            ta.selection = res.selection
          else:
            let beforeCurrRow =
              if currRow.startPos == 0: ""
              else: text.runeSubStr(0, currRow.startPos)

            let afterCurrRow =
              if currRow.nextRowPos < 0: ""
              else: text.runeSubStr(currRow.nextRowPos)

            let newCurrRow =
              if sc in shortcuts[tesDeleteToLineStart]:
                let cursorPos = ta.cursorPos
                ta.cursorPos = currRow.startPos
                text.runeSubStr(cursorPos, currRow.endPos - cursorPos + 1)
              else:
                text.runeSubStr(currRow.startPos,
                                ta.cursorPos - currRow.startPos)

            text = beforeCurrRow & newCurrRow & afterCurrRow

        # General
        elif sc in shortcuts[tesPrevTextField]:
          exitEditMode()
          ta.activatePrev = true
          ta.itemToActivate = ta.prevItem
          setFramesLeft()

        elif sc in shortcuts[tesNextTextField]:
          exitEditMode()
          ta.activateNext = true
          setFramesLeft()

        elif sc in shortcuts[tesAccept]:
          exitEditMode()
          # Note we won't process any remaining characters in the buffer
          # because exitEditMode() clears the key buffer.

        elif sc in shortcuts[tesCancel]:
          text = ta.originalText
          exitEditMode()
          # Note we won't process any remaining characters in the buffer
          # because exitEditMode() clears the key buffer.

        else:
          ui.eventHandled = false

    # Splice newly entered characters into the string.
    # (If we exited edit mode in the above key handler, this will result in
    # a noop as exitEditMode() clears the char buffer.)
    if not charBufEmpty():
      var newChars = consumeCharBuf()
      let res = insertString(text, ta.cursorPos, ta.selection, newChars)
      text = res.text
      ta.cursorPos = res.cursorPos
      ta.selection = res.selection

    # Update textarea field vars after the edits
    let textLen = text.runeLen

    if textLen == 0:
      ta.cursorPos = 0
      ta.selection = NoSelection


  result = text

  # Draw text area
  let editing = ta.activeItem == id

  let drawState = if isHot(id) and noActiveItem(): dsHover
    elif editing: dsActive
    else: dsNormal

  let (fillColor, strokeColor) = case drawState
    of dsHover:  (s.bgFillColorHover,  s.bgStrokeColorHover)
    of dsActive: (s.bgFillColorActive, s.bgStrokeColorActive)
    else:        (s.bgFillColor,       s.bgStrokeColor)

  let layer = if editing: TopLayer-3 else: ui.currentLayer

  addDrawLayer(layer, vg):
    vg.save()

    # Draw text field background
    if drawWidget:
      vg.beginPath()
      vg.roundedRect(x, y, w, h, s.bgCornerRadius)
      vg.fillColor(fillColor)
      vg.fill()

    elif editing:
      vg.beginPath()
      vg.rect(
        textBoxX, textBoxY + s.textPadVert,
        textBoxW, textBoxH - s.textPadVert*2
      )
      vg.fillColor(fillColor)
      vg.fill()

    # Make scissor region slightly wider because of the cursor
    vg.intersectScissor(textBoxX, textBoxY, textBoxW + TextRightPad, textBoxH)

    # Draw text
    # TODO text color hover
    let textColor = if editing: s.textColorActive else: s.textColor

    vg.setFont(s.textFontSize, vertAlign=vaBaseline)

    var (_, _, lineHeight) = vg.textMetrics()
    lineHeight = floor(lineHeight * s.textLineHeight)

    let rows = textBreakLines(text, textBoxW)
    let sel = normaliseSelection(ta.selection)

    var
      textX = textBoxX
      textY = textBoxY + lineHeight
      numGlyphs: Natural


    for rowIdx, row in rows.pairs():

      let cursorYAdjust = floor(lineHeight*0.55)

      # Draw selection
      if editing:
        numGlyphs = calcGlypPosForRow(textX, textY, row)

        if hasSelection(ta.selection):
          let selStartX =
            if sel.startPos < row.startPos:
              textX
            elif sel.startPos >= row.startPos and
                 sel.startPos <= row.endPos:
              glyphs[sel.startPos - row.startPos].minX
            else: -1

          let selEndX =
            if sel.endPos-1 > row.endPos:
              glyphs[numGlyphs-1].maxX
            elif sel.endPos-1 >= row.startPos and
                 sel.endPos-1 <= row.endPos:
              glyphs[sel.endPos-1 - row.startPos].maxX
            else: -1

          if selStartX >= 0 and selEndX >= 0:
            vg.beginPath()
            vg.rect(selStartX, textY - cursorYAdjust, selEndX - selStartX,
                    lineHeight)
            vg.fillColor(s.selectionColor)
            vg.fill()

      # Draw text
      vg.fillColor(textColor)
      discard vg.text(textX, textY, text, row.startBytePos, row.endBytePos)

      # Draw cursor
      if editing:
        var cursorX = float.none
        var drawCursorAtEndOfLine = false

        if ta.cursorPos >= row.startPos and
           ta.cursorPos <= row.endPos:

          let n = ta.cursorPos - row.startPos
          if n < numGlyphs:
            cursorX = (glyphs[n].x.float).some
          else:
            drawCursorAtEndOfLine = true

        elif rowIdx == rows.high and ta.cursorPos == text.runeLen:
          drawCursorAtEndOfLine = true


        if drawCursorAtEndOfLine:
          if numGlyphs > 0:
            cursorX = (glyphs[numGlyphs-1].maxX.float).some
          else:
            cursorX = textX.some

        if cursorX.isSome:
          drawCursor(vg, cursorX.get,
                     textY - cursorYAdjust,
                     textY - cursorYAdjust + lineHeight,
                     s.cursorColor, s.cursorWidth)

      textY += lineHeight

    vg.restore()


  if isHot(id):
    handleTooltip(id, tooltip)

  # TODO a bit hacky, why is it needed?
  if activate or tabActivate:
    ui.tooltipState.state = tsOff

  ta.prevItem = id


template textArea*(
  x, y, w, h: float,
  text:       string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextAreaConstraint] = TextAreaConstraint.none,
  style:      TextAreaStyle = DefaultTextAreaStyle
): string =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textArea(id, x, y, w, h, text, tooltip, activate, drawWidget = true,
           constraint, style)


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
      disableCursor()

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

        let d = if shiftDown():
          if altDown(): SliderUltraFineDragDivisor
          else:         SliderFineDragDivisor
        else: 1

        let dx = (ui.mx - ui.x0) / d

        newPosX = clamp(posX + dx, posMinX, posMaxX)
        let t = invLerp(posMinX, posMaxX, newPosX)
        value = lerp(startVal, endVal, t)
        ui.x0 = ui.mx

    of ssEditValue:
      # The textfield will only work correctly if it thinks it's active
      setActive(ss.textFieldId)

      # TODO couldn't we do activate=true here and simplify the code?
      ss.valueText = koi.textField(ss.textFieldId, x, y, w, h,
                                   ss.valueText, drawWidget = false)

      if ui.textFieldState.state == tfsDefault:
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
        of dsActive: HILITE
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
      let tw = vg.textWidth(valueString)
      discard vg.text(x + w*0.5 - tw*0.5, y + h*TextVertAlignFactor, valueString)

  if isHot(id):
    handleTooltip(id, tooltip)


template horizSlider*(x, y, w, h: float,
                      startVal:   float = 0.0,
                      endVal:     float = 1.0,
                      tooltip:    string = "",
                      value:      float): float =

  let i = instantiationInfo(fullPaths=true)
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
      disableCursor()
      ss.state = ssDragHidden

    of ssDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      let d = if shiftDown():
        if altDown(): SliderUltraFineDragDivisor
        else:         SliderFineDragDivisor
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
      of dsActive: HILITE
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

  let i = instantiationInfo(fullPaths=true)
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

type DialogStyle* = ref object
  cornerRadius*:       float
  backgroundColor*:    Color
  titleBarBgColor*:    Color
  titleBarTextColor*:  Color
  outerBorderColor*:   Color
  innerBorderColor*:   Color
  outerBorderWidth*:   float
  innerBorderWidth*:   float

var DefaultDialogStyle = DialogStyle(
  cornerRadius:       7,
  backgroundColor:    gray(0.2),
  titleBarBgColor:    gray(0.05),
  titleBarTextColor:  gray(0.85),
  outerBorderColor:   black(),
  innerBorderColor:   white(),
  outerBorderWidth:   0,
  innerBorderWidth:   0
)

proc getDefaultDialogStyle*(): DialogStyle =
  DefaultDialogStyle.deepCopy

proc setDefaultDialogStyle*(style: DialogStyle) =
  DefaultDialogStyle = style.deepCopy


proc beginDialog*(w, h: float, title: string,
                  style: DialogStyle = DefaultDialogStyle) =

  alias(ui, g_uiState)
  alias(s, style)

  let
    x = floor((ui.winWidth - w) / 2)
    y = floor((ui.winHeight - h) / 2)

  inc(ui.currentLayer, 2)   # TODO

  addDrawLayer(ui.currentLayer, vg):
    const TitleBarHeight = 30.0

    # Outer border
    if s.outerBorderWidth > 0:
      let bw = s.outerBorderWidth + s.innerBorderWidth
      let cr = if s.cornerRadius > 0: s.cornerRadius+bw else: 0

      vg.beginPath()
      vg.fillColor(s.outerBorderColor)
      vg.roundedRect(x-bw, y-bw, w+bw*2, h+bw*2, cr)
      vg.fill()

    # Inner border
    if s.innerBorderWidth > 0:
      let bw = s.innerBorderWidth
      let cr = if s.cornerRadius > 0: s.cornerRadius+bw else: 0

      vg.beginPath()
      vg.fillColor(s.innerBorderColor)
      vg.roundedRect(x-bw, y-bw, w+bw*2, h+bw*2, cr)
      vg.fill()

    # Dialog background
    vg.beginPath()
    vg.fillColor(s.backgroundColor)
    vg.roundedRect(x, y, w, h, s.cornerRadius)
    vg.fill()

    # Title bar
    vg.beginPath()
    vg.fillColor(s.titleBarBgColor)
    vg.roundedRectVarying(x, y, w, TitleBarHeight,
                          s.cornerRadius, s.cornerRadius, 0, 0)
    vg.fill()

    vg.fontFace("sans-bold")
    vg.fontSize(15.0)
    vg.textAlign(haLeft, vaMiddle)
    vg.fillColor(s.titleBarTextColor)
    discard vg.text(x+10.0, y + TitleBarHeight * TextVertAlignFactor, title)

  ui.ox = x
  ui.oy = y
  ui.insideDialog = true
  ui.isDialogOpen = true


proc endDialog*() =
  alias(ui, g_uiState)
  ui.ox = 0
  ui.oy = 0
  ui.insideDialog = false
  dec(ui.currentLayer, 2 )  # TODO


proc closeDialog*() =
  alias(ui, g_uiState)
  ui.isDialogOpen = false
  setFramesLeft()


# }}}
#[
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
    let tw = g_nvgContext.textWidth(name)
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
    of dsActive: HILITE
    else:        GRAY_MID

  addDrawLayer(ui.currentLayer, vg):
    vg.save()

    # Draw bar
    vg.beginPath()
    vg.rect(x, y, w, h)
    vg.fillColor(fillColor)
    vg.fill()

    vg.intersectScissor(x, y, w, h)

    vg.setFont(14.0)
    vg.fillColor(GRAY_LO)

    for i in 0..names.high:
      discard vg.text(menuPosX[i], y + h*TextVertAlignFactor, names[i])

    vg.restore()


template menuBar*(x, y, w, h: float, names: seq[string]): string =

  let i = instantiationInfo(fullPaths=true)
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
]#

# {{{ init*()

proc init*(nvg: NVGContext) =
  g_nvgContext = nvg

  g_cursorArrow       = wrapper.createStandardCursor(csArrow)
  g_cursorIBeam       = wrapper.createStandardCursor(csIBeam)
  g_cursorCrosshair   = wrapper.createStandardCursor(csCrosshair)
  g_cursorHorizResize = wrapper.createStandardCursor(csHorizResize)
  g_cursorVertResize  = wrapper.createStandardCursor(csVertResize)
  g_cursorHand        = wrapper.createStandardCursor(csHand)

  let win = currentContext()
  win.lockKeyMods = true
  win.keyCb  = keyCb
  win.charCb = charCb
  win.mouseButtonCb = mouseButtonCb

  glfw.swapInterval(1)

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

  ui.hasEvent = false
  ui.eventHandled = false

  if g_eventBuf.canRead():
    ui.currEvent = g_eventBuf.read().get
    ui.hasEvent = true
    let ev = ui.currEvent

    case ev.kind:
    of ekKey: discard

    of ekMouse:
      case ev.button
      of mbLeft:
        ui.mbLeftDown = ev.pressed

        ui.lastMbLeftDownX = ui.mbLeftDownX
        ui.lastMbLeftDownY = ui.mbLeftDownY
        ui.lastMbLeftDownT = ui.mbLeftDownT

        ui.mbLeftDownT = getTime()
        ui.mbLeftDownX = ui.mx
        ui.mbLeftDownY = ui.my

      of mbRight:  ui.mbRightDown  = ev.pressed
      of mbMiddle: ui.mbMiddleDown = ev.pressed
      else: discard

    # Because up to one event is processed per frame, handling keystroke
    # events can become "out of sync" with the char buffer. So we need to keep
    # processing one more frame while there are still events in the buffer to
    # prevent that from happening.
    if g_eventBuf.canRead(): setFramesLeft()

  # Reset hot item
  ui.hotItem = 0

  g_drawLayers.init()

# }}}
# {{{ endFrame*()

proc endFrame*() =
  alias(ui, g_uiState)

  # Post-frame processing
  tooltipPost()

  setCursorMode(ui.cursorShape)

  g_drawLayers.draw(g_nvgContext)

  ui.lastHotItem = ui.hotItem

  # Widget specific postprocessing
  #
  # NOTE: These must be called before the "Active state reset" section below
  # as they usually depend on the pre-reset value of the activeItem!
  scrollBarPost()
  sliderPost()

  # Active state reset
  if ui.mbLeftDown or ui.mbRightDown or ui.mbMiddleDown:
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

  if ui.framesLeft > 0:
    dec(ui.framesLeft)

# }}}
# {{{ shouldRenderNextFrame*()
proc shouldRenderNextFrame*(): bool =
  alias(ui, g_uiState)
  ui.framesLeft > 0
# }}}
# {{{ nvgContext*()
proc nvgContext*(): NVGContext =
  g_nvgContext

# }}}

# vim: et:ts=2:sw=2:fdm=marker
