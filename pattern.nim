import options

const
  RowsPerPattern* = 32
  NoteNone* = -1
  NumSemitones* = 12

type
  Note* = range[0..127]


  Pattern* = object
    tracks*: seq[Track]

  Track* = object
    rows*: array[RowsPerPattern, Cell]

  Cell* = object
    note*:      Option[Note]
    effect*:    array[3, char]


proc resetCell*(c: var Cell) =
  c.note = none(Note)
  c.effect[0] = '0'
  c.effect[1] = '0'
  c.effect[2] = '0'

proc initTrack*(): Track =
  for i in 0..result.rows.high:
    resetCell(result.rows[i])

proc initPattern*(): Pattern =
  result.tracks = newSeq[Track]()

proc toStr*(note: Option[Note]): string =
  if note.isNone: return "---"
  else:
    case note.get mod NumSemitones:
    of  0: result = "C-"
    of  1: result = "C#"
    of  2: result = "D-"
    of  3: result = "D#"
    of  4: result = "E-"
    of  5: result = "F-"
    of  6: result = "F#"
    of  7: result = "G-"
    of  8: result = "G#"
    of  9: result = "A-"
    of 10: result = "A#"
    of 11: result = "B-"
    else: discard
    result &= $(note.get div NumSemitones + 1)


const
  MidiChannelMin  = 0
  MidiChannelMax  = 15
  NumMidiChannels = 16

type
  MidiMessage = uint32
  Channel = range[0..15]
  DataByte = range[0..127]

  ChannelVoiceMessage = enum
    cvmNoteOff         = 0x80
    cvmNoteOn          = 0x90
    cvmPolyKeyPressure = 0xa0
    cvmControlChange   = 0xb0
    cvmProgramChange   = 0xc0
    cvmChannelPressure = 0xd0
    cvmPitchBend       = 0xe0

  ChannelModeMessage = enum
    cmmResetAllControllers = 0x79
    cmmLocalControl        = 0x7a
    cmmAllNotesOff         = 0x7b
    cmmOmniModeOff         = 0x7c
    cmmOmniModeOn          = 0x7d
    cmmMonoModeOn          = 0x7e
    cmmPolyModeOn          = 0x7f

func midiMessage(status: byte, ch: Channel,
                 data1: DataByte, data2: DataByte = 0): MidiMessage =
  (status.uint32 or ch.byte) or
  (data1.byte shl 8) or
  (data2.byte shl 16)

# Channel Voice Messages
func noteOffMsg(ch: Channel, n: Note, velocity: DataByte): MidiMessage =
  midiMessage(cvmNoteOff.byte, ch, n, velocity)

func noteOnMsg(ch: Channel, n: Note, velocity: DataByte): MidiMessage =
  midiMessage(cvmNoteOn.byte, ch, n, velocity)

func polyKeyPressureMsg(ch: Channel, n: Note,
                        pressure: DataByte): MidiMessage =
  midiMessage(cvmPolyKeyPressure.byte, ch, n, pressure)

func programChangeMsg(ch: Channel, program: DataByte): MidiMessage =
  midiMessage(cvmControlChange.byte, ch, program)

func channelPressureMsg(ch: Channel, pressure: DataByte): MidiMessage =
  midiMessage(cvmChannelPressure.byte, ch, pressure)

func pitchBendMsg(ch: Channel, msb: DataByte, lsb: DataByte): MidiMessage =
  midiMessage(cvmPitchBend.byte, ch, msb, lsb)

# Channel Mode Messages
func resetAllControllersMsg(): MidiMessage =
  midiMessage(cvmControlChange.byte, ch = 0, data1 = cmmResetAllControllers.byte)

let
  n1 = noteOffMsg(1, Note(25), 127)
  n2 = noteOnMsg(1, Note(25), 127)
  n3 = polyKeyPressureMsg(1, Note(25), 127)
  n4 = programChangeMsg(1, 127)
  n5 = channelPressureMsg(1, 127)
  n6 = pitchBendMsg(1, 50, 100)

  n7 = resetAllControllersMsg()

#Polyphonic Key Pressure (Aftertouch)	0xA	Note Number	Pressure
#Control Change	0xB	Controller Number	Value
#Program Change	0xC	Program Number
#Channel Pressure (Aftertouch)	0xD	Pressure
#Pitch Wheel	0xE	LSB	MSB
