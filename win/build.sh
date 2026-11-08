#!/bin/sh
# Cross-compiles syswatch.exe for 64-bit Windows (run from any OS with Go 1.22+).
set -e
VERSION="${VERSION:-0.1.0}"
mkdir -p dist
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath \
  -ldflags "-s -w -H=windowsgui -X main.version=$VERSION" \
  -o dist/syswatch.exe ./cmd/syswatch
echo "built dist/syswatch.exe ($VERSION)"
