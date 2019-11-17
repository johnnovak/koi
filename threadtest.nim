import os

type GlobalState = object
  s: string
  a: seq[int]

var gGlobalState: ref GlobalState

var renderThread: Thread[ptr GlobalState]
var running = true


proc renderThreadFunc(gsp: ptr GlobalState) {.thread.} =
  var i = 5
  while i > 0:
    echo "renderThread " & $i
    sleep(1000)
    dec(i)
  echo "renderThread exiting"
  running = false


proc main() =
  new(gGlobalState)
  gGlobalState.s = "some string"
  gGlobalState.a = @[1,2,3,4]

  GC_ref(gGlobalState)

  createThread(renderThread, renderThreadFunc, (gGlobalState[]).addr)

  while running:
    sleep(300)
    echo "main thread running"

  echo "joining renderThread"

  joinThreads(renderThread)
  GC_unref(gGlobalState)

  echo "main thread exiting"


main()
