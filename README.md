# koi — immediate mode UI for Nim

![koi-orig-flat](https://github.com/johnnovak/koi/assets/698770/76e55eb0-c01c-4f9d-9ed0-a325058a21b0)

**koi** is a small (~5 KLOC) immediate mode UI library that uses OpenGL for rendering via NanoVG. It was mainly invented for the dungeon mapping tool [Gridmonger](https://gridmonger.johnnovak.net/) (see screenshot below), and then it evolved into a minimalist but feature-rich general-purpose UI library.

GLFW is currently a hard requirement, but it should be easy to adapt it to other frameworks or backends.

There is no documentation yet—check out the [examples](/examples) and Gridmonger for usage.

Support is currently *alpha level*, meaning that the API or the functionality might change without warning at any moment.

<img width="1312" alt="image" src="https://github.com/johnnovak/koi/assets/698770/dbf58114-5a68-4937-96ed-cd0109eebc89">

## Dependencies

Nim 2.0.2 or later and the following two libraries are required:

- [nim-glfw](https://github.com/johnnovak/nim-glfw)
- [nim-nanovg](https://github.com/johnnovak/nim-nanovg)

You can install them with [Nimble](https://github.com/nim-lang/nimble):

```
nimble install glfw nanovg
```

## Building

To build the examples (the dependencies will be auto-installed if needed):

```
nimble test
nimble paneltest
```

or

```
nimble testRelease
nimble paneltestRelease
```

See [config.nims](/config.nims) on how to link statically **koi** and **GLFW** to your program.

## License

Copyright © 2019-2024 John Novak <<john@johnnovak.net>>

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net/), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

