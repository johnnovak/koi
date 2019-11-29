import macros

var level = 0

proc indentEcho(s: string) =
  var p = ""
  for i in 0..<level:
    p &= "  "
  echo p & s

proc beginMenuBar() =
  indentEcho "beginMenuBar"
  inc(level)

proc endMenuBar() =
  dec(level)
  indentEcho "endMenuBar"


proc beginMenuBarItem() =
  indentEcho "beginMenuBarItem"
  inc(level)

proc endMenuBarItem() =
  dec(level)
  indentEcho "endMenuBarItem"


proc beginMenuParentItem() =
  indentEcho "beginMenuParentItem"
  inc(level)

proc endMenuParentItem() =
  dec(level) 
  indentEcho "endMenuParentItem"


template lineNo(): int =
  var i = instantiationInfo(fullPaths = true)
  i.line


template menuBar(x, y, w, h: float, menus: untyped): untyped =
  beginMenuBar()
  menus
  endMenuBar()

template menuBarItem(name: string, menuItems: untyped): untyped =
  beginMenuBarItem()
  menuItems
  endMenuBarItem()

template menuParentItem(name: string, menuItems: untyped): untyped =
  beginMenuParentItem()
  menuItems
  endMenuParentItem()


proc menuItem(name: string): bool =
  indentEcho name
  result = false

proc menuItemSeparator() =
  discard


menuBar(0, 5, 500, 10):
  menuBarItem("File"):
    menuParentItem("&New"):
      if menuItem("&General"):       echo "File -> New -> General"
      if menuItem("2&D Animation"):  echo "File -> New -> 2D Animation"
      if menuItem("&Sculpting"):     echo "File -> New -> Sculpting"
      if menuItem("&VFX"):           echo "File -> New -> VFX"
      if menuItem("Video &Editing"): echo "File -> New -> Video Editing"

    if menuItem("&Open..."):
      echo "File -> Open"

    menuParentItem("Open &Recent..."):
      discard menuItem("No recent files")

  menuBarItem("Edit"):
    if menuItem("&Undo"):
      echo "Edit -> Undo"

    if menuItem("&Redo"):
      echo "Edit -> Redo"

    menuItemSeparator()

    if menuItem("Undo &History..."): echo "Edit -> Undo History"


  menuBarItem("Help"):
    if menuItem("&Manual"):    echo "Help -> Manual"
    if menuItem("&Tutorials"): echo "Help -> Tutorials"
    if menuItem("&Support"):   echo "Help -> Support"

    menuItemSeparator()

    if menuItem("Save System &Info"): echo "Help -> Save System Info"

