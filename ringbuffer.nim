import options

type RingBuffer[T] = object
  buf:      seq[T]
  readPos:  Natural
  writePos: Natural

proc initRingBuffer*[T](bufSize: Natural): RingBuffer[T] =
  assert bufSize >= 2
  result.buf = newSeq[T](bufSize)

proc prevPos[T](cb: RingBuffer[T], p: Natural): Natural {.inline.} =
  if p == 0: cb.buf.high else: (p.int) - 1

proc nextPos[T](cb: RingBuffer[T], p: Natural): Natural {.inline.} =
  if p < cb.buf.high: p+1 else: 0

proc canRead*[T](cb: RingBuffer[T]): bool {.inline.} =
  cb.readPos != cb.writePos

proc read*[T](cb: var RingBuffer[T]): Option[T] =
  if cb.canRead():
    result = cb.buf[cb.readPos].some
    cb.readPos = cb.nextPos(cb.readPos)
  else:
    result = T.none

proc canWrite*[T](cb: RingBuffer[T]): bool {.inline.} =
  cb.writePos != cb.prevPos(cb.readPos)

proc write*[T](cb: var RingBuffer[T], item: T): bool =
  if cb.canWrite():
    cb.buf[cb.writePos] = item
    cb.writePos = cb.nextPos(cb.writePos)
    result = true
  else:
    result = false

proc clear*[T](cb: var RingBuffer[T]) =
  cb.readPos = 0
  cb.writePos = 0
