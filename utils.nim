template alias*(newName: untyped, call: untyped) =
  template newName(): untyped = call

template `++`*(s: string, offset: SomeInteger): cstring =
  cast[cstring](cast[int](cstring(s)) + offset)

template `++`*(p: ptr, offset: SomeInteger): ptr =
  cast[ptr](cast[int](p) + offset)

func lerp*(a, b, t: SomeFloat): SomeFloat =
  a + (b - a) * t

func invLerp*(a, b, v: SomeFloat): SomeFloat =
  (v - a) / (b - a)

