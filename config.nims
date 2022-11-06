proc setCommonCompileParams() =
  --gc:orc
  --deepcopy:on
  --d:nimPreviewFloatRoundtrip
  --d:nvgGL3
  --d:glfwStaticLib
  --d:glStaticProcs
  --hint:"Name:off"

task test, "build test":
  --d:debug
  setCommand "c", "examples/test"
  setCommonCompileParams()

task paneltest, "build panel test":
  --d:debug
  setCommand "c", "examples/paneltest"
  setCommonCompileParams()

task testRelease, "build test":
  --d:release
  setCommand "c", "examples/test"
  setCommonCompileParams()

task paneltestRelease, "build panel test":
  --d:release
  setCommand "c", "examples/paneltest"
  setCommonCompileParams()

