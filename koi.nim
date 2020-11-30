import hashes
import json
import lenientops
import math
import options
import sequtils
import sets
import strformat
import strutils
import tables
import unicode

import glfw
from glfw/wrapper import setCursor, createStandardCursor, CursorShape
import glm
import nanovg
import with

import koi/ringbuffer
import koi/undomanager
import koi/utils

export CursorShape

# {{{ Types

type ItemId = int64

# {{{ DrawLayer
#
type
  DrawLayer = enum
    layerDefault,
    layerDialog,
    layerPopup,
    layerWidgetOverlay,
    layerTooltip,
    layerGlobalOverlay

# }}}

# {{{ ColorPickerState

type
  ColorPickerColorMode = enum
    ccmRGB, ccmHSV, ccmHex

  ColorPickerMouseMode = enum
    cmmNormal, cmmLMBDown, cmmDragWheel, cmmDragTriangle

  ColorPickerStateVars = object
    opened:        bool
    colorMode:     ColorPickerColorMode
    lastColorMode: ColorPickerColorMode
    mouseMode:     ColorPickerMouseMode
    activeItem:    ItemId
    h, s, v:       float
    hexString:     string
    lastHue:       float

# }}}
# {{{ DropDownState

type
  DropDownState = enum
    dsClosed, dsOpenLMBPressed, dsOpen

  DropDownStateVars = object
    state:      DropDownState

    # Drop-down in open mode, 0 if no drop-down is open currently.
    activeItem: ItemId

# }}}
# {{{ PopupState

type
  PopupState = enum
    psOpenLMBDown, psOpen

  PopupStateVars = object
    state:     PopupState
    prevLayer: DrawLayer
    closed:    bool
    widgetInsidePopupCapturedFocus: bool

# }}}
# {{{ RadioButtonState

type
  RadioButtonStateVars = object
    activeItem: Natural

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
# {{{ ScrollViewState

type
  ScrollViewStateVars = object
    activeItem: Natural

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
    cursorPosX:   float
    cursorPosY:   float

    valueText:    string
    editModeItem: ItemId
    textFieldId:  ItemId

# }}}
# {{{ TextAreaState
type
  TextSelection = object
    # Rune position of the start of the selection (inclusive),
    # -1 if nothing is selected.
    startPos: int

    # Rune position of the end of the selection (exclusive)
    endPos:   Natural

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

    # Text area item in edit mode, 0 if no text area is being edited
    activeItem:      ItemId

    # The text is displayed starting from the row of this index
    displayStartRow: float

    # The text will be drawn at thix Y coordinate (can be smaller than the
    # starting Y coordinate of the textbox)
    displayStartY:   float

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

    # The text is displayed starting from the Rune of this index.
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
# {{{ TooltipState

type
  TooltipState = enum
    tsOff, tsShowDelay, tsShow, tsFadeOutDelay, tsFadeOut

  TooltipStateVars = object
    state:       TooltipState
    lastState:   TooltipState

    # Used for the various tooltip delays & timeouts.
    t0:          float
    text:        string

    # Hot item from the last frame
    lastHotItem: ItemId

# }}}

# {{{ WidgetState

type WidgetState* = enum
  wsNormal, wsHover, wsDown, wsActive, wsActiveHover, wsDisabled

# }}}
# {{{ WidgetGrouping
type WidgetGrouping = enum
  wgNone, wgStart, wgMiddle, wgEnd

# }}}

# {{{ UIState

type
  EventKind* = enum
    ekKey, ekMouseButton, ekScroll

  Event* = object
    case kind*: EventKind
    of ekKey:
      key*:     Key
      action*:  KeyAction

    of ekMouseButton:
      button*:  MouseButton
      pressed*: bool
      x*, y*:   float64

    of ekScroll:
      ox*, oy*: float64

    mods*:      set[ModifierKey]

  UIState = object
    # General state
    # *************
    hasEvent:       bool
    currEvent:      Event
    eventHandled:   bool

    # Frames left to render; this is decremented in endFrame()
    framesLeft:     Natural

    # This is the draw layer all widgets will draw on
    currentLayer:   DrawLayer

    # Window dimensions (in virtual pixels)
    winWidth, winHeight: float

    # Set if a widget has captured the focus (e.g. a textfield in edit mode) so
    # all other UI interactions (hovers, tooltips, etc.) should be disabled.
    focusCaptured:  bool

    tooltipState:     TooltipStateVars

    # True if a dialog is currently open
    dialogOpen:       bool

    # Reset to empty seq at the start of the frame
    drawOffsetStack: seq[DrawOffset]

    # Mouse state
    # -----------
    mx, my:          float

    # When widgetMouseDrag is true, only dx and dy are updated instead
    # of mx and my
    widgetMouseDrag: bool
    dx, dy:    float

    # Mouse cursor position from the last frame.
    lastmx, lastmy:  float

    mbLeftDown:      bool
    mbRightDown:     bool
    mbMiddleDown:    bool

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
    hotItem:        ItemId    # reset at the start of the frame to 0
    activeItem:     ItemId

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

    # Global widget states (per widget type)
    colorPickerState: ColorPickerStateVars
    dropDownState:    DropDownStateVars
    popupState:       PopupStateVars
    radioButtonState: RadioButtonStateVars
    scrollBarState:   ScrollBarStateVars
    scrollViewState:  ScrollViewStateVars
    sliderState:      SliderStateVars
    textAreaState:    TextAreaStateVars
    textFieldState:   TextFieldStateVars

    # Per-instance data storage for widgets that require it (e.g. ScrollView)
    itemState:        Table[ItemId, ref RootObj]

    # Auto-layout
    # ***********
    autoLayoutParams: AutoLayoutParams
    autoLayoutState:  AutoLayoutStateVars


  DrawOffset = object
    # Origin offset, used for relative coordinate handling (e.g in dialogs)
    ox, oy: float

  AutoLayoutParams* = object
    rowWidth*:         float
    labelWidth*:       float
    itemsPerRow*:      Natural
    rowPad*:           float
    rowGroupPad*:      float
    defaultRowHeight*: float

  AutoLayoutStateVars = object
    x, y:              float
    yNoPad:            float
    currColIndex:      Natural
    nextItemWidth:     float
    nextItemHeight:    float
    insideGroup:       bool

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

# TODO these could become settable global parameters
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

  # TODO make it a font param for every widget
  TextVertAlignFactor = 0.55

  DoubleClickMaxDelay = 0.1
  DoubleClickMaxXOffs = 4.0
  DoubleClickMaxYOffs = 4.0

  WindowEdgePad = 10.0

# }}}

# {{{ Event helpers

proc hashId*(id: string): ItemId =
  let hash32 = hash(id).uint32
  # Make sure the IDs are always positive integers
  let h = int64(hash32) - int32.low + 1
  assert h > 0
  h

proc mkIdString*(filename: string, line: int, id: string): string =
  result = filename & ":" & $line & ":" & id

var g_lastIdString: string

proc generateId*(filename: string, line: int, id: string): ItemId =
  let idString = mkIdString(filename, line, id)
  g_lastIdString = idString
  hashId(idString)

proc lastIdString*(): string = g_lastIdString

proc setFramesLeft*(n: Natural = 5) =
  alias(ui, g_uiState)
  ui.framesLeft = 5

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

proc hasHotItem*(): bool =
  g_uiState.hotItem > 0

proc hasNoActiveItem*(): bool =
  g_uiState.activeItem == 0

proc hasActiveItem*(): bool =
  g_uiState.activeItem > 0

proc isDialogOpen*(): bool =
  g_uiState.dialogOpen

proc isHit*(x, y, w, h: float): bool =
  alias(ui, g_uiState)
  not ui.focusCaptured and mouseInside(x, y, w, h)

proc winWidth*():  float = g_uiState.winWidth
proc winHeight*(): float = g_uiState.winHeight

proc mx*(): float = g_uiState.mx
proc my*(): float = g_uiState.my

proc lastmx*(): float = g_uiState.lastmx
proc lastmy*(): float = g_uiState.lastmy


proc hasEvent*(): bool =
  alias(ui, g_uiState)

  not ui.focusCaptured and ui.hasEvent and (not ui.eventHandled)

#  template calcHasEvent(): bool =
#    ui.hasEvent and (not ui.eventHandled) and not ui.focusCaptured

  # TODO isn't this a bit hacky?
#  if ui.isDialogOpen:
#    if ui.insideDialog: calcHasEvent()
#    else: false
#  else: calcHasEvent()

proc currEvent*(): Event = g_uiState.currEvent

proc setEventHandled*() =
  g_uiState.eventHandled = true

proc mbLeftDown*():   bool = g_uiState.mbLeftDown
proc mbRightDown*():  bool = g_uiState.mbRightDown
proc mbMiddleDown*(): bool = g_uiState.mbMiddleDown

proc isKeyDown*(key: Key): bool =
  if key == keyUnknown: false
  else: g_uiState.keyStates[ord(key)]

proc shiftDown*(): bool = isKeyDown(keyLeftShift)   or isKeyDown(keyRightShift)
proc altDown*():   bool = isKeyDown(keyLeftAlt)     or isKeyDown(keyRightAlt)
proc ctrlDown*():  bool = isKeyDown(keyLeftControl) or isKeyDown(keyRightControl)
proc superDown*(): bool = isKeyDown(keyLeftSuper)   or isKeyDown(keyRightSuper)

# }}}
# {{{ Drawing utils

# {{{ snapToGrid*()
func snapToGrid*(x, y, w, h, strokeWidth: float): (float, float, float, float) =
  let s = (strokeWidth mod 2) * 0.5
  let
    x = round(x) - s
    y = round(y) - s
    w = round(w) + s*2
    h = round(h) + s*2
  result = (x, y, w, h)

# }}}
# {{{ fitRectWithinWindow*()
proc fitRectWithinWindow*(w, h: float, ax, ay, aw, ah: float,
                          align: HorizontalAlign): (float, float) =
  alias(ui, g_uiState)

  var x = case align
          of haLeft:   ax
          of haCenter: ax+aw*0.5 - w*0.5
          of haRight:  ax+aw

  var y = ay+ah
  let pad = WindowEdgePad

  if x+w > ui.winWidth  - pad: x = ax+aw - w
  if y+h > ui.winHeight - pad: y = ay-h

  if   x < pad: x = pad
  elif x+w > ui.winWidth - pad: x = ui.winWidth - pad - w

  if   y < pad: y = pad
  elif y+h > ui.winHeight - pad: y = ui.winHeight - pad - h

  result = (x, y)

# }}}

# {{{ setFont*()
proc setFont*(vg: NVGContext, size: float, name: string = "sans-bold",
              horizAlign: HorizontalAlign = haLeft,
              vertAlign: VerticalAlign = vaMiddle) =
  vg.fontFace(name)
  vg.fontSize(size)
  vg.textAlign(horizAlign, vertAlign)

# }}}
# {{{ textBreakLines*()
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


