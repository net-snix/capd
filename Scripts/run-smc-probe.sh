#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="/tmp/capd-smc-probe"

swiftc "${ROOT}/Scripts/smc-probe.swift" -o "${OUT}" -framework IOKit
sudo "${OUT}" "$@"
