import macros

macro menuBar(x, y, w, h: float, body: untyped) =
  for n in body:
    if n.kind == nnkCall and n[0].kind == nnkStrLit:
      echo $n[0]

  result = quote do:
    echo `x`
    echo `y`
    echo `w`
    echo `h`



let
  x = 12.0
  y = 42.0

var h = 20.0

menuBar(x, y, 500, h):
  "File":
    if menuParentItem("&New", some(mkKeyEvent(keyN, {mkSuper}))):
      if menuItem("&General"):       echo "File -> New -> General"

    if menuItem("&Open...", some(mkKeyEvent(keyO, {mkSuper}))):
      echo "File -> Open"

  "Help":
    if menuItem("&Open...", some(mkKeyEvent(keyO, {mkSuper}))):
      echo "File -> Open"

dumpTree:
  "File":
    if menuParentItem("&New", some(mkKeyEvent(keyN, {mkSuper}))):
      if menuItem("&General"):       echo "File -> New -> General"

    if menuItem("&Open...", some(mkKeyEvent(keyO, {mkSuper}))):
      echo "File -> Open"

  "Help":
    if menuItem("&Open...", some(mkKeyEvent(keyO, {mkSuper}))):
      echo "File -> Open"
