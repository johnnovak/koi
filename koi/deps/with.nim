## This module only contains a single, but rather useful macro. The ``with``
## macro allows you to put all the fields of an object or tuple into the
## scope of the block that is passed in. This is useful in instances where you
## take in an object to a procedure that only does work on this object, for
## example an initialiser or what would normally be seen as a method in a
## object oriented approach.

import macros

proc getAllIdentDefs(x: NimNode): seq[NimNode] =
  for n in x:
    if n.kind == nnkIdentDefs:
      result &= n
    elif n.kind in {nnkRecCase, nnkRecList, nnkOfBranch, nnkElse}:
      result &= getAllIdentDefs(n)

proc createInner(x: NimNode): NimNode =
  result = newStmtList()
  var t = getTypeImpl(x)
  if t.kind == nnkRefTy:
    t = getTypeImpl(t[0])
  assert(t.kind in {nnkObjectTy, nnkTupleTy}, "`with` must be called with " &
    "either objects or tuples.")
  for field in getAllIdentDefs(if t.kind == nnkObjectTy: t[2] else: t):
    let name = newIdentNode($field[0])
    if field[1].kind == nnkProcTy:
      result.add quote do:
        template `name`(args: varargs[untyped]): untyped {.used.} =
            `x`.`name`(args)
    else:
      result.add quote do:
        template `name`(): untyped {.used.} =
          `x`.`name`

macro with*(x: typed, body: untyped): untyped =
  ## ``x`` can be either an object, a tuple, or a tuple of objects and tuples.
  ## ``body`` is just any block of code that should be run with the fields of
  ## ``x`` (or the fields of all objects and tuples if multiple were given)
  ## visible to it.
  result = newStmtList()
  if x.kind == nnkTupleConstr:
    for y in x:
      result.add createInner(y)
  else:
    result.add createInner(x)
  result.add body
  result = nnkBlockStmt.newTree(newEmptyNode(), result)
