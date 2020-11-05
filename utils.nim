template alias*(newName: untyped, call: untyped) =
  template newName(): untyped = call

template `++`*[A](a: ptr A, offset: int): ptr A =
  cast[ptr A](cast[int](a) + offset)

func lerp*(a, b, t: SomeFloat): SomeFloat =
  a + (b - a) * t

func invLerp*(a, b, v: SomeFloat): SomeFloat =
  (v - a) / (b - a)