const TextBreakRunes = @[
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

  if text == "":
    return @[TextRow(
      startPos:       0,
      startBytePos:   0,
      endPos:         0,
      endBytePos:     0,
      nextRowPos:     -1,
      nextRowBytePos: -1,
      width:          0
    )]

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
        if prevRune in TextBreakRunes and rune notin TextBreakRunes:
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

        let lastEmptyRowStartPos = textLen
        let lastEmptyRowStartBytePos = textBytePos+1

        result.add(TextRow(
          startPos:       rowStartPos,
          startBytePos:   rowStartBytePos,
          endPos:         textPos,
          endBytePos:     textBytePos,
          nextRowPos:     lastEmptyRowStartPos,
          nextRowBytePos: lastEmptyRowStartBytePos,
          width:          runeBeforeNewLineEndX - rowStartX
        ))
        result.add(TextRow(
          startPos:       lastEmptyRowStartPos,
          startBytePos:   lastEmptyRowStartBytePos,
          endPos:         lastEmptyRowStartPos,
          endBytePos:     lastEmptyRowStartBytePos,
          nextRowPos:     -1,
          nextRowBytePos: -1,
          width:          0
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

# {{{ pushDrawOffset*()
proc pushDrawOffset*(ds: DrawOffset) =
  alias(ui, g_uiState)
  ui.drawOffsetStack.add(ds)

# }}}
# {{{ popDrawOffset*()
proc popDrawOffset*() =
  alias(ui, g_uiState)
  if ui.drawOffsetStack.len > 1:
    discard ui.drawOffsetStack.pop()

# }}}
# {{{ drawOffset*()
proc drawOffset(): DrawOffset =
  g_uiState.drawOffsetStack[^1]

# }}}
# {{{ addDrawOffset*()
proc addDrawOffset*(x, y: float): (float, float) =
  let offs = drawOffset()
  result = (offs.ox + x, offs.oy + y)

# }}}

# {{{ toHSV*()
proc toHSV*(c: Color): (float, float, float) =
  let
    r = c.r
    g = c.g
    b = c.b
    xmax = max(r, max(g, b))
    xmin = min(r, min(g, b))
    v = xmax
    c = xmax - xmin

  let h = if   c == 0: 0.0
          elif v == r: ((60 * (g-b)/c + 360) mod 360) / 360
          elif v == g: ((60 * (b-r)/c + 120) mod 360) / 360
          else:        ((60 * (r-g)/c + 240) mod 360) / 360  # v == b

  let s = if v == 0.0: 0.0 else: c/v

  result = (h.float, s.float, v.float)

# }}}
# {{{ hsva*()
proc hsva(h, s, v, a: float): Color =
  var r, g, b: float
  if s == 0.0:
    r = v
    g = v
    b = v
  else:
    let
      hf = if h >= 1.0: 0.0 else: h*6
      i = hf.int  # should be in the range 0..5
      f = hf - i  # fractional part

      m = v * (1 - s)
      n = v * (1 - s*f)
      k = v * (1 - s*(1-f))

    (r, g, b) = if   i == 0: (v, k, m)
                elif i == 1: (n, v, m)
                elif i == 2: (m, v, k)
                elif i == 3: (m, n, v)
                elif i == 4: (k, m, v)
                else:        (v, m, n)

  result = rgba(r, g, b, a)

# }}}
# {{{ toHex*()
proc toHex*(c: Color): string =
  (c.r * 255).int.toHex(2) &
  (c.g * 255).int.toHex(2) &
  (c.b * 255).int.toHex(2)

# }}}
# {{{ colorFromHex*()
proc colorFromHexStr*(s: string): Color =
  try:
    let r = parseHexInt(s.substr(0, 1)) / 255
    let g = parseHexInt(s.substr(2, 3)) / 255
    let b = parseHexInt(s.substr(4, 5)) / 255
    result = rgb(r, g, b)
  except CatchableError:
    discard

# }}}

# {{{ rightClippedRoundedRect*()
proc rightClippedRoundedRect*(vg: NVGContext, x, y, w, h, r, clipW: float,
                              grouping: WidgetGrouping = wgNone) =
  alias(vg, g_nvgContext)

  vg.beginPath()

  if grouping == wgMiddle:
    vg.rect(x, y, clipW, h)
  else:
    if clipW < r:
      # top left
      if grouping == wgEnd:
        vg.moveTo(x, y)
        vg.lineTo(x+clipW, y)
      else:
        let da = arccos((r - clipW) / r)
        vg.arc(x+r, y+r, r, PI, PI + da, pwCW)

      # bottom left
      if grouping == wgStart:
        vg.lineTo(x+clipW, y+h)
        vg.lineTo(x, y+h)
      else:
        let da = arccos((r - clipW) / r)
        vg.arc(x+r, y+h-r, r, PI - da, PI, pwCW)
      vg.closePath()

    elif clipW <= w-r:
      # top left
      if grouping == wgEnd:
        vg.moveTo(x, y)
      else:
        vg.arc(x+r, y+r, r, PI, 1.5*PI, pwCW)

      # flat end cap
      vg.lineTo(x+clipW, y)
      vg.lineTo(x+clipW, y+h)

      # bottom left
      if grouping == wgStart:
        vg.lineTo(x, y+h)
      else:
        vg.lineTo(x+r, y+h)
        vg.arc(x+r, y+h-r, r, PI*0.5, PI, pwCW)
      vg.closePath()

    else:
      # top left
      if grouping == wgEnd:
        vg.moveTo(x, y)
      else:
        vg.arc(x+r, y+r, r, PI, 1.5*PI, pwCW)

      # top right
      if grouping == wgEnd:
        vg.lineTo(x+clipW, y)
      else:
        let dx = clipW - (w-r)
        let da = arccos(dx / r)
        vg.arc(x+w-r, y+r, r, 1.5*PI, 1.5*PI + (PI*0.5-da), pwCW)

      # bottom right
      if grouping == wgStart:
        vg.lineTo(x+clipW, y+h)
      else:
        let dx = clipW - (w-r)
        let da = arccos(dx / r)
        vg.arc(x+w-r, y+h-r, r, da, PI*0.5, pwCW)

      # bottom left
      if grouping == wgStart:
        vg.lineTo(x, y+h)
      else:
        vg.arc(x+r, y+h-r, r, PI*0.5, PI, pwCW)
      vg.closePath()

# }}}

# }}}
# {{{ Draw layers

type
  DrawProc = proc (vg: NVGContext)

  DrawLayers = object
    layers:        array[0..ord(DrawLayer.high), seq[DrawProc]]
    lastUsedLayer: Natural

var
  g_drawLayers: DrawLayers

proc init(dl: var DrawLayers) =
  for i in 0..dl.layers.high:
    dl.layers[i] = @[]

proc add(dl: var DrawLayers, layer: Natural, p: DrawProc) =
  dl.layers[layer].add(p)
  dl.lastUsedLayer = layer

template addDrawLayer(layer: DrawLayer, vg, body: untyped) =
  g_drawLayers.add(ord(layer), proc (vg: NVGContext) =
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
  tesCursorToLineStart,
  tesCursorToLineEnd,
  tesCursorToDocumentStart,
  tesCursorToDocumentEnd,
  tesCursorToPreviousLine,
  tesCursorToNextLine,
  tesCursorPageUp,
  tesCursorPageDown,

  tesSelectionAll,
  tesSelectionOneCharLeft,
  tesSelectionOneCharRight,
  tesSelectionToPreviousWord,
  tesSelectionToNextWord,
  tesSelectionToLineStart,
  tesSelectionToLineEnd,
  tesSelectionToDocumentStart,
  tesSelectionToDocumentEnd,
  tesSelectionToPreviousLine,
  tesSelectionToNextLine,
  tesSelectionPageUp,
  tesSelectionPageDown,

  tesDeleteOneCharLeft,
  tesDeleteOneCharRight,
  tesDeleteWordToRight,
  tesDeleteWordToLeft,
  tesDeleteToLineStart,
  tesDeleteToLineEnd,

  tesCutText,
  tesCopyText,
  tesPasteText,

  tesInsertNewline,

  tesPrevTextField,
  tesNextTextField,

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

  tesCursorToLineStart:       @[mkKeyShortcut(keyHome,    {}),
                                mkKeyShortcut(keyKp7,     {})],

  tesCursorToLineEnd:         @[mkKeyShortcut(keyEnd,     {}),
                                mkKeyShortcut(keyKp1,     {})],

  tesCursorToDocumentStart:   @[mkKeyShortcut(keyHome,    {mkCtrl}),
                                mkKeyShortcut(keyKp7,     {mkCtrl})],

  tesCursorToDocumentEnd:     @[mkKeyShortcut(keyEnd,     {mkCtrl}),
                                mkKeyShortcut(keyKp1,     {mkCtrl})],

  tesCursorToPreviousLine:    @[mkKeyShortcut(keyUp,      {}),
                                mkKeyShortcut(keyKp8,     {})],

  tesCursorToNextLine:       @[mkKeyShortcut(Key.keyDown, {}),
                               mkKeyShortcut(keyKp2,      {})],

  tesCursorPageUp:            @[mkKeyShortcut(keyPageUp,  {}),
                                mkKeyShortcut(keyKp9,     {})],

  tesCursorPageDown:         @[mkKeyShortcut(keyPageDown, {}),
                               mkKeyShortcut(keyKp3,      {})],

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

  tesSelectionToLineStart:    @[mkKeyShortcut(keyHome,    {mkShift}),
                                mkKeyShortcut(keyKp7,     {mkShift})],

  tesSelectionToLineEnd:      @[mkKeyShortcut(keyEnd,     {mkShift}),
                                mkKeyShortcut(keyKp1,     {mkShift})],

  tesSelectionToDocumentStart:   @[mkKeyShortcut(keyHome, {mkCtrl, mkShift}),
                                mkKeyShortcut(keyKp7,     {mkCtrl, mkShift})],

  tesSelectionToDocumentEnd:  @[mkKeyShortcut(keyEnd,     {mkCtrl, mkShift}),
                                mkKeyShortcut(keyKp1,     {mkCtrl, mkShift})],

  tesSelectionToPreviousLine: @[mkKeyShortcut(keyUp,      {mkShift}),
                                mkKeyShortcut(keyKp8,     {mkShift})],

  tesSelectionToNextLine:    @[mkKeyShortcut(Key.keyDown, {mkShift}),
                               mkKeyShortcut(keyKp2,      {mkShift})],

  tesSelectionPageUp:        @[mkKeyShortcut(keyPageUp,   {mkShift}),
                               mkKeyShortcut(keyKp9,      {mkShift})],

  tesSelectionPageDown:      @[mkKeyShortcut(keyPageDown, {mkShift}),
                               mkKeyShortcut(keyKp3,      {mkShift})],

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
  tesInsertNewline:           @[mkKeyShortcut(keyEnter,   {mkShift}),
                                mkKeyShortcut(keyKpEnter, {mkShift})],

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

  tesInsertNewline:        @[mkKeyShortcut(keyEnter,   {mkShift})],

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


const EventBufSize = 64
var g_eventBuf = initRingBuffer[Event](EventBufSize)


# No key events will be generated for these keys
# TODO this could be made configurable
const ExcludedKeyEvents = @[
  keyLeftShift,
  keyLeftControl,
  keyLeftAlt,
  keyLeftSuper,
  keyRightShift,
  keyRightControl,
  keyRightAlt,
  keyRightSuper,
  keyCapsLock,
  keyScrollLock,
  keyNumLock
]

proc keyCb(win: Window, key: Key, scanCode: int32, action: KeyAction,
           mods: set[ModifierKey]) =

  alias(ui, g_uiState)

  let keyIdx = ord(key)
  if keyIdx >= 0 and keyIdx <= ui.keyStates.high:
    case action
    of kaDown, kaRepeat: ui.keyStates[keyIdx] = true
    of kaUp:             ui.keyStates[keyIdx] = false

  if key notin ExcludedKeyEvents:
    let event = Event(
      kind: ekKey,
      key: key, action: action, mods: mods
    )
    discard g_eventBuf.write(event)


proc clearEventBuf*() = g_eventBuf.clear()

# {{{ toClipboard*()
proc toClipboard*(s: string) =
  glfw.currentContext().clipboardString = s

# }}}
# {{{ fromClipboard*()
proc fromClipboard*(): string =
  $glfw.currentContext().clipboardString

# }}}

# }}}
# {{{ Mouse handling

proc mouseButtonCb(win: Window, button: MouseButton, pressed: bool,
                   modKeys: set[ModifierKey]) =

  let (x, y) = win.cursorPos()

  discard g_eventBuf.write(
    Event(
      kind: ekMouseButton,
      button: button,
      pressed: pressed,
      x: x,
      y: y,
      mods: modKeys
    )
  )

proc scrollCb(win: Window, offset: tuple[x, y: float64]) =
  # The scroll callback seems to only be called during pollEvents/waitEvents.
  # GLFW coalesces all scroll events since the last poll into a single event.
  discard g_eventBuf.write(
    Event(
      kind: ekScroll,
      ox: offset.x,
      oy: offset.y
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

proc setCursorMode*(cs: CursorShape) =
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
# {{{ Layout handling

# {{{ initAutoLayout()
proc initAutoLayout() =
  alias(ui, g_uiState)
  alias(a,  ui.autoLayoutState)
  alias(ap, ui.autoLayoutParams)

  a = AutoLayoutStateVars.default
  a.nextItemWidth  = ap.labelWidth
  a.nextItemHeight = ap.defaultRowHeight

# }}}
# {{{ handleAutoLayout()
proc handleAutoLayout(height: float = -1, forceNextRow: bool = false) =
  alias(a, g_uiState.autoLayoutState)
  alias(ap, g_uiState.autoLayoutParams)

  inc(a.currColIndex)

  let h = if height >= 0: height else: ap.defaultRowHeight

  if a.currColIndex == ap.itemsPerRow or forceNextRow:
    a.currColIndex = 0
    a.nextItemWidth = ap.labelWidth
    a.x = 0

    a.y += h
    a.yNoPad = a.y
    a.y += (if a.insideGroup: ap.rowPad else: ap.rowGroupPad)

  # TODO this only works for the default 2-column layout
  else:
    a.x = ap.labelWidth
    a.nextItemWidth = ap.rowWidth - ap.labelWidth
    a.nextItemHeight = h

# }}}

# {{{ setAutoLayoutParams*()
#
const DefaultAutoLayoutParams = AutoLayoutParams(
  rowWidth:         300.0,
  labelWidth:       180.0,
  itemsPerRow:      2,
  rowPad:           6.0,
  rowGroupPad:      18.0,
  defaultRowHeight: 22.0
)

proc setAutoLayoutParams*(params: AutoLayoutParams) =
  alias(ui, g_uiState)
  ui.autoLayoutParams = params
  initAutoLayout()

# }}}
# {{{ beginGroup*()
proc beginGroup*() =
  alias(a, g_uiState.autoLayoutState)
  a.insideGroup = true

# }}}
# {{{ endGroup*()
proc endGroup*() =
  alias(a, g_uiState.autoLayoutState)
  alias(ap, g_uiState.autoLayoutParams)

  a.y += ap.rowGroupPad
  a.insideGroup = false

# }}}
# {{{ group*()
template group*(body: untyped) =
  beginGroup()
  body
  endGroup()

# }}}

# }}}

# {{{ Widgets

# {{{ Shadow

type ShadowStyle* = ref object
  enabled*:      bool
  cornerRadius*: float
  xOffset*:      float
  yOffset*:      float
  widthOffset*:  float
  heightOffset*: float
  feather*:      float
  color*:        Color

var DefaultShadowStyle = ShadowStyle(
  enabled      : true,
  cornerRadius : 10.0,
  xOffset      : 1.0,
  yOffset      : 2.0,
  widthOffset  : 0.0,
  heightOffset : 0.0,
  feather      : 10.0,
  color        : black(0.4)
)

proc getDefaultShadowStyle*(): ShadowStyle =
  DefaultShadowStyle.deepCopy

proc setDefaultShadowStyle*(style: ShadowStyle) =
  DefaultShadowStyle = style.deepCopy

# {{{ drawShadow*()
proc drawShadow*(vg: NVGContext, x, y, w, h: float,
                 style: ShadowStyle = DefaultShadowStyle) =
  alias(s, style)

  if s.enabled:
    let (x, y, w, h) = snapToGrid(x, y, w, h, strokeWidth=0)

    let shadow = vg.boxGradient(x + s.xOffset,
                                y + s.yOffset,
                                w + s.widthOffset,
                                h + s.heightOffset,
                                s.cornerRadius, s.feather,
                                s.color, black(0.0))
    vg.fillPaint(shadow)

    vg.beginPath()
    vg.rect(
      x + s.xOffset - s.feather*0.5,
      y + s.yOffset - s.feather*0.5,
      w + s.widthOffset + s.feather,
      h + s.heightOffset + s.feather,
    )
    vg.fill()

# }}}

# }}}
# {{{ Tooltip

# {{{ handleTooltip*()

proc handleTooltip*(id: ItemId, tooltip: string) =
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
         tt.lastHotItem != id:
      tt.state = tsShowDelay
      tt.t0 = getTime()
      setFramesLeft()

    elif tt.state >= tsShow:
      tt.state = tsShow
      tt.t0 = getTime()
      tt.text = tooltip
      setFramesLeft()

# }}}
# {{{ drawTooltip()

proc drawTooltip(x, y: float, text: string, alpha: float = 1.0) =
  alias(vg, g_nvgContext)

  # TODO make visual parameters configurable
  addDrawLayer(layerTooltip, vg):
    var w = 300.0
    let fontSize = 14.0
    let lineHeight = 1.4
    let padX = 10.0
    let padY = 10.0

    vg.setFont(fontSize, "sans-bold")

    var rows = textBreakLines(text, w-padX*2)
    let h = fontSize * lineHeight * rows.len + padY*2

    if rows.len == 1:
      w = vg.textWidth(text) + padX*2

    var (x, y) = fitRectWithinWindow(w, h, x-8, y-8, 30, 30, haLeft)

    # Draw shadow
    var shadow = DefaultShadowStyle.deepCopy
    shadow.color.a = shadow.color.a * alpha
    drawShadow(vg, x, y, w, h, shadow)

    # Draw tooltip background
    vg.beginPath()
    vg.roundedRect(x, y, w, h, 5)
    vg.fillColor(gray(0.1, 0.88 * alpha))
    vg.fill()

    # Draw text
    vg.fillColor(white(0.9 * alpha))

    x += padX
    y += padY + fontSize * lineHeight * 0.55 # TODO hacky

    for row in rows:
      discard vg.text(x, y, text, row.startBytePos, row.endBytePos)
      y += fontSize * lineHeight

# }}}
# {{{ tooltipPost()

proc tooltipPost() =
  alias(ui, g_uiState)
  alias(tt, ui.tooltipState)

  let
    ttx = ui.mx
    tty = ui.my

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

  tt.lastHotItem = ui.hotItem

# }}}

# }}}
# {{{ Popup

type PopupStyle* = ref object
  autoClose*:              bool
  autoCloseBorder*:        float
  backgroundCornerRadius*: float
  backgroundStrokeWidth*:  float
  backgroundStrokeColor*:  Color
  backgroundFillColor*:    Color
  shadow*:                 ShadowStyle

var DefaultPopupStyle = PopupStyle(
  autoClose              : true,
  autoCloseBorder        : 40,
  backgroundCornerRadius : 5,
  backgroundStrokeWidth  : 0,
  backgroundStrokeColor  : black(),
  backgroundFillColor    : gray(0.1),
  shadow                 : getDefaultShadowStyle()
)

proc getDefaultPopupStyle*(): PopupStyle =
  DefaultPopupStyle.deepCopy

proc setDefaultPopupStyle*(style: PopupStyle) =
  DefaultPopupStyle = style.deepCopy

# {{{ closePopup*()
proc closePopup*() =
  alias(ui, g_uiState)
  alias(ps, ui.popupState)

  ui.focusCaptured = false
  ps.state = psOpenLMBDown  # just resetting the default state
  ps.closed = true

# }}}
# {{{  beginPopup*()
proc beginPopup*(w, h: float,
                 ax, ay, aw, ah: float,
                 style: PopupStyle = DefaultPopupStyle): bool =
  alias(ui, g_uiState)
  alias(ps, ui.popupState)
  alias(s, style)

  var (x, y) = addDrawOffset(ax, ay)
  (x, y) = fitRectWithinWindow(w, h, x, y, aw, ah, haLeft)

  # Hit testing
  let
    inside = mouseInside(x, y, w, h)
    b = s.autoCloseBorder
    insideBorder = mouseInside(x-b, y-b, w+b*2, h+b*2)

  if ps.state == psOpenLMBDown:
    ps.closed = false
    if not ui.mbLeftDown:
      ps.state = psOpen

  if not ps.widgetInsidePopupCapturedFocus and ps.state == psOpen and
     ((s.autoClose and not (inside or insideBorder)) or
     (ui.mbLeftDown and not inside)):
    closePopup()
    result = false
  else:
    ps.prevLayer = ui.currentLayer

    # Draw popup window
    addDrawLayer(layerPopup, vg):
      drawShadow(vg, x, y, w, h, s.shadow)

      # Draw background
      let sw = s.backgroundStrokeWidth
      let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

      vg.fillColor(s.backgroundFillColor)
      vg.strokeColor(s.backgroundStrokeColor)
      vg.strokeWidth(sw)

      vg.beginPath()
      vg.roundedRect(x, y, w, h, s.backgroundCornerRadius)
      vg.fill()
      vg.stroke()


    pushDrawOffset(
      DrawOffset(ox: x, oy: y)
    )

    ui.focusCaptured = ps.widgetInsidePopupCapturedFocus
    ui.currentLayer = layerPopup

    result = true

# }}}
# {{{ endPopup*()
proc endPopup*() =
  alias(ui, g_uiState)
  alias(ps, ui.popupState)

  if ui.focusCaptured:
    ps.widgetInsidePopupCapturedFocus = true
  else:
    ps.widgetInsidePopupCapturedFocus = false

  popDrawOffset()

  # Do nothing closePopup() was called before this
  if not ps.closed:
    ui.focusCaptured = true
    ui.currentLayer = ps.prevLayer

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
  shadow*:             ShadowStyle

var DefaultDialogStyle = DialogStyle(
  cornerRadius      : 7.0,
  backgroundColor   : gray(0.2),
  titleBarBgColor   : gray(0.05),
  titleBarTextColor : gray(0.85),
  outerBorderColor  : black(),
  innerBorderColor  : white(),
  outerBorderWidth  : 0.0,
  innerBorderWidth  : 0.0
)

DefaultDialogStyle.shadow = ShadowStyle(
  enabled      : true,
  cornerRadius : 12.0,
  xOffset      : 2.0,
  yOffset      : 3.0,
  widthOffset  : 0.0,
  heightOffset : 0.0,
  feather      : 25.0,
  color        : black(0.4)
)

proc getDefaultDialogStyle*(): DialogStyle =
  DefaultDialogStyle.deepCopy

proc setDefaultDialogStyle*(style: DialogStyle) =
  DefaultDialogStyle = style.deepCopy

# {{{ beginDialog()
proc beginDialog*(w, h: float, title: string,
                  style: DialogStyle = DefaultDialogStyle) =

  alias(ui, g_uiState)
  alias(s, style)

  ui.dialogOpen = true
  ui.focusCaptured = false

  let
    x = floor((ui.winWidth - w) / 2)
    y = floor((ui.winHeight - h) / 2)

  ui.currentLayer = layerDialog

  addDrawLayer(ui.currentLayer, vg):
    const TitleBarHeight = 30.0

    drawShadow(vg, x, y, w, h, s.shadow)

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
    vg.roundedRect(x, y, w, TitleBarHeight,
                   s.cornerRadius, s.cornerRadius, 0, 0)
    vg.fill()

    # TODO use label
    vg.fontFace("sans-bold")
    vg.fontSize(15.0)
    vg.textAlign(haLeft, vaMiddle)
    vg.fillColor(s.titleBarTextColor)
    discard vg.text(x+10.0, y + TitleBarHeight * TextVertAlignFactor, title)

  pushDrawOffset(
    DrawOffset(ox: x, oy: y)
  )

# }}}
# {{{ endDialog()
proc endDialog*() =
  alias(ui, g_uiState)

  popDrawOffset()
  ui.currentLayer = layerDefault
  if ui.dialogOpen:
    ui.focusCaptured = true

# }}}
# {{{ closeDialog()
proc closeDialog*() =
  alias(ui, g_uiState)

  ui.focusCaptured = false
  ui.dialogOpen = false

# }}}

# }}}

# {{{ Label

type LabelStyle* = ref object
  fontSize*:         float
  fontFace*:         string
  vertAlignFactor*:  float
  padHoriz*:         float
  align*:            HorizontalAlign
  multiLine*:        bool
  lineHeight*:       float
  color*:            Color
  colorHover*:       Color
  colorDown*:        Color
  colorActive*:      Color
  colorActiveHover*: Color
  colorDisabled*:    Color

var DefaultLabelStyle = LabelStyle(
  fontSize         : 14.0,
  fontFace         : "sans-bold",
  vertAlignFactor  : 0.55,
  padHoriz         : 0.0,
  align            : haLeft,
  multiLine        : false,
  lineHeight       : 1.4,
  color            : gray(0.7),
  colorHover       : gray(0.7),
  colorDown        : gray(0.7),
  colorActive      : gray(1.0),
  colorActiveHover : gray(1.0),
  colorDisabled    : gray(0.25)
)

proc getDefaultLabelStyle*(): LabelStyle =
  DefaultLabelStyle.deepCopy

proc setDefaultLabelStyle*(style: LabelStyle) =
  DefaultLabelStyle = style.deepCopy

# {{{ drawLabel()
proc drawLabel(vg: NVGContext; x, y, w, h: float; label: string;
               state: WidgetState = wsNormal,
               style: LabelStyle = DefaultLabelStyle) =
  alias(s, style)
  let
    textBoxX = x + s.padHoriz
    textBoxW = w - s.padHoriz*2
    textBoxY = y
    textBoxH = h

  let tx = case s.align:
  of haLeft:   textBoxX
  of haCenter: textBoxX + textBoxW*0.5
  of haRight:  textBoxX + textBoxW

  let ty = y + h*s.vertAlignFactor

  vg.save()

  vg.intersectScissor(textBoxX, textBoxY, textBoxW, textBoxH)

  vg.setFont(s.fontSize, s.fontFace, s.align)

  let color = case state
              of wsNormal:      s.color
              of wsHover:       s.colorHover
              of wsDown:        s.colorDown
              of wsActive:      s.colorActive
              of wsActiveHover: s.colorActiveHover
              of wsDisabled:    s.colorDisabled

  vg.fillColor(color)

  if s.multiLine:
    vg.textLineHeight(s.lineHeight)
    vg.textBox(tx, ty, textBoxW, label)
  else:
    discard vg.text(tx, ty, label)

  vg.restore()

# }}}
# {{{ label()
proc label*(x, y, w, h: float,
           labelText:  string,
           state:      WidgetState = wsNormal,
           style:      LabelStyle = DefaultLabelStyle) =

  alias(ui, g_uiState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  addDrawLayer(ui.currentLayer, vg):
    vg.drawLabel(x, y, w, h, labelText, state, style)

# }}}

proc label*(labelText: string, state: WidgetState = wsNormal,
            style: LabelStyle = DefaultLabelStyle) =
  alias(ui, g_uiState)
  alias(a, ui.autoLayoutState)

  label(a.x, a.y, a.nextItemWidth, a.nextItemHeight, labelText, state, style)

  handleAutoLayout()

# }}}
# {{{ Button

type ButtonStyle* = ref object
  cornerRadius*:        float
  strokeWidth*:         float
  strokeColor*:         Color
  strokeColorHover*:    Color
  strokeColorDown*:     Color
  strokeColorDisabled*: Color
  fillColor*:           Color
  fillColorHover*:      Color
  fillColorDown*:       Color
  fillColorDisabled*:   Color
  labelOnly*:           bool
  label*:               LabelStyle

var DefaultButtonStyle = ButtonStyle(
  cornerRadius        : 5.0,
  strokeWidth         : 0.0,
  strokeColor         : black(),
  strokeColorHover    : black(),
  strokeColorDown     : black(),
  strokeColorDisabled : black(),
  fillColor           : gray(0.6),
  fillColorHover      : GRAY_HI,
  fillColorDown       : HILITE,
  fillColorDisabled   : GRAY_LO,
  labelOnly           : false,
  label               : getDefaultLabelStyle()
)

with DefaultButtonStyle.label:
  align         = haCenter
  padHoriz      = 8.0
  color         = GRAY_LO
  colorHover    = GRAY_LO
  colorDown     = GRAY_LO
  colorDisabled = GRAY_HI


proc getDefaultButtonStyle*(): ButtonStyle =
  DefaultButtonStyle.deepCopy

proc setDefaultButtonStyle*(style: ButtonStyle) =
  DefaultButtonStyle = style.deepCopy

# {{{ button()
proc button(id:         ItemId,
            x, y, w, h: float,
            label:      string,
            tooltip:    string,
            disabled:   bool,
            style:      ButtonStyle): bool =

  alias(ui, g_uiState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if not disabled and ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHot(id) and isActive(id):
    result = true

  addDrawLayer(ui.currentLayer, vg):
    let sw = s.strokeWidth
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let state = if   disabled: wsDisabled
                elif isHot(id) and hasNoActiveItem(): wsHover
                elif isHot(id) and isActive(id): wsDown
                else: wsNormal

    let (fillColor, strokeColor, labelColor) =
      case state
      of wsNormal, wsActive, wsActiveHover:
        (s.fillColor, s.strokeColor, s.label.color)
      of wsHover:
        (s.fillColorHover, s.strokeColorHover, s.label.colorHover)
      of wsDown:
        (s.fillColorDown, s.strokeColorDown, s.label.colorDown)
      of wsDisabled:
        (s.fillColorDisabled, s.strokeColorDisabled,
         s.label.colorDisabled)

    if not s.labelOnly:
      vg.fillColor(fillColor)
      vg.strokeColor(strokeColor)
      vg.strokeWidth(sw)

      vg.beginPath()
      vg.roundedRect(x, y, w, h, s.cornerRadius)
      vg.fill()
      vg.stroke()

    vg.drawLabel(x, y, w, h, label, state, s.label)

  if isHot(id):
    handleTooltip(id, tooltip)

# }}}

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
  icon*:                LabelStyle
  iconColorActive*:     Color
  iconActive*:          string
  iconInactive*:        string

var DefaultCheckBoxStyle = CheckBoxStyle(
  cornerRadius      : 5.0,
  strokeWidth       : 0.0,
  strokeColor       : black(),
  strokeColorHover  : black(),
  strokeColorDown   : black(),
  strokeColorActive : black(),
  fillColor         : GRAY_MID,
  fillColorHover    : GRAY_HI,
  fillColorDown     : GRAY_LOHI,
  fillColorActive   : GRAY_LO,
  icon              : getDefaultLabelStyle(),
  iconColorActive   : GRAY_HI,
  iconActive        : "",
  iconInactive      : ""
)

with DefaultCheckBoxStyle.icon:
  align       = haCenter
  color       = GRAY_LO
  colorHover  = GRAY_LO
  colorDown   = GRAY_HI

proc getDefaultCheckBoxStyle*(): CheckBoxStyle =
  DefaultCheckBoxStyle.deepCopy

proc setDefaultCheckBoxStyle*(style: CheckBoxStyle) =
  DefaultCheckBoxStyle = style.deepCopy

type
  CheckBoxDrawProc* = proc (vg: NVGContext,
                            x, y, w: float, active: bool, state: WidgetState,
                            style: CheckBoxStyle)

let DefaultCheckBoxDrawProc: CheckBoxDrawProc =
  proc (vg: NVGContext,
        x, y, w: float, active: bool, state: WidgetState,
        style: CheckBoxStyle) =

    alias(ui, g_uiState)
    alias(s, style)

    var (fillColor, strokeColor) = case state
      of wsNormal, wsDisabled:
        (s.fillColor, s.strokeColor)
      of wsHover:
        (s.fillColorHover, s.strokeColorHover)
      of wsDown:
        (s.fillColorDown, s.strokeColorDown)
      of wsActive, wsActiveHover:
        (s.fillColorActive, s.strokeColorActive)

    let sw = s.strokeWidth
    let (x, y, w, _) = snapToGrid(x, y, w, w, sw)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)
    vg.beginPath()
    vg.roundedRect(x, y, w, w, s.cornerRadius)
    vg.fill()
    vg.stroke()

    let icon = if active: s.iconActive else: s.iconInactive
    if icon != "":
      vg.drawLabel(x, y, w, w, icon, state, s.icon)


# {{{ checkBox()
proc checkBox(id:         ItemId,
              x, y, w:    float,
              active_out: var bool,
              tooltip:    string,
              drawProc:   CheckBoxDrawProc = DefaultCheckBoxDrawProc,
              style:      CheckBoxStyle = DefaultCheckBoxStyle) =

  var active = active_out

  alias(ui, g_uiState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  # Hit testing
  if isHit(x, y, w, w):
    setHot(id)
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
  active = if not ui.mbLeftDown and isHot(id) and isActive(id): not active
           else: active

  active_out = active

  addDrawLayer(ui.currentLayer, vg):
    let state = if   isHot(id) and hasNoActiveItem(): wsHover
                elif isHot(id) and isActive(id): wsDown
                else: wsNormal

    drawProc(vg, x, y, w, active, state, style)


  if isHot(id):
    handleTooltip(id, tooltip)

# }}}

template checkBox*(x, y, w:  float,
                   active:   var bool,
                   tooltip:  string = "",
                   drawProc: CheckBoxDrawProc = DefaultCheckBoxDrawProc,
                   style:    CheckBoxStyle = DefaultCheckBoxStyle) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  checkbox(id, x, y, w, active, tooltip, drawProc, style)


template checkBox*(active:   var bool,
                   tooltip:  string = "",
                   drawProc: CheckBoxDrawProc = DefaultCheckBoxDrawProc,
                   style:    CheckBoxStyle = DefaultCheckBoxStyle) =

  alias(ui, g_uiState)
  alias(a, ui.autoLayoutState)

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  checkbox(id, a.x, a.y, a.nextItemHeight, active, tooltip, drawProc, style)

  handleAutoLayout()

# }}}
# {{{ SectionHeader

# TODO
type SectionHeaderStyle* = ref object
  label*:     LabelStyle
#  checkBox*:  CheckBoxStyle

var DefaultSectionHeaderStyle = SectionHeaderStyle(
  label : getDefaultLabelStyle()
)

proc getDefaultSectionHeaderStyle*(): SectionHeaderStyle =
  DefaultSectionHeaderStyle.deepCopy

proc setDefaultSectionHeaderStyle*(style: SectionHeaderStyle) =
  DefaultSectionHeaderStyle = style.deepCopy


let SectionHeaderCheckboxStyle = getDefaultCheckBoxStyle()

# {{{ sectionHeader()
proc sectionHeader(id:           ItemId,
                   x, y, w, h:   float,
                   label:        string,
                   expanded_out: var bool,
                   tooltip:      string,
                   style:        SectionHeaderStyle): bool =

  alias(ui, g_uiState)
  alias(s, style)

  let (ox, oy) = (x, y)
  let (x, y) = addDrawOffset(x, y)

  let buttonWidth = h

  addDrawLayer(ui.currentLayer, vg):
    let (x, y, w, h) = snapToGrid(x, y, w, h, strokeWidth=0)

    vg.fillColor(gray(0.2))
    vg.beginPath()
    vg.rect(x, y-2, w, h+4)
    vg.fill()

    let labelColor = s.label.color

    alias(vg, g_nvgContext)
    vg.drawLabel(x+buttonWidth, y, w-buttonWidth, h, label, style=s.label)

  let cbId = hashId(lastIdString() & ":checkBox")
  checkBox(cbId, ox, oy, buttonWidth, expanded_out, tooltip,
           style=DefaultCheckBoxStyle)

  result = expanded_out

# }}}

template sectionHeader*(
  x, y, w, h: float,
  label:      string,
  expanded:   var bool,
  tooltip:    string = "",
  style:      SectionHeaderStyle = DefaultSectionHeaderStyle
): bool =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  sectionHeader(id, x, y, w, h, label, expanded, tooltip, style)
  expanded


template sectionHeader*(
  label:    string,
  expanded: var bool,
  tooltip:  string = "",
  style:    SectionHeaderStyle = DefaultSectionHeaderStyle
): bool =

  alias(ui, g_uiState)
  alias(a, ui.autoLayoutState)
  alias(ap, ui.autoLayoutParams)

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, label)

  let result = sectionHeader(id, a.x, a.y, ap.rowWidth, a.nextItemHeight,
                             label, expanded, tooltip, style)

  handleAutoLayout(forceNextRow=true)
  result

# }}}
# {{{ RadioButtons

type RadioButtonsStyle* = ref object
  buttonPadHoriz*:               float
  buttonPadVert*:                float
  buttonCornerRadius*:           float
  buttonStrokeWidth*:            float
  buttonStrokeColor*:            Color
  buttonStrokeColorHover*:       Color
  buttonStrokeColorDown*:        Color
  buttonStrokeColorActive*:      Color
  buttonStrokeColorActiveHover*: Color
  buttonFillColor*:              Color
  buttonFillColorHover*:         Color
  buttonFillColorDown*:          Color
  buttonFillColorActive*:        Color
  buttonFillColorActiveHover*:   Color
  label*:                        LabelStyle

var DefaultRadioButtonsStyle = RadioButtonsStyle(
  buttonPadHoriz               : 3.0,
  buttonPadVert                : 3.0,
  buttonCornerRadius           : 5.0,
  buttonStrokeWidth            : 0.0,
  buttonStrokeColor            : black(),
  buttonStrokeColorHover       : black(),
  buttonStrokeColorDown        : black(),
  buttonStrokeColorActive      : black(),
  buttonStrokeColorActiveHover : black(),
  buttonFillColor              : GRAY_MID,
  buttonFillColorHover         : GRAY_HI,
  buttonFillColorDown          : HILITE_LO,
  buttonFillColorActive        : HILITE,
  buttonFillColorActiveHover   : HILITE,
  label                        : getDefaultLabelStyle(),
)

with DefaultRadioButtonsStyle.label:
  align            = haCenter
  padHoriz         = 8.0
  color            = GRAY_LO
  colorHover       = GRAY_LO
  colorDown        = GRAY_LO
  colorActive      = GRAY_LO
  colorActiveHover = GRAY_LO
  colorDisabled    = GRAY_HI

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
                                state: WidgetState, first, last: bool,
                                x, y, w, h: float,
                                style: RadioButtonsStyle)

# {{{ DefaultRadioButtonDrawProc
let DefaultRadioButtonDrawProc: RadioButtonsDrawProc =
  proc (vg: NVGContext, buttonIdx: Natural, label: string,
        state: WidgetState, first, last: bool,
        x, y, w, h: float, style: RadioButtonsStyle) =

    alias(s, style)

    let (fillColor, strokeColor) =
      case state
      of wsNormal, wsDisabled:
        (s.buttonFillColor, s.buttonStrokeColor)
      of wsHover:
        (s.buttonFillColorHover, s.buttonStrokeColorHover)
      of wsDown:
        (s.buttonFillColorDown, s.buttonStrokeColorDown)
      of wsActive:
        (s.buttonFillColorActive, s.buttonStrokeColorActive)
      of wsActiveHover:
        (s.buttonFillColorActiveHover, s.buttonStrokeColorActiveHover)

    let
      sw = s.buttonStrokeWidth
      buttonW = w - s.buttonPadHoriz
      bx = round(x)
      bw = round(x + buttonW) - bx
      bh = h - s.buttonPadVert

    vg.setFont(s.label.fontSize)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)
    vg.beginPath()

    let cr = s.buttonCornerRadius
    if   first: vg.roundedRect(bx, y, bw, bh, cr, 0, 0, cr)
    elif last:  vg.roundedRect(bx, y, bw, bh, 0, cr, cr, 0)
    else:       vg.rect(bx, y, bw, bh)

    vg.fill()
    vg.stroke()

    vg.drawLabel(bx, y, bw, bh, label, state, s.label)

# }}}
# {{{ radioButtons()
proc radioButtons[T](
  id:               ItemId,
  x, y, w, h:       float,
  labels:           seq[string],
  activeButton_out: var T,
  tooltips:         seq[string] = @[],
  layout:           RadioButtonsLayout = RadioButtonsLayout(kind: rblHoriz),
  drawProc:         Option[RadioButtonsDrawProc] = RadioButtonsDrawProc.none,
  style:            RadioButtonsStyle = DefaultRadioButtonsStyle
) =

  var activeButton = activeButton_out

  assert activeButton.ord >= 0 and activeButton.ord <= labels.high
  assert tooltips.len == 0 or tooltips.len == labels.len

  alias(ui, g_uiState)
  alias(rs, ui.radioButtonState)

  let (x, y) = addDrawOffset(x, y)

  let numButtons = labels.len

  # Hit testing
  var hotButton = -1

  proc setHotAndActive() =
    setHot(id)
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)
      rs.activeItem = hotButton

  proc setHotButton(button: int) =
    if hasNoActiveItem() or (hasActiveItem() and button == rs.activeItem):
      hotButton = button

  case layout.kind
  of rblHoriz:
    let buttonW = w / numButtons.float
    let button = min(((ui.mx - x) / buttonW).int, numButtons-1)

    setHotButton(button)

    if isHit(x, y, w, h) and hotButton > -1: setHotAndActive()

  of rblGridHoriz:
    let
      bbWidth = layout.itemsPerRow * w
      numRows = ceil(numButtons.float / layout.itemsPerRow).Natural
      bbHeight = numRows * h
      row = ((ui.my - y) / h).int
      col = ((ui.mx - x) / w).int
      button = row * layout.itemsPerRow + col

    if row >= 0 and col >= 0 and button < numButtons:
      setHotButton(button)

    setHotButton(button)

    if isHit(x, y, bbWidth, bbHeight) and hotButton > -1: setHotAndActive()

  of rblGridVert:
    let
      bbHeight = layout.itemsPerColumn * h
      numCols = ceil(numButtons.float / layout.itemsPerColumn).Natural
      bbWidth = numCols * w
      row = ((ui.my - y) / h).int
      col = ((ui.mx - x) / w).int
      button = col * layout.itemsPerColumn + row

    if row >= 0 and col >= 0 and button < numButtons:
      setHotButton(button)

    if isHit(x, y, bbWidth, bbHeight) and hotButton > -1: setHotAndActive()

  # LMB released over active widget means it was clicked
  if not ui.mbLeftDown and isHot(id) and isActive(id) and
     rs.activeItem == hotButton:
    activeButton = T(hotButton)

  activeButton_out = activeButton

  # Draw radio buttons
  proc buttonDrawState(i: Natural): WidgetState =
    let state = if   isHot(id) and hasNoActiveItem(): wsHover
                elif isHot(id) and isActive(id): wsDown
                else: wsNormal

    if activeButton.ord == i:
      if hotButton == i and state == wsHover: wsActiveHover
      else: wsActive

    else:
      if hotButton == i:
        if   state == wsHover: wsHover
        elif state == wsDown:  wsDown
        else: wsNormal
      else:
        wsNormal


  addDrawLayer(ui.currentLayer, vg):
    var x = x
    var y = y
    let drawProc = if drawProc.isSome: drawProc.get
                   else: DefaultRadioButtonDrawProc

    case layout.kind
    of rblHoriz:
      let buttonW = w / numButtons.float
      for i, label in labels:
        let
          state = buttonDrawState(i)
          first = i == 0
          last = i == labels.len-1
          w = round(x + buttonW) - round(x)

        drawProc(vg, i, label, state, first, last,
                 round(x), y, w, h, style)
        x += buttonW

    of rblGridHoriz:
      let startX = x
      var itemsInRow = 0
      for i, label in labels:
        let state = buttonDrawState(i)
        drawProc(vg, i, label, state, first=false, last=false,
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
        let state = buttonDrawState(i)
        drawProc(vg, i, label, state, first=false, last=false,
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

# }}}

template radioButtons*[T](
  x, y, w, h:   float,
  labels:       seq[string],
  activeButton: var T,
  tooltips:     seq[string] = @[],
  layout:       RadioButtonsLayout = RadioButtonsLayout(kind: rblHoriz),
  drawProc:     Option[RadioButtonsDrawProc] = RadioButtonsDrawProc.none,
  style:        RadioButtonsStyle = DefaultRadioButtonsStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  radioButtons(id, x, y, w, h, labels, activeButton, tooltips,
               layout, drawProc, style)


template radioButtons*[T](
  labels:       seq[string],
  activeButton: var T,
  tooltips:     seq[string] = @[],
  layout:       RadioButtonsLayout = RadioButtonsLayout(kind: rblHoriz),
  drawProc:     Option[RadioButtonsDrawProc] = RadioButtonsDrawProc.none,
  style:        RadioButtonsStyle = DefaultRadioButtonsStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  radioButtons(id, x, y, w, h, labels, activeButton, tooltips,
               layout, drawProc, style)

# }}}
# {{{ DropDown

type DropDownStyle* = ref object
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
  label*:                     LabelStyle
  itemListAlign*:             HorizontalAlign
  itemListPadHoriz*:          float
  itemListPadVert*:           float
  itemListCornerRadius*:      float
  itemListStrokeWidth*:       float
  itemListStrokeColor*:       Color
  itemListFillColor*:         Color
  item*:                      LabelStyle
  itemBackgroundColorHover*:  Color
  shadow*:                    ShadowStyle

var DefaultDropDownStyle = DropDownStyle(
  buttonCornerRadius        : 5.0,
  buttonStrokeWidth         : 0.0,
  buttonStrokeColor         : black(),
  buttonStrokeColorHover    : black(),
  buttonStrokeColorDown     : black(),
  buttonStrokeColorDisabled : black(),
  buttonFillColor           : GRAY_MID,
  buttonFillColorHover      : GRAY_HI,
  buttonFillColorDown       : GRAY_MID,
  buttonFillColorDisabled   : GRAY_LO,
  label                     : getDefaultLabelStyle(),
  itemListAlign             : haCenter,
  itemListPadHoriz          : 7.0,
  itemListPadVert           : 7.0,
  itemListCornerRadius      : 5.0,
  itemListStrokeWidth       : 0.0,
  itemListStrokeColor       : black(),
  itemListFillColor         : GRAY_LO,
  item                      : getDefaultLabelStyle(),
  itemBackgroundColorHover  : HILITE,
  shadow                    : getDefaultShadowStyle()
)

with DefaultDropDownStyle:
  label.padHoriz    = 8.0
  label.color       = GRAY_LO
  label.colorHover  = GRAY_LO
  label.colorDown   = GRAY_LO # TODO

  item.padHoriz     = 0.0
  item.color        = GRAY_HI
  item.colorHover   = GRAY_LO

proc getDefaultDropDownStyle*(): DropDownStyle =
  DefaultDropDownStyle.deepCopy

proc setDefaultDropDownStyle*(style: DropDownStyle) =
  DefaultDropDownStyle = style.deepCopy

# {{{ dropDown()

proc dropDown[T](id:               ItemId,
                 x, y, w, h:       float,
                 items:            seq[string],
                 selectedItem_out: var T,
                 tooltip:          string,
                 disabled:         bool,
                 style:            DropDownStyle) =

  var selectedItem = selectedItem_out

  assert items.len > 0
  assert selectedItem.ord <= items.high

  alias(ui, g_uiState)
  alias(ds, ui.dropDownState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  var
    itemListX, itemListY, itemListW, itemListH: float
    hoverItem = -1

  let
    numItems = items.len
    itemHeight = h  # TODO just temporarily

  proc closeDropDown() =
    ds.state = dsClosed
    ds.activeItem = 0
    ui.focusCaptured = false

  if ds.state == dsClosed:
    if isHit(x, y, w, h):
      setHot(id)
      if not disabled and ui.mbLeftDown and hasNoActiveItem():
        setActive(id)
        ds.state = dsOpenLMBPressed
        ds.activeItem = id
        ui.focusCaptured = true
        ui.t0 = getTime()

  # We 'fall through' to the open state to avoid a 1-frame delay when clicking
  # the button
  if ds.activeItem == id and ds.state >= dsOpenLMBPressed:

    # Calculate the position of the box around the drop-down items
    var maxItemWidth = 0.0

    g_nvgContext.setFont(s.item.fontSize)

    for i in items:
      let tw = g_nvgContext.textWidth(i)
      maxItemWidth = max(tw, maxItemWidth)

    itemListW = max(maxItemWidth + s.itemListPadHoriz*2, w)
    itemListH = float(items.len) * itemHeight + s.itemListPadVert*2

    (itemListX, itemListY) = fitRectWithinWindow(itemListW, itemListH,
                                                 x, y, w, h,
                                                 s.itemListAlign)

    let (itemListX, itemListY, itemListW, itemListH) = snapToGrid(
      itemListX, itemListY, itemListW, itemListH, s.itemListStrokeWidth
    )

    # Hit testing
    let
      insideButton = mouseInside(x, y, w, h)
      insideItemList = mouseInside(itemListX, itemListY, itemListW, itemListH)

    if insideButton or insideItemList:
      setHot(id)
      setActive(id)
    else:
      closeDropDown()

    if insideItemList:
      hoverItem = min(
        ((ui.my - itemListY - s.itemListPadVert) / itemHeight).int,
        numItems-1
      )

    # LMB released inside the box selects the item under the cursor and closes
    # the dropDown
    if ds.state == dsOpenLMBPressed:
      if not ui.mbLeftDown:
        let dt = getTime() - ui.t0  # protection against fast click & drag
        if hoverItem >= 0 and dt > 0.1:
          selectedItem = T(hoverItem)
          closeDropDown()
        else:
          ds.state = dsOpen
    else:
      if ui.mbLeftDown:
        if hoverItem >= 0:
          selectedItem = (hoverItem)
          closeDropDown()
        elif insideButton:
          closeDropDown()

  selectedItem_out = selectedItem

  let state = if disabled: wsDisabled
              elif isHot(id) and hasNoActiveItem(): wsHover
              elif isHot(id) and isActive(id): wsDown
              else: wsNormal

  # Drop-down button
  addDrawLayer(ui.currentLayer, vg):
    let sw = s.buttonStrokeWidth
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let (fillColor, strokeColor, textColor) = case state
      of wsNormal, wsActive, wsActiveHover:
        (s.buttonFillColor, s.buttonStrokeColor, s.label.color)
      of wsHover:
        (s.buttonFillColorHover, s.buttonStrokeColorHover, s.label.colorHover)
      of wsDown:
        (s.buttonFillColorDown, s.buttonStrokeColorDown, s.label.colorDown)
      of wsDisabled:
        (s.buttonFillColorDisabled, s.buttonStrokeColorDisabled,
         s.label.colorDisabled)

    vg.fillColor(fillColor)
    vg.strokeColor(strokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.buttonCornerRadius)
    vg.fill()
    vg.stroke()

    let itemText = items[selectedItem]

    vg.drawLabel(x, y, w, h, itemText, state, s.label)

  # Drop-down items
  if isActive(id) and ds.state >= dsOpenLMBPressed:

    addDrawLayer(layerWidgetOverlay, vg):
      drawShadow(vg, itemListX, itemListY, itemListW, itemListH, s.shadow)

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
        var state = wsNormal
        if i == hoverItem:
          vg.beginPath()
          vg.rect(itemListX, iy, itemListW, h)
          vg.fillColor(s.itemBackgroundColorHover)
          vg.fill()
          state = wsHover

        vg.drawLabel(ix, iy, itemListW, h, item, state, s.item)

        iy += itemHeight

  if isHot(id):
    handleTooltip(id, tooltip)

# }}}

template dropDown*(
  x, y, w, h:   float,
  items:        seq[string],
  selectedItem: Natural,
  tooltip:      string = "",
  disabled:     bool = false,
  style:        DropDownStyle = DefaultDropDownStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  dropDown(id, x, y, w, h, items, selectedItem, tooltip, disabled, style)


template dropDown*(
  items:        seq[string],
  selectedItem: Natural,
  tooltip:      string = "",
  disabled:     bool = false,
  style:        DropDownStyle = DefaultDropDownStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  dropDown(id, a.x, a.y, a.nextItemWidth, a.nextItemHeight, items,
           selectedItem, tooltip, disabled, style)

  handleAutoLayout()

# }}}
# {{{ ScrollBar

type ScrollBarStyle* = ref object
  trackCornerRadius*:      float
  trackStrokeWidth*:       float
  trackStrokeColor*:       Color
  trackStrokeColorHover*:  Color
  trackStrokeColorDown*:   Color
  trackFillColor*:         Color
  trackFillColorHover*:    Color
  trackFillColorDown*:     Color
  thumbCornerRadius*:      float
  thumbPad*:               float
  thumbMinSize*:           float
  thumbStrokeWidth*:       float
  thumbStrokeColor*:       Color
  thumbStrokeColorHover*:  Color
  thumbStrokeColorDown*:   Color
  thumbFillColor*:         Color
  thumbFillColorHover*:    Color
  thumbFillColorDown*:     Color

var DefaultScrollBarStyle = ScrollBarStyle(
  trackCornerRadius      : 5.0,
  trackStrokeWidth       : 0.0,
  trackStrokeColor       : black(),
  trackStrokeColorHover  : black(),
  trackStrokeColorDown   : black(),
  trackFillColor         : GRAY_MID,
  trackFillColorHover    : GRAY_HI,
  trackFillColorDown     : GRAY_MID,
  thumbCornerRadius      : 5.0,
  thumbPad               : 3.0,
  thumbMinSize           : 10.0,
  thumbStrokeWidth       : 0.0,
  thumbStrokeColor       : black(),
  thumbStrokeColorHover  : black(),
  thumbStrokeColorDown   : black(),
  thumbFillColor         : GRAY_LO,
  thumbFillColorHover    : GRAY_LOHI,
  thumbFillColorDown     : HILITE,
)

proc getDefaultScrollBarStyle*(): ScrollBarStyle =
  DefaultScrollBarStyle.deepCopy

proc setDefaultScrollBarStyle*(style: ScrollBarStyle) =
  DefaultScrollBarStyle = style.deepCopy

# {{{ horizScrollBar

# Must be kept in sync with vertScrollBar!
proc horizScrollBar(id:         ItemId,
                    x, y, w, h: float,
                    startVal:   float,
                    endVal:     float,
                    value_out:  var float,
                    tooltip:    string = "",
                    thumbSize:  float = -1.0,
                    clickStep:  float = -1.0,
                    style:      ScrollBarStyle) =

  # TODO only for debugging, too fragile
#  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
#         (endVal   < startVal and value >= endVal   and value <= startVal)

#  assert thumbSize < 0.0 or thumbSize < abs(startVal - endVal)
#  assert clickStep < 0.0 or clickStep < abs(startVal - endVal)

  var value = value_out

  alias(ui, g_uiState)
  alias(sb, ui.scrollBarState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  # Calculate current thumb position
  let
    thumbSize = if thumbSize < 0: 0.000001 else: thumbSize

    thumbW = max((w - s.thumbPad*2) / (abs(startVal - endVal) / thumbSize),
                 s.thumbMinSize)

    thumbH = h - s.thumbPad*2
    thumbMinX = x + s.thumbPad
    thumbMaxX = x + w - s.thumbPad - thumbW

  proc calcThumbX(val: float): float =
    let t = invLerp(startVal, endVal, val)
    lerp(thumbMinX, thumbMaxX, t)

  let thumbX = calcThumbX(value)

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  let insideThumb = mouseInside(thumbX, y, thumbW, h)

  # New thumb position & value calculation
  var
    newThumbX = thumbX
    newValue = value

  proc calcNewValue(newThumbX: float): float =
    let t = invLerp(thumbMinX, thumbMaxX, newThumbX)
    lerp(startVal, endVal, t)

  proc calcNewValueTrackClick(newValue: float): float =
    let clickStep = if clickStep < 0: abs(startVal - endVal) * 0.1
                    else: clickStep

    let (s, e) = if startVal < endVal: (startVal, endVal)
                 else: (endVal, startVal)
    # TODO newValue is captured, isn't this a bug?
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
        ui.widgetMouseDrag = true
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
        let dx = ui.dx - ui.x0

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        ui.x0 = clamp(ui.dx, thumbMinX, thumbMaxX + thumbW)

    of sbsDragHidden:
      # TODO not needed with widgetMouseDrag
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
#      setHot(id)

      if shiftDown():
        let d = if altDown(): ScrollBarUltraFineDragDivisor
                else:         ScrollBarFineDragDivisor
        let dx = (ui.dx - ui.x0) / d

        newThumbX = clamp(thumbX + dx, thumbMinX, thumbMaxX)
        newValue = calcNewValue(newThumbX)

        ui.x0 = ui.dx
        ui.dragX = newThumbX + thumbW*0.5
        ui.dragY = -1.0
      else:
        sb.state = sbsDragNormal
        showCursor()
        setCursorPosX(ui.dragX)
        ui.dx = ui.dragX
        ui.x0 = ui.dragX

    of sbsTrackClickFirst:
      newValue = calcNewValueTrackClick(newValue)
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
          newValue = calcNewValueTrackClick(newValue)
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

  value_out = newValue

  # Draw scrollbar
  addDrawLayer(ui.currentLayer, vg):
    let (bx, by, bw, bh) = (x, y, w, h)

    let state = if   isHot(id) and hasNoActiveItem(): wsHover
                elif isActive(id): wsDown
                else: wsNormal

    var sw = s.trackStrokeWidth
    var (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let (trackFillColor, trackStrokeColor,
         thumbFillColor, thumbStrokeColor) =
      case state
      of wsHover:
        (s.trackFillColorHover, s.trackStrokeColorHover,
         s.thumbFillColorHover, s.thumbStrokeColorHover)
      of wsDown:
        (s.trackFillColorDown, s.trackStrokeColorDown,
         s.thumbFillColorDown, s.thumbStrokeColorDown)
      else:
        (s.trackFillColor, s.trackStrokeColor,
         s.thumbFillColor, s.thumbStrokeColor)

    # Draw track
    vg.fillColor(trackFillColor)
    vg.strokeColor(trackStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.trackCornerRadius)
    vg.fill()
    vg.stroke()

    # Draw thumb
    sw = s.thumbStrokeWidth
    (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    vg.fillColor(thumbFillColor)
    vg.strokeColor(thumbStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(newThumbX, y + s.thumbPad, thumbW, thumbH,
                   s.thumbCornerRadius)
    vg.fill()
    vg.stroke()

  if isHot(id):
    handleTooltip(id, tooltip)

# }}}
# {{{ vertScrollBar

# Must be kept in sync with horizScrollBar!
proc vertScrollBar(id:         ItemId,
                   x, y, w, h: float,
                   startVal:   float,
                   endVal:     float,
                   value_out:  var float,
                   tooltip:    string = "",
                   thumbSize:  float = -1.0,
                   clickStep:  float = -1.0,
                   style:      ScrollBarStyle) =

  # TODO only for debugging, too fragile
#  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
#         (endVal   < startVal and value >= endVal   and value <= startVal)

#  assert thumbSize < 0.0 or thumbSize < abs(startVal - endVal)
#  assert clickStep < 0.0 or clickStep < abs(startVal - endVal)

  var value = value_out

  alias(ui, g_uiState)
  alias(sb, ui.scrollBarState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  # Calculate current thumb position
  let
    thumbSize = if thumbSize < 0: 0.000001 else: thumbSize
    thumbW = w - s.thumbPad*2

    thumbH = max((h - s.thumbPad*2) / (abs(startVal - endVal) / thumbSize),
                 s.thumbMinSize)

    thumbMinY = y + s.thumbPad
    thumbMaxY = y + h - s.thumbPad - thumbH

  proc calcThumbY(value: float): float =
    let t = invLerp(startVal, endVal, value)
    lerp(thumbMinY, thumbMaxY, t)

  let thumbY = calcThumbY(value)

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and hasNoActiveItem():
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
        ui.widgetMouseDrag = true
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
        let dy = ui.dy - ui.y0

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        ui.y0 = clamp(ui.dy, thumbMinY, thumbMaxY + thumbH)

    of sbsDragHidden:
      # Technically, the cursor can move outside the widget when it's disabled
      # in "drag hidden" mode, and then it will cease to be "hot". But in
      # order to not break the tooltip processing logic, we're making here
      # sure the widget is always hot in "drag hidden" mode.
      setHot(id)

      if shiftDown():
        let d = if altDown(): ScrollBarUltraFineDragDivisor
                else:         ScrollBarFineDragDivisor
        let dy = (ui.dy - ui.y0) / d

        newThumbY = clamp(thumbY + dy, thumbMinY, thumbMaxY)
        newValue = calcNewValue(newThumbY)

        ui.y0 = ui.dy
        ui.dragX = -1.0
        ui.dragY = newThumbY + thumbH*0.5
      else:
        sb.state = sbsDragNormal
        showCursor()
        setCursorPosY(ui.dragY)
        ui.dy = ui.dragY
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

  value_out = newValue

  # Draw scrollbar
  addDrawLayer(ui.currentLayer, vg):
    let value = newValue

    let (bx, by, bw, bh) = (x, y, w, h)

    let state = if   isHot(id) and hasNoActiveItem(): wsHover
                elif isActive(id): wsDown
                else: wsNormal

    # Draw track
    var sw = s.trackStrokeWidth
    var (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let (trackFillColor, trackStrokeColor,
         thumbFillColor, thumbStrokeColor) =
      case state
      of wsHover:
        (s.trackFillColorHover, s.trackStrokeColorHover,
         s.thumbFillColorHover, s.thumbStrokeColorHover)
      of wsDown:
        (s.trackFillColorDown, s.trackStrokeColorDown,
         s.thumbFillColorDown, s.thumbStrokeColorDown)
      else:
        (s.trackFillColor, s.trackStrokeColor,
         s.thumbFillColor, s.thumbStrokeColor)

    vg.fillColor(trackFillColor)
    vg.strokeColor(trackStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.trackCornerRadius)
    vg.fill()
    vg.stroke()

    # Draw thumb
    sw = s.thumbStrokeWidth
    (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    vg.fillColor(thumbFillColor)
    vg.strokeColor(thumbStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x + s.thumbPad, newThumbY, thumbW, thumbH,
                   s.thumbCornerRadius)
    vg.fill()
    vg.stroke()

  if isHot(id):
    handleTooltip(id, tooltip)

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

    ui.widgetMouseDrag = false

# }}}

template horizScrollBar*(x, y, w, h: float,
                         startVal:  float,
                         endVal:    float,
                         value:     var float,
                         tooltip:   string = "",
                         thumbSize: float = -1.0,
                         clickStep: float = -1.0,
                         style:     ScrollBarStyle = DefaultScrollBarStyle) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  horizScrollBar(id, x, y, w, h, startVal, endVal, value, tooltip, thumbSize,
                 clickStep, style)


template vertScrollBar*(x, y, w, h: float,
                        startVal:   float,
                        endVal:     float,
                        value:      var float,
                        tooltip:    string = "",
                        thumbSize:  float = -1.0,
                        clickStep:  float = -1.0,
                        style:      ScrollBarStyle = DefaultScrollBarStyle) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  vertScrollBar(id, x, y, w, h, startVal, endVal, value, tooltip, thumbSize,
                clickStep, style)

# }}}

# {{{ Text functions

type TextEditResult = object
  text:      string
  cursorPos: Natural
  selection: TextSelection

const NoSelection = TextSelection(startPos: -1, endPos: 0)

# {{{ hasSelection()
proc hasSelection(sel: TextSelection): bool =
  sel.startPos > -1 and sel.startPos != sel.endPos

# }}}
# {{{ normaliseSelection()
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

# }}}
# {{{ updateSelection()
proc updateSelection(sel: TextSelection,
                     cursorPos, newCursorPos: Natural): TextSelection =
  var sel = sel
  if sel.startPos == -1:
    sel.startPos = cursorPos
    sel.endPos   = cursorPos
  sel.endPos = newCursorPos
  result = sel

# }}}
# {{{ isAlphanumeric()
proc isAlphanumeric(r: Rune): bool =
  if r.isAlpha: return true
  let s = $r
  if s[0] == '_' or s[0].isDigit: return true

# }}}
# {{{ findNextWordEnd()
proc findNextWordEnd(text: string, cursorPos: Natural): Natural =
  var p = cursorPos
  while p < text.runeLen and     text.runeAtPos(p).isAlphanumeric: inc(p)
  while p < text.runeLen and not text.runeAtPos(p).isAlphanumeric: inc(p)
  result = p

# }}}
# {{{ findPrevWordStart()
proc findPrevWordStart(text: string, cursorPos: Natural): Natural =
  var p = cursorPos
  while p > 0 and not text.runeAtPos(p-1).isAlphanumeric: dec(p)
  while p > 0 and     text.runeAtPos(p-1).isAlphanumeric: dec(p)
  result = p

# }}}
# {{{ drawCursor()
proc drawCursor(vg: NVGContext, x, y1, y2: float, color: Color, width: float) =
  vg.beginPath()
  vg.strokeColor(color)
  vg.strokeWidth(width)
  vg.moveTo(x+0.5, y1)
  vg.lineTo(x+0.5, y2)
  vg.stroke()

# }}}
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
    try:
      let toInsert = fromClipboard()
      res = insertString(text, cursorPos, selection, toInsert)
    except GLFWError:
      # attempting to retrieve non-text data raises an exception
      discard

  else:
    eventHandled = false

  result = if eventHandled: res.some else: TextEditResult.none

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

  # TODO use labelstyle?
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
  bgCornerRadius      : 5.0,
  bgStrokeWidth       : 0.0, # TODO
  bgStrokeColor       : black(),
  bgStrokeColorHover  : black(),
  bgStrokeColorActive : black(),
  bgFillColor         : GRAY_MID,
  bgFillColorHover    : GRAY_HI,
  bgFillColorActive   : GRAY_LO,

  # TODO use labelstyle?
  textPadHoriz        : 8.0,
  textPadVert         : 2.0,
  textFontSize        : 14.0,
  textFontFace        : "sans-bold",
  textColor           : GRAY_LO,
  textColorHover      : GRAY_LO, # TODO
  textColorActive     : GRAY_HI,

  cursorColor         : HILITE,
  cursorWidth         : 1.0,
  selectionColor      : rgb(0.5, 0.15, 0.15)
)

proc getDefaultTextFieldStyle*(): TextFieldStyle =
  DefaultTextFieldStyle.deepCopy

proc setDefaultTextFieldStyle*(style: TextFieldStyle) =
  DefaultTextFieldStyle = style.deepCopy

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

# {{{ textFieldEnterEditMode()
proc textFieldEnterEditMode(id: ItemId, text: string, startX: float) =
  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)

  setActive(id)
  # TODO clear at the end of each frame?
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

# }}}
# {{{ textField()
proc textField(
  id:         ItemId,
  x, y, w, h: float,
  text_out:   var string,
  tooltip:    string = "",
  activate:   bool = false,
  drawWidget: bool = true,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
) =

  const MaxTextLen = 5000

  var text = text_out

  assert text.runeLen <= MaxTextLen

  alias(ui, g_uiState)
  alias(tf, ui.textFieldState)
  alias(s, style)

  let (x, y) = addDrawOffset(x, y)

  # The text is displayed within this rectangle (used for drawing later)
  let
    textBoxX = x + s.textPadHoriz
    textBoxW = w - s.textPadHoriz*2
    textBoxY = y
    textBoxH = h

  var glyphs: array[MaxTextLen, GlyphPosition]

  var tabActivate = false

  if not ui.focusCaptured and tf.state == tfsDefault:
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
      if (ui.mbLeftDown and hasNoActiveItem()) or activate or tabActivate:
        textFieldEnterEditMode(id, text, textBoxX)
        tf.state = tfsEditLMBPressed


  proc setFont() =
    g_nvgContext.setFont(s.textFontSize, name=s.textFontFace)

  proc calcGlyphPos() =
    setFont()
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
    # TODO stripping should be optional
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

      setEventHandled()

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

        elif sc in shortcuts[tesNextTextField]:
          text = enforceConstraint(text, tf.originalText)
          exitEditMode()
          tf.activateNext = true

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


  text_out = text

  let editing = tf.activeItem == id

  addDrawLayer(ui.currentLayer, vg):
    vg.save()

    let state = if isHot(id) and hasNoActiveItem(): wsHover
      elif editing: wsActive
      else: wsNormal

    let (fillColor, strokeColor) = case state
      of wsHover:  (s.bgFillColorHover,  s.bgStrokeColorHover)
      of wsActive: (s.bgFillColorActive, s.bgStrokeColorActive)
      else:        (s.bgFillColor,       s.bgStrokeColor)

    var
      textX = textBoxX
      textY = y + h*TextVertAlignFactor

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
    let xPad = 3
    vg.intersectScissor(textBoxX-xPad, textBoxY, textBoxW+xPad, textBoxH)

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
        let selYPad = 2
        vg.rect(selStartX, y+selYPad, selEndX - selStartX, h-selYPad*2)
        vg.fillColor(s.selectionColor)
        vg.fill()

      # Draw cursor
      let cursorX = getCursorXPos()
      drawCursor(vg, cursorX, y+2, y+h-2, s.cursorColor, s.cursorWidth)

      text = text.runeSubStr(tf.displayStartPos)

    # Draw text
    # TODO text color hover
    let textColor = if editing: s.textColorActive else: s.textColor

    setFont()
    vg.fillColor(textColor)
    discard vg.text(textX, textY, text)

    vg.restore()

  if isHot(id):
    handleTooltip(id, tooltip)

  # TODO a bit hacky, why is it needed?
  if activate or tabActivate:
    ui.tooltipState.state = tsOff

  tf.prevItem = id

# }}}

template rawTextField*(
  x, y, w, h: float,
  text:       var string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, text, tooltip, activate, drawWidget = false,
            constraint, style)


template textField*(
  x, y, w, h: float,
  text:       var string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textField(id, x, y, w, h, text, tooltip, activate, drawWidget = true,
            constraint, style)


template textField*(
  text:       var string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextFieldConstraint] = TextFieldConstraint.none,
  style:      TextFieldStyle = DefaultTextFieldStyle
) =

  alias(ui, g_uiState)
  alias(a, ui.autoLayoutState)

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textField(id, a.x, a.y, a.nextItemWidth, a.nextItemHeight, text,
            tooltip, activate, drawWidget = true, constraint, style)

  handleAutoLayout()

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

  # TODO use labelStyle?
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
  bgCornerRadius      : 5.0,
  bgStrokeWidth       : 0.0, # TODO
  bgStrokeColor       : black(),
  bgStrokeColorHover  : black(),
  bgStrokeColorActive : black(),
  bgFillColor         : GRAY_MID,
  bgFillColorHover    : GRAY_HI,
  bgFillColorActive   : GRAY_LO,

  # TODO use labelStyle?
  textPadHoriz       : 8.0,
  textPadVert        : 2.0,
  textFontSize       : 14.0,
  textFontFace       : "sans-bold", # TODO
  textLineHeight     : 1.4,
  textColor          : GRAY_LO,
  textColorHover     : GRAY_LO, # TODO
  textColorActive    : GRAY_HI,

  cursorColor        : HILITE,
  cursorWidth        : 1.0,
  selectionColor     : rgb(0.5, 0.15, 0.15)
)

proc getDefaultTextAreaStyle*(): TextAreaStyle =
  DefaultTextAreaStyle.deepCopy

proc setDefaultTextAreaStyle*(style: TextAreaStyle) =
  DefaultTextAreaStyle = style.deepCopy

type
  TextAreaConstraint* = object
    minLen*: Natural
    maxLen*: int

var DefaultTextAreaScrollBarStyle = getDefaultScrollBarStyle()

with DefaultTextAreaScrollBarStyle:
  trackCornerRadius   = 3.0
  trackFillColor      = gray(0, 0)
  trackFillColorHover = gray(0, 0)
  trackFillColorDown  = gray(0, 0)
  thumbCornerRadius   = 3.0
  thumbFillColor      = gray(0, 0.4)
  thumbFillColorHover = gray(0, 0.43)
  thumbFillColorDown  = gray(0, 0.35)

var DefaultTextAreaScrollBarStyle_EditMode = DefaultTextAreaScrollBarStyle.deepCopy()

# {{{ textArea()
proc textArea(
  id:         ItemId,
  x, y, w, h: float,
  text_out:   var string,
  tooltip:    string = "",
  activate:   bool = false,
  drawWidget: bool = false,
  constraint: Option[TextAreaConstraint] = TextAreaConstraint.none,
  style:      TextAreaStyle = DefaultTextAreaStyle
) =

  alias(vg, g_nvgContext)
  alias(ui, g_uiState)
  alias(ta, ui.textAreaState)
  alias(s, style)

  var text = text_out

  const MaxLineLen = 1000
  assert text.runeLen <= MaxLineLen

  let TextRightPad = s.textFontSize

  # TODO style param
  let ScrollBarWidth = 12.0

  let (x, y) = addDrawOffset(x, y)

  # The text is displayed within this rectangle (used for drawing later)
  let
    textBoxX = x + s.textPadHoriz
    textBoxW = w - s.textPadHoriz - ScrollBarWidth
    textBoxY = y + s.textPadVert
    textBoxH = h - s.textPadVert*2

  proc setFont() =
    vg.setFont(s.textFontSize, name=s.textFontFace, vertAlign=vaBaseline)

  setFont()
  var (_, _, lineHeight) = vg.textMetrics()
  lineHeight = floor(lineHeight * s.textLineHeight)

  var maxDisplayRows = (textBoxH / lineHeight).int

  var glyphs: array[MaxLineLen, GlyphPosition]


  proc enterEditMode(id: ItemId, text: string, startX: float) =
    setActive(id)
    # TODO clear at the end of each frame?
    clearCharBuf()
    clearEventBuf()

    ta.state = tasEdit
    ta.activeItem = id
    ta.cursorPos = text.runeLen
    ta.originalText = text
    ta.selection.startPos = -1
    ta.selection.endPos = 0

    ui.focusCaptured = true


  proc exitEditMode() =
    clearEventBuf()
    clearCharBuf()

    ta.state = tasDefault
    ta.activeItem = 0
    ta.cursorPos = 0
    ta.displayStartRow = 0
    ta.displayStartY = 0
    ta.selection = NoSelection
    ta.originalText = ""
    ta.lastActiveItem = id

    ui.focusCaptured = false
    setCursorShape(csArrow)


  var tabActivate = false

  if not ui.focusCaptured and ta.state == tasDefault:
    if ta.activateNext and ta.lastActiveItem == ta.prevItem and
       id != ta.prevItem:  # exit editing textarea if there's just one
      ta.activateNext = false
      tabActivate = true

    elif ta.activatePrev and id == ta.itemToActivate and
         id != ta.prevItem:  # exit editing textarea if there's just one
      ta.activatePrev = false
      tabActivate = true

    # Hit testing
    if isHit(x, y, w - ScrollBarWidth, h) or activate or tabActivate:
      setHot(id)
      if (ui.mbLeftDown and hasNoActiveItem()) or activate or tabActivate:
        enterEditMode(id, text, textBoxX)
        ta.state = tasEditEntered


  proc calcGlypPosForRow(x, y: float, row: TextRow): Natural =
    setFont()
    return vg.textGlyphPositions(x, y, text,
                                 row.startBytePos, row.endBytePos, glyphs)

  # TODO suboptimal to do this on every frame?
  var rows = textBreakLines(text, textBoxW)

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
      if ui.mbLeftDown and not mouseInside(x, y, w, h):
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

      setEventHandled()

      # Only use the stored X position for consecutive prev/next line
      # actions
      if not (sc in shortcuts[tesCursorToPreviousLine] or
              sc in shortcuts[tesCursorToNextLine] or
              sc in shortcuts[tesCursorPageUp] or
              sc in shortcuts[tesCursorPageDown] or

              sc in shortcuts[tesSelectionToPreviousLine] or
              sc in shortcuts[tesSelectionToNextLine] or
              sc in shortcuts[tesSelectionPageUp] or
              sc in shortcuts[tesSelectionPageDown]):

        ta.lastCursorXPos = float.none

      let res = handleCommonTextEditingShortcuts(sc, text, ta.cursorPos,
                                                 ta.selection)

      if res.isSome:
        text = res.get.text
        ta.cursorPos = res.get.cursorPos
        ta.selection = res.get.selection

      else:
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

        proc findClosestCursorPos(row: TextRow, cx: float): Natural =
          result = if row.nextRowPos == -1: row.endPos+1 else: row.endPos
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

        # Editing
        if sc in shortcuts[tesInsertNewline]:
          text = text.runeSubstr(0, ta.cursorPos) & "\n" &
                 text.runeSubstr(ta.cursorPos)
          inc(ta.cursorPos)

        # Cursor movement
        elif sc in shortcuts[tesCursorToLineStart]:
          ta.cursorPos = currRow.startPos
          ta.selection = NoSelection

        elif sc in shortcuts[tesCursorToLineEnd]:
          ta.cursorPos = if currRow.nextRowPos > 0: currRow.endPos
                         else: text.runeLen
          ta.selection = NoSelection

        # Selection
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

        # Cursor movement & selection
        elif sc in shortcuts[tesCursorToPreviousLine] or
             sc in shortcuts[tesCursorPageUp] or
             sc in shortcuts[tesSelectionToPreviousLine] or
             sc in shortcuts[tesSelectionPageUp]:

          if currRowIdx > 0:
            setLastCursorXPos()

            let targetRowIdx = if sc in shortcuts[tesCursorPageUp] or
                                  sc in shortcuts[tesSelectionPageUp]:
              max(currRowIdx.int - maxDisplayRows, 0)
            else: currRowIdx-1

            let targetRow = rows[targetRowIdx]
            discard calcGlypPosForRow(textBoxX, 0, targetRow)
            let newCursorPos = findClosestCursorPos(targetRow,
                                                    ta.lastCursorXPos.get)

            if sc in shortcuts[tesSelectionToPreviousLine] or
               sc in shortcuts[tesSelectionPageUp]:
              ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                             newCursorPos)
              ta.cursorPos = newCursorPos
            else:
              ta.cursorPos = newCursorPos
              ta.selection = NoSelection


        elif sc in shortcuts[tesCursorToNextLine] or
             sc in shortcuts[tesCursorPageDown] or
             sc in shortcuts[tesSelectionToNextLine] or
             sc in shortcuts[tesSelectionPageDown]:

          if currRowIdx < rows.high:
            setLastCursorXPos()

            let targetRowIdx = if sc in shortcuts[tesCursorPageDown] or
                                  sc in shortcuts[tesSelectionPageDown]:
              min(currRowIdx + maxDisplayRows, rows.high)
            else: currRowIdx+1

            let targetRow = rows[targetRowIdx]
            discard calcGlypPosForRow(textBoxX, 0, targetRow)

            let newCursorPos = if targetRow.startPos == text.runeLen:
                                 targetRow.startPos
                               else:
                                 findClosestCursorPos(targetRow,
                                                      ta.lastCursorXPos.get)

            if sc in shortcuts[tesSelectionToNextLine] or
               sc in shortcuts[tesSelectionPageDown]:
              ta.selection = updateSelection(ta.selection, ta.cursorPos,
                                             newCursorPos)
              ta.cursorPos = newCursorPos
            else:
              ta.cursorPos = newCursorPos
              ta.selection = NoSelection

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

        elif sc in shortcuts[tesNextTextField]:
          exitEditMode()
          ta.activateNext = true

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

    # Recalculate lines after an edit -- necessary for the scrollbar to work
    # correctly
    rows = textBreakLines(text, textBoxW)


  let editing = ta.activeItem == id

  # Update state vars
  maxDisplayRows = (textBoxH / lineHeight).int

  var currRow = rows.high
  for rowIdx, row in rows.pairs():
    if ta.cursorPos >= row.startPos and
       ta.cursorPos <= row.endPos:
      currRow = rowIdx
      break

  if editing:
    if currRow < ta.displayStartRow:
      ta.displayStartRow = currRow.float
    else:
      let displayEndRow = min(ta.displayStartRow.int + maxDisplayRows-1,
                              rows.high)
      if currRow > displayEndRow:
        ta.displayStartRow = max(currRow - (maxDisplayRows-1), 0).float

    let maxDisplayStartRow = max(rows.len.int - maxDisplayRows, 0)
    ta.displayStartRow = min(ta.displayStartRow.int, maxDisplayStartRow).float

  # Scrollbar
  let sbStyle = if editing: DefaultTextAreaScrollBarStyle_EditMode
                else:       DefaultTextAreaScrollBarStyle

  let endVal = max(rows.len.float - maxDisplayRows, ta.displayStartRow)
  let thumbSize = maxDisplayRows.float *
                  ((rows.len.float - maxDisplayRows) / rows.len)

  text_out = text


  addDrawLayer(ui.currentLayer, vg):
    vg.save()

    let state = if isHot(id) and hasNoActiveItem(): wsHover
      elif editing: wsActive
      else: wsNormal

    let (fillColor, strokeColor) = case state
      of wsHover:  (s.bgFillColorHover,  s.bgStrokeColorHover)
      of wsActive: (s.bgFillColorActive, s.bgStrokeColorActive)
      else:        (s.bgFillColor,       s.bgStrokeColor)

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

    setFont()
    let rows = textBreakLines(text, textBoxW)
    let maxDisplayRows = (textBoxH / lineHeight).int

    let sel = normaliseSelection(ta.selection)

    var
      textX = textBoxX
      # TODO make these config params?
      textY = floor(textBoxY + lineHeight * 1.1)
      cursorYAdjust = floor(lineHeight*0.77)
      numGlyphs: Natural

    let displayEndRow = min(ta.displayStartRow.int + maxDisplayRows-1, rows.high)

    for rowIdx in ta.displayStartRow.int..displayEndRow:
      let row = rows[rowIdx]
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
            if sel.endPos-1 >= row.endPos:
              textX + textBoxW
            elif sel.endPos-1 >= row.startPos and
                 sel.endPos-1 < row.endPos:
              glyphs[sel.endPos-1 - row.startPos].maxX
            else: -1

          if selStartX >= 0 and selEndX >= 0:
            vg.beginPath()
            vg.rect(selStartX, textY - cursorYAdjust, selEndX - selStartX,
                    lineHeight)
            vg.fillColor(s.selectionColor)
            vg.fill()

      # Draw text
      let textColor = if editing: s.textColorActive else: s.textColor
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


  let sbId = hashId(lastIdString() & ":scrollBar")

  # TODO offset
  vertScrollBar(
    sbId,
    x+w - ScrollBarWidth, y,
    ScrollBarWidth, h,
    startVal=0, endVal=endVal,
    ta.displayStartRow,
    thumbSize=thumbSize, clickStep=2, style=sbStyle)


  if isHot(id):
    handleTooltip(id, tooltip)

  # TODO a bit hacky, why is it needed?
  if activate or tabActivate:
    ui.tooltipState.state = tsOff

  ta.prevItem = id

# }}}

template textArea*(
  x, y, w, h: float,
  text:       var string,
  tooltip:    string = "",
  activate:   bool = false,
  constraint: Option[TextAreaConstraint] = TextAreaConstraint.none,
  style:      TextAreaStyle = DefaultTextAreaStyle
) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  textArea(id, x, y, w, h, text, tooltip, activate, drawWidget = true,
           constraint, style)

# }}}

# {{{ Slider

type SliderStyle* = ref object
  trackCornerRadius*:     float
  trackPad:               float
  trackStrokeWidth*:      float
  trackStrokeColor*:      Color
  trackStrokeColorHover*: Color
  trackStrokeColorDown*:  Color
  trackFillColor*:        Color
  trackFillColorHover*:   Color
  trackFillColorDown*:    Color
  valuePrecision:         Natural
  valueCornerRadius*:     float
  sliderColor*:           Color
  sliderColorHover*:      Color
  sliderColorDown*:       Color
  label*:                 LabelStyle
  value*:                 LabelStyle
  cursorFollowsValue*:    bool

var DefaultSliderStyle = SliderStyle(
  trackCornerRadius     : 10.0,
  trackPad              : 3.0,
  trackStrokeWidth      : 0.0,
  trackStrokeColor      : black(),
  trackStrokeColorHover : black(),
  trackStrokeColorDown  : black(),
  trackFillColor        : GRAY_MID,
  trackFillColorHover   : GRAY_HI,
  trackFillColorDown    : GRAY_MID,
  valuePrecision        : 3,
  valueCornerRadius     : 8.0,
  sliderColor           : GRAY_LO,
  sliderColorHover      : GRAY_LO,
  sliderColorDown       : GRAY_LO,
  label                 : getDefaultLabelStyle(),
  value                 : getDefaultLabelStyle(),
  cursorFollowsValue    : true
)

with DefaultSliderStyle:
  label.padHoriz    = 8.0
  label.align       = haLeft
  label.color       = white()
  label.colorHover  = white()
  label.colorDown   = white()

  label.padHoriz    = 8.0
  value.align       = haCenter
  value.color       = white()
  value.colorHover  = white()
  value.colorDown   = white()

proc getDefaultSliderStyle*(): SliderStyle =
  DefaultSliderStyle.deepCopy

proc setDefaultSliderStyle*(style: SliderStyle) =
  DefaultSliderStyle = style.deepCopy

# {{{ horizSlider
proc horizSlider(id:         ItemId,
                 x, y, w, h: float,
                 startVal:   float,
                 endVal:     float,
                 value_out:  var float,
                 tooltip:    string = "",
                 label:      string = "",
                 style:      SliderStyle = DefaultSliderStyle,
                 grouping:   WidgetGrouping = wgNone) =

  var value = value_out

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  alias(ui, g_uiState)
  alias(ss, ui.sliderState)
  alias(s, style)

  let (ox, oy) = (x, y)
  let (x, y) = addDrawOffset(x, y)

  let
    posMinX = x + s.trackPad
    posMaxX = x + w - s.trackPad

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
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  # New position & value calculation
  var newPosX = posX

  if isActive(id):
    case ss.state:
    of ssDefault:
      ui.x0 = ui.mx
      ui.dragX = ui.mx
      ui.dragY = -1.0
      ui.widgetMouseDrag = true
      ss.state = ssDragHidden
      ss.cursorMoved = false
      disableCursor()

    of ssDragHidden:
      if ui.dragX != ui.dx:
        ss.cursorMoved = true

      if not ui.mbLeftDown and not ss.cursorMoved:
        ss.state = ssEditValue
        ss.valueText = fmt"{value:.6f}"
        trimZeros(ss.valueText)

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

        let dx = (ui.dx - ui.x0) / d

        newPosX = clamp(posX + dx, posMinX, posMaxX)
        let t = invLerp(posMinX, posMaxX, newPosX)
        value = lerp(startVal, endVal, t)
        ui.x0 = ui.dx

        ss.cursorPosX = if s.cursorFollowsValue: newPosX
                        else: ui.dragX

    of ssEditValue:
      discard


  value_out = value

  # Draw slider
  addDrawLayer(ui.currentLayer, vg):
    let state = if isHot(id) and hasNoActiveItem(): wsHover
                elif isActive(id): wsDown
                else: wsNormal

    var sw = s.trackStrokeWidth
    var (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let (trackFillColor, trackStrokeColor,
         sliderColor, labelColor, valueColor) =
      case state
      of wsHover:
        (s.trackFillColorHover, s.trackStrokeColorHover,
         s.sliderColorHover, s.label.colorHover, s.value.colorHover)
      of wsDown:
        (s.trackFillColorDown, s.trackStrokeColorDown,
         s.sliderColorDown, s.label.colorDown, s.value.colorDown)
      else:
        (s.trackFillColor, s.trackStrokeColor,
         s.sliderColor, s.label.color, s.value.color)

    # Draw track background
    proc drawTrackShape() =
      let cr = s.trackCornerRadius
      case grouping
      of wgNone:   vg.roundedRect(x, y, w, h, cr)
      of wgStart:  vg.roundedRect(x, y, w, h, cr, cr, 0, 0)
      of wgMiddle: vg.rect(x, y, w, h)
      of wgEnd:    vg.roundedRect(x, y, w, h, 0, 0, cr, cr)

    vg.fillColor(trackFillColor)

    vg.beginPath()
    drawTrackShape()
    vg.fill()

    # Draw slider bar
    if not (ss.editModeItem == id and ss.state == ssEditValue):
      let
        vx = x + s.trackPad
        vy = y + s.trackPad
        vw = w - s.trackPad*2
        vh = h - s.trackPad*2
        cr = s.valueCornerRadius
        # TODO hacky
        clipW = (newPosX - x - s.trackPad).int +
                (if sw mod 2 == 1: 0.5 else: 0)

      vg.fillColor(sliderColor)
      vg.beginPath()

      case grouping
      of wgNone:
        vg.rightClippedRoundedRect(vx, vy, vw, vh, cr, clipW, wgNone)
      of wgStart:
        vg.rightClippedRoundedRect(vx, vy, vw, vh, cr, clipW, wgStart)
      of wgMiddle:
        vg.rightClippedRoundedRect(vx, vy, vw, vh, cr, clipW, wgMiddle)
      of wgEnd:
        vg.rightClippedRoundedRect(vx, vy, vw, vh, cr, clipW, wgEnd)

      vg.fill()

      # Draw label text
      if label != "":
        vg.drawLabel(x, y, w, h, label, state, s.label)

      # Draw value text
      let valueString = if s.valuePrecision == 0: $value.int
                        else: value.formatFloat(ffDecimal, s.valuePrecision)

      vg.drawLabel(x, y, w, h, valueString, state, s.value)

    # Draw track outline
    vg.strokeColor(trackStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    drawTrackShape()
    vg.stroke()


  # Handle text field edit mode
  if isActive(id) and ss.state == ssEditValue:
    rawTextField(ox, oy, w, h, ss.valueText, activate=true)

    if ui.textFieldState.state == tfsDefault:
      value = try:
        let f = parseFloat(ss.valueText)
        if startVal < endVal: clamp(f, startVal, endVal)
        else:                 clamp(f, endVal, startVal)
      except: value

      value_out = value
      newPosX = calcPosX(value)

      ss.editModeItem = -1
      ss.state = ssDefault

      # Needed for the tooltips to work correctly
      setHot(id)

    else:
      setActive(id)
      setHot(id)

  if isHot(id):
    handleTooltip(id, tooltip)


template horizSlider*(x, y, w, h: float,
                      startVal:   float = 0.0,
                      endVal:     float = 1.0,
                      value:      float,
                      tooltip:    string = "",
                      label:      string = "",
                      style:      SliderStyle = DefaultSliderStyle,
                      grouping:   WidgetGrouping = wgNone) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  horizSlider(id, x, y, w, h, startVal, endVal, value, tooltip, label,
              style, grouping)

# }}}
# {{{ vertSlider

proc vertSlider(id:         ItemId,
                x, y, w, h: float,
                startVal:   float,
                endVal:     float,
                value_out:  var float,
                tooltip:    string = "",
                style:      SliderStyle = DefaultSliderStyle) =

  var value = value_out

  assert (startVal <   endVal and value >= startVal and value <= endVal  ) or
         (endVal   < startVal and value >= endVal   and value <= startVal)

  alias(ui, g_uiState)
  alias(ss, ui.sliderState)
  alias(s,  style)

  let (x, y) = addDrawOffset(x, y)

  let
    posMinY = y + h - s.trackPad
    posMaxY = y + s.trackPad

  # Calculate current slider position
  proc calcPosY(val: float): float =
    let t = invLerp(startVal, endVal, val)
    lerp(posMinY, posMaxY, t)

  let posY = calcPosY(value)

  # Hit testing
  if isHit(x, y, w, h):
    setHot(id)
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  # New position & value calculation
  var newPosY = posY

  if isActive(id):
    case ss.state:
    of ssDefault:
      ui.y0 = ui.my
      ui.dragX = -1.0
      ui.dragY = ui.my
      ui.widgetMouseDrag = true
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

      let dy = (ui.dy - ui.y0) / d

      newPosY = clamp(posY + dy, posMaxY, posMinY)
      let t = invLerp(posMinY, posMaxY, newPosY)
      value = lerp(startVal, endVal, t)
      ui.y0 = ui.dy

      ss.cursorPosY = if s.cursorFollowsValue: newPosY
                      else: ui.dragY

    of ssEditValue:
      discard

  value_out = value

  # Draw slider
  addDrawLayer(ui.currentLayer, vg):
    let state = if isHot(id) and hasNoActiveItem(): wsHover
                elif isActive(id): wsDown
                else: wsNormal

    var sw = s.trackStrokeWidth
    var (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    let (trackFillColor, trackStrokeColor, sliderColor) =
      case state
      of wsHover:
        (s.trackFillColorHover, s.trackStrokeColorHover, s.sliderColorHover)
      of wsDown:
        (s.trackFillColorDown, s.trackStrokeColorDown, s.sliderColorDown)
      else:
        (s.trackFillColor, s.trackStrokeColor, s.sliderColor)

    # Draw track background
    vg.fillColor(trackFillColor)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.trackCornerRadius)
    vg.fill()

    # Draw value
    let
      vx = x + s.trackPad
      vy = newPosY
      vw = w - s.trackPad*2
      vh = y + h - newPosY - s.trackPad
      cr = s.valueCornerRadius

    vg.fillColor(sliderColor)

    vg.beginPath()
    vg.roundedRect(vx, vy, vw, vh, cr)
    vg.fill()

    # Draw track outline
    vg.strokeColor(trackStrokeColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.roundedRect(x, y, w, h, s.trackCornerRadius)
    vg.stroke()

  if isHot(id):
    handleTooltip(id, tooltip)


template vertSlider*(x, y, w, h: float,
                     startVal:   float,
                     endVal:     float,
                     value:      float,
                     tooltip:    string = "",
                     style:      SliderStyle = DefaultSliderStyle) =

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  vertSlider(id, x, y, w, h, startVal, endVal, value, tooltip, style)

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
        setCursorPosX(ss.cursorPosX)
      else:
        setCursorPosY(ss.cursorPosY)

    ui.widgetMouseDrag = false

# }}}

# }}}
# {{{ Color

var ColorPickerRadioButtonStyle = RadioButtonsStyle(
  buttonPadHoriz             : 2.0,
  buttonPadVert              : 3.0,
  buttonCornerRadius         : 4.0,
  buttonStrokeWidth          : 0.0,
  buttonStrokeColor          : black(),
  buttonStrokeColorHover     : black(),
  buttonStrokeColorDown      : black(),
  buttonStrokeColorActive    : black(),
  buttonFillColor            : gray(0.25),
  buttonFillColorHover       : gray(0.25),
  buttonFillColorDown        : gray(0.45),
  buttonFillColorActive      : gray(0.45),
  buttonFillColorActiveHover : gray(0.45),
  label                      : getDefaultLabelStyle()
)

with ColorPickerRadioButtonStyle.label:
  fontSize         = 13.0
  fontFace         = "sans-bold"
  padHoriz         = 0.0
  align            = haCenter
  color            = gray(0.6)
  colorHover       = gray(0.6)
  colorDown        = gray(0.8)
  colorActive      = gray(1.0)
  colorActiveHover = gray(1.0)


var ColorPickerSliderStyle = SliderStyle(
  trackCornerRadius      : 4.0,
  trackPad               : 0.0,
  trackStrokeWidth       : 1.0,
  trackStrokeColor       : gray(0.1),
  trackStrokeColorHover  : gray(0.1),
  trackStrokeColorDown   : gray(0.1),
  trackFillColor         : gray(0.25),
  trackFillColorHover    : gray(0.30),
  trackFillColorDown     : gray(0.25),
  sliderColor            : gray(0.45),
  sliderColorHover       : gray(0.55),
  sliderColorDown        : gray(0.45),
  label                  : getDefaultLabelStyle(),
  value                  : getDefaultLabelStyle(),
  valuePrecision         : 0,
  valueCornerRadius      : 4,
  cursorFollowsValue     : true
)

with ColorPickerSliderStyle:
  label.padHoriz    = 5.0
  label.fontSize    = 13.0
  label.fontFace    = "sans-bold"
  label.align       = haLeft
  label.color       = gray(0.8)
  label.colorHover  = gray(0.9)
  label.colorDown   = gray(0.8)

  value.padHoriz    = 5.0
  value.fontSize    = 13.0
  value.fontFace    = "sans"
  value.align       = haRight
  value.color       = white()
  value.colorHover  = white()
  value.colorDown   = white()


var ColorPickerTextFieldStyle = TextFieldStyle(
  bgCornerRadius      : 4.0,
  bgStrokeWidth       : 1.0,
  bgStrokeColor       : gray(0.1),
  bgStrokeColorHover  : gray(0.1),
  bgStrokeColorActive : gray(0.1),
  bgFillColor         : gray(0.25),
  bgFillColorHover    : gray(0.30),
  bgFillColorActive   : gray(0.25),
  textPadHoriz        : 8.0,
  textPadVert         : 2.0,
  textFontSize        : 13.0,
  textFontFace        : "sans-bold",
  textColor           : gray(0.8),
  textColorHover      : gray(0.8),
  textColorActive     : gray(0.8),
  cursorColor         : rgb(1.0, 0.8, 0.0),
  cursorWidth         : 1.0,
  selectionColor      : rgb(0.5, 0.15, 0.15)
)

# {{{ colorWheel()
proc colorWheel(x, y, w, h: float; hue, sat, val: var float) =
  alias(ui, g_uiState)
  alias(cs, ui.colorPickerState)

  let (x, y) = addDrawOffset(x, y)

  let
    # Circle
    cx = x + w*0.5
    cy = y + h*0.5
    r1 = (if w < h: w else: h) * 0.5
    r0 = r1 - r1*0.20

    # Triangle
    x1 = cx + r0 * cos(5*PI/6)
    y1 = cy + r0 * sin(5*PI/6)
    x2 = cx + r0 * cos(PI/6)
    y2 = cy + r0 * sin(PI/6)
    x3 = cx + r0 * cos(1.5*PI)
    y3 = cy + r0 * sin(1.5*PI)


  proc wheelAngleFromCursor(): float =
    let dx = ui.mx - cx
    let dy = ui.my - cy
    result = arctan2(dy, dx)

  proc hueFromWheelAngle(a: float): float =
    let aa = if a > 0: a else: 2*PI + a
    result = (aa / (2*PI) + 0.5) mod 1.0

  proc calcTriangleHalfPlaneDeterminants(): (float, float, float) =
    let m1 = (y3-y1)/(x3-x1)
    var mx = ui.mx - x1
    var my = ui.my - y1
    let dLeft = m1*mx - my

    let m2 = (y3-y2)/(x3-x2)
    mx = ui.mx - x2
    my = ui.my - y2
    let dRight = m2*mx - my

    let dBottom = if ui.my < y1: -1.0 else: 1.0
    result = (dLeft, dRight, dBottom)

  # Hit testing
  if cs.mouseMode == cmmNormal:
    if isHit(x, y, w, h) and ui.mbLeftDown:
      let
        dy = ui.my - cy
        a = wheelAngleFromCursor()
        r = dy / sin(a)

      if r >= r0 and r <= r1:
        hue = hueFromWheelAngle(a)
        cs.mouseMode = cmmDragWheel
        ui.focusCaptured = true
      else:
        let (dLeft, dRight, dBottom) = calcTriangleHalfPlaneDeterminants()
        let insideTriangle = dLeft < 0 and dRight < 0 and dBottom < 0
        if insideTriangle:
          cs.mouseMode = cmmDragTriangle
          ui.focusCaptured = true
        else:
          cs.mouseMode = cmmLMBDown  # LMB down outside of any active area

  elif cs.mouseMode == cmmLMBDown:
    if not ui.mbLeftDown:
      cs.mouseMode = cmmNormal

  # "Fall-through" from hit testing stage
  if cs.mouseMode == cmmDragWheel:
    if not ui.mbLeftDown:
      cs.mouseMode = cmmNormal
      ui.focusCaptured = false
    else:
      let a = wheelAngleFromCursor()
      hue = hueFromWheelAngle(a)

  elif cs.mouseMode == cmmDragTriangle:
    if not ui.mbLeftDown:
      cs.mouseMode = cmmNormal
      ui.focusCaptured = false
    else:
      var mx, my: float
      let (dLeft, dRight, dBottom) = calcTriangleHalfPlaneDeterminants()
      let insideTriangle = dLeft < 0 and dRight < 0 and dBottom < 0

      if insideTriangle:
        mx = ui.mx
        my = ui.my
      # Cursor is to the left of the left side -> project Y coord to the side
      elif dLeft > 0:
        my = clamp(ui.my, y3, y1)
        let dy = y1-y3
        mx = lerp(x1, x3, (y1-my)/dy)
      # Cursor is to the right of the right side -> project Y coord to the side
      elif dRight > 0:
        my = clamp(ui.my, y3, y1)
        let dy = y1-y3
        mx = lerp(x2, x3, (y1-my)/dy)
      # Cursor below the bottom side -> project the X coord to the side
      elif dBottom > 0:
        mx = clamp(ui.mx, x1, x2)
        my = y1

      # Convert screen-coordinates into "local" coordinates (triangle within
      # the unit-circle), so we can rotate them.
      mx -= cx
      my -= cy

      # The angle is negative because the Y-axis in NanoVG is flipped, and
      # we're dealing with an "unflipped" transform matrix here
      const M = mat3f().rotate(-2*PI/3)
      let vm = M * vec3f(mx, my, 1)

      # Because of the rotation trick, we can easily calculate the saturation
      # and value from the "local" mouse coordinates (value runs along the
      # Y axis, saturation along the X axis)
      let dy = y1-y3
      val = ((vm.y)-(y3-cy)) / dy
      val = clamp(val, 0, 1)  # there's a chance to over/undershoot

      const Eps = 0.0001
      sat = if val < Eps: 0.0
            else:
              let xs = lerp(x3-cx, x1-cx, val)
              let xe = lerp(x3-cx, x2-cx, val)
              invLerp(xs, xe, vm.x)

      sat = clamp(sat, 0, 1)  # there's a chance to over/undershoot


  let hue = hue
  let sat = sat
  let val = val

  addDrawLayer(ui.currentLayer, vg):
    let da = 0.5 / r1

    # Draw triangle
    vg.strokeColor(black)
    vg.strokeWidth(1.0)
    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    vg.lineTo(x3, y3)
    vg.closePath()

    var paint = vg.linearGradient(x3, y3, x2, y2,
                                  hsla(hue, 1.0, 0.5, 1.0), white())
    vg.fillPaint(paint)
    vg.fill()

    paint = vg.linearGradient(x1, y1, x3+(x2-x3)*0.5, y3+(y2-y3)*0.5,
                              black(), black(0))
    vg.fillPaint(paint)
    vg.fill()

    # Draw triangle marker
    let xs = lerp(x3, x1, val)
    let xe = lerp(x3, x2, val)

    var my = lerp(y3, y1, val)
    var mx = lerp(xs, xe, sat)

    vg.save()
    vg.translate(cx, cy)
    vg.rotate(-2*PI/3)

    vg.strokeWidth(1.0)
    vg.beginPath()
    vg.circle(mx-cx, my-cy, 5)
    vg.strokeColor(black(0.8))
    vg.stroke()

    vg.beginPath()
    vg.circle(mx-cx, my-cy, 4)
    vg.strokeColor(white(0.8))
    vg.stroke()

    vg.restore()

    # Draw wheel
    const Segments = 6

    for i in 0..<Segments:
      var
        a0 =  float(i)        / Segments * 2*PI - da
        a1 = (float(i) + 1.0) / Segments * 2*PI + da

      vg.beginPath()
      vg.arc(cx, cy, r0, a0, a1, pwCW)
      vg.arc(cx, cy, r1, a1, a0, pwCCW)
      vg.closePath()

      let
        r = r0 + r1
        ax = cx + cos(a0) * r * 0.5
        ay = cy + sin(a0) * r * 0.5
        bx = cx + cos(a1) * r * 0.5
        by = cy + sin(a1) * r * 0.5

        paint = vg.linearGradient(ax, ay, bx, by,
                                  hsla(0.5 + a0 / (2*PI), 1.0, 0.50, 1.00),
                                  hsla(0.5 + a1 / (2*PI), 1.0, 0.50, 1.00))
      vg.fillPaint(paint)
      vg.fill()

    # Draw wheel marker
    vg.save()
    vg.translate(cx, cy)
    vg.rotate(PI + hue * 2*PI)

    mx = (r0 + r1)*0.5
    vg.strokeWidth(1.0)
    vg.beginPath()
    vg.circle(mx, 0, 5)
    vg.strokeColor(black(0.8))
    vg.stroke()

    vg.beginPath()
    vg.circle(mx, 0, 4)
    vg.strokeColor(white(0.8))
    vg.stroke()

    vg.restore()

# }}}
# {{{ color()
proc color(id: ItemId, x, y, w, h: float, color_out: var Color) =
  alias(ui, g_uiState)
  alias(cs, ui.colorPickerState)

  var color = color_out

  let (ox, oy) = (x, y)
  let (x, y) = addDrawOffset(x, y)

  if isHit(x, y, w, h):
    if ui.mbLeftDown and hasNoActiveItem():
      cs.activeItem = id
      cs.opened = true
      cs.mouseMode = cmmNormal

  # Draw color widget
  addDrawLayer(ui.currentLayer, vg):
    let
      sw = 1.0
      (x, y, w, h) = snapToGrid(x, y, w, h, sw)
      hw = w/2
      cr = 5.0

    vg.fillColor(color.withAlpha(1.0))
    vg.beginPath()
    vg.roundedRect(x, y, hw, h, cr, 0, 0, cr)
    vg.fill()

    vg.fillColor(color)
    vg.beginPath()
    vg.roundedRect(x+hw, y, hw, h, 0, cr, cr, 0)
    vg.fill()

    vg.strokeColor(gray(0.1))
    vg.strokeWidth(sw)
    vg.beginPath()
    vg.roundedRect(x, y, w, h, cr)
    vg.stroke()


  const PopupWidth = 180.0

  if cs.activeItem == id:
    if not beginPopup(w=PopupWidth, h=311, ax=ox-1, ay=oy, aw=w+2, ah=h):
      cs.activeItem = 0
    else:
      const startY = 14.0
      var
        x = 14.0
        y = x
        w = PopupWidth - 2*x
        h = 20.0

      y = 178.0

      cs.lastColorMode = cs.colorMode

      radioButtons(
        x, y, w+2, h+2,
        labels = @["RGB", "HSV", "Hex"],
        cs.colorMode, style=ColorPickerRadioButtonStyle)

      y += 30

      case cs.colorMode
      of ccmRGB:
        var
          r = color.r.float * 255
          g = color.g.float * 255
          b = color.b.float * 255
          a = color.a.float * 255

        horizSlider(x, y, w, h, startVal = 0, endVal = 255, r,
                    grouping=wgStart, label="R", style=ColorPickerSliderStyle)

        y += 20
        horizSlider(x, y, w, h, startVal = 0, endVal = 255, g,
                    grouping=wgMiddle, label="G", style=ColorPickerSliderStyle)

        y += 20
        horizSlider(x, y, w, h, startVal = 0, endVal = 255, b,
                    grouping=wgEnd, label="B", style=ColorPickerSliderStyle)

        y += 30
        horizSlider(x, y, w, h-1, startVal = 0, endVal = 255, a,
                    label="A", style=ColorPickerSliderStyle)

        const Eps = 0.0001
        var (hue, sat, val) = rgba(r/255, g/255, b/255, a/255).toHSV
        if sat < Eps or r < Eps and g < Eps and b < Eps:
          hue = cs.lastHue

        colorWheel(x, startY, w+0.5, w+0.5, hue, sat, val)

        cs.lastHue = hue
        color_out = hsva(hue, sat, val, a/255)


      of ccmHSV:
        if cs.opened or cs.lastColorMode != ccmHSV:
          (cs.h, cs.s, cs.v) = color.toHSV

        var
          hue = cs.h * 360
          sat = cs.s * 100
          val = cs.v * 100

        var a = color.a.float * 255

        horizSlider(x, y, w, h, startVal = 0, endVal = 360, hue,
                    grouping=wgStart, label="H", style=ColorPickerSliderStyle)

        y += 20
        horizSlider(x, y, w, h, startVal = 0, endVal = 100, sat,
                    grouping=wgMiddle, label="S", style=ColorPickerSliderStyle)

        y += 20
        horizSlider(x, y, w, h, startVal = 0, endVal = 100, val,
                    grouping=wgEnd, label="V", style=ColorPickerSliderStyle)

        y += 30
        horizSlider(x, y, w, h-1, startVal = 0, endVal = 255, a,
                    label="A", style=ColorPickerSliderStyle)

        (cs.h, cs.s, cs.v) = (hue/360, sat/100, val/100)

        colorWheel(x, startY, w+0.5, w+0.5, cs.h, cs.s, cs.v)

        color_out = hsva(cs.h, cs.s, cs.v, a/255)


      of ccmHex:
        if cs.opened or cs.lastColorMode != ccmHex:
          cs.hexString = color.toHex

        var a = color.a.float * 255

        textField(x, y, w, h-1, cs.hexString, style=ColorPickerTextFieldStyle)

        y += 20 + 20 + 30
        horizSlider(x, y, w, h-1, startVal = 0, endVal = 255, a,
                    label="A", style=ColorPickerSliderStyle)

        color = colorFromHexStr(cs.hexString).withAlpha(a/255)

        var (hue, sat, val) = color.toHSV
        let (oldHue, oldSat, oldVal) = (hue, sat, val)

        colorWheel(x, startY, w+0.5, w+0.5, hue, sat, val)

        color = hsva(hue, sat, val, a/255)
        if hue != oldHue or sat != oldSat or val != oldVal:
          cs.hexString = color.toHex

        color_out =  color


      # Make sure 'opened' is only true in the first frame after opening the
      # color picker
      cs.opened = false

      endPopup()

# }}}

template color*(x, y, w, h: float, color: var Color) =
  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  color(id, x, y, w, h, color)


template color*(col: var Color) =
  alias(ui, g_uiState)
  alias(a, ui.autoLayoutState)

  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  color(id, a.x, a.y, a.nextItemWidth, a.nextItemHeight, col)

  handleAutoLayout()

# }}}

# {{{ ScrollView

var DefaultScrollViewScrollBarStyle = getDefaultScrollBarStyle()

with DefaultScrollViewScrollBarStyle:
  trackCornerRadius   = 6.0
  trackFillColor      = gray(0, 0)
  trackFillColorHover = gray(0, 0.14)
  trackFillColorDown  = gray(0, 0.14)
  thumbCornerRadius   = 4.0
  thumbFillColor      = gray(0.422)
  thumbFillColorHover = gray(0.54)
  thumbFillColorDown  = gray(0.48)

type ScrollViewState = ref object of RootObj
  x, y, w, h: float
  viewStartY: float

# TODO style param
let ScrollViewScrollBarWidth = 14.0

# {{{ beginScrollView*()
proc beginScrollView*(id: ItemId, x, y, w, h: float) =
  alias(vg, g_nvgContext)
  alias(ui, g_uiState)

  let (x, y) = addDrawOffset(x, y)

  addDrawLayer(ui.currentLayer, vg):
    vg.save()
    vg.intersectScissor(x, y, w-ScrollViewScrollBarWidth, h)

    vg.strokeColor(black())
    vg.strokeWidth(1)
    vg.beginPath()
    vg.rect(x, y, w, h)
    vg.stroke()

  ui.scrollViewState.activeItem = id

  discard ui.itemState.hasKeyOrPut(id,
    ScrollViewState(x: x, y: y, w: w, h: h)
  )
  var ss = cast[ScrollViewState](ui.itemState[id])

  pushDrawOffset(
    DrawOffset(ox: x, oy: y - ss.viewStartY)
  )

  ui.itemState[id] = ss


template beginScrollView*(x, y, w, h: float) =
  let i = instantiationInfo(fullPaths=true)
  let id = generateId(i.filename, i.line, "")

  beginScrollView(id, x, y, w, h)

# }}}
# {{{ endScrollView*()
proc endScrollView*() =
  alias(ui, g_uiState)
  alias(vg, g_nvgContext)
  alias(a, ui.autoLayoutState)

  addDrawLayer(ui.currentLayer, vg):
    vg.restore()

  popDrawOffset()

  # TODO make this configurable
  const ScrollSensitivity = if defined(macosx): 10 else: 40

  let id = ui.scrollViewState.activeItem
  var ss = cast[ScrollViewState](ui.itemState[id])

  var viewStartY = ss.viewStartY

  let visibleHeight = ss.h
  let contentHeight = a.yNoPad

  if contentHeight > visibleHeight:
    let thumbSize = visibleHeight *
                    ((contentHeight - visibleHeight) / contentHeight)

    let endVal = contentHeight - visibleHeight

    if isHit(ss.x, ss.y, ss.w, ss.h):
      if hasEvent() and ui.currEvent.kind == ekScroll:
        viewStartY -= ui.currEvent.oy * ScrollSensitivity
        ui.eventHandled = true

    viewStartY = viewStartY.clamp(0, endVal)

    let sbId = hashId(lastIdString() & ":scrollBar")

    vertScrollBar(
      sbId,
      x=(ss.x + ss.w - ScrollViewScrollBarWidth), y=ss.y,
      w=ScrollViewScrollBarWidth, h=visibleHeight,
      startVal=0, endVal=endVal,
      viewStartY,
      thumbSize=thumbSize, clickStep=20,
      style=DefaultScrollViewScrollBarStyle)

  else:
    viewStartY = 0

  ss.viewStartY = viewStartY
  ui.itemState[id] = ss

  ui.scrollViewState.activeItem = 0

# }}}

# }}}

#[
# {{{ Menu
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
    if ui.mbLeftDown and hasNoActiveItem():
      setActive(id)

  # LMB released over active widget means it was clicked
#  if not ui.mbLeftDown and isHot(id) and isActive(id):
#    result = true

  # Draw menu bar
  let state = if isHot(id) and hasNoActiveItem(): wsHover
    elif isHot(id) and isActive(id): wsActive
    else: wsNormal

  let fillColor = case state
    of wsHover:  GRAY_HI
    of wsActive: HILITE
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

# }}}

# {{{ General

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

  win.keyCb  = keyCb
  win.charCb = charCb
  win.mouseButtonCb = mouseButtonCb
  win.scrollCb = scrollCb

  # LockKeyMods must be enabled so we can differentiate between keypad keys
  # and keypad cursor movement keys
  win.lockKeyMods = true

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

  ui.drawOffsetStack = @[
    DrawOffset(ox: 0, oy: 0)
  ]

  ui.currentLayer = layerDefault

  ui.winWidth = winWidth
  ui.winHeight = winHeight

  # Store mouse state
  ui.lastmx = ui.mx
  ui.lastmy = ui.my

  if ui.widgetMouseDrag:
    (ui.dx, ui.dy) = win.cursorPos()
  else:
    (ui.mx, ui.my) = win.cursorPos()

  ui.hasEvent = false
  ui.eventHandled = false

  # Get next pending event from the queue
  if g_eventBuf.canRead():
    ui.currEvent = g_eventBuf.read().get
    ui.hasEvent = true
    let ev = ui.currEvent

    setFramesLeft()

    # Update current mouse button state
    if ev.kind == ekMouseButton:
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

  # Reset hot item
  ui.hotItem = 0

  # Layout
  ui.autoLayoutParams = DefaultAutoLayoutParams
  initAutoLayout()

  g_drawLayers.init()

# }}}
# {{{ endFrame*()

proc endFrame*() =
  alias(ui, g_uiState)

  # Post-frame processing
  tooltipPost()

  setCursorMode(ui.cursorShape)

  g_drawLayers.draw(g_nvgContext)

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

  # Decrement remaining frames counter
  if ui.framesLeft > 0: dec(ui.framesLeft)

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

# }}}

# vim: et:ts=2:sw=2:fdm=marker
