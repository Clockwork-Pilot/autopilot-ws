#!/bin/bash
# Wrapper: adds -self-hosted for self-hosted runner mode across platforms

# Detect current OS and map to runner type
PLATFORM=$(uname -s)
case "$PLATFORM" in
  Linux*)
    RUNNER="-P ubuntu-latest=-self-hosted"
    ;;
  Darwin*)
    RUNNER="-P macos-latest=-self-hosted"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    RUNNER="-P windows-latest=-self-hosted"
    ;;
  *)
    RUNNER="-P ubuntu-latest=-self-hosted"
    ;;
esac

/usr/local/bin/act-real "$@" $RUNNER
