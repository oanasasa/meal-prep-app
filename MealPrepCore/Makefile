# Under a full Xcode install these framework flags are unnecessary — `swift test`
# finds Swift Testing automatically. On a Command Line Tools-only machine the
# Testing.framework lives in the CLT Developer/Frameworks dir, so we add it to
# the search path here.
FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks

.PHONY: test demo build

build:
	swift build

test:
	swift test \
	  -Xswiftc -F -Xswiftc "$(FW)" \
	  -Xlinker -F -Xlinker "$(FW)" \
	  -Xlinker -rpath -Xlinker "$(FW)"

demo:
	swift run mealprep-demo
