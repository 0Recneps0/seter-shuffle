#!/bin/bash
# daily.sh (SeTeR Shuffle, Python build)
#
# Thin shortcut for `run.sh daily`: ALL of the daily run's logic
# lives in run.sh now (exp-2026-11-26.1), so there is one daily
# implementation instead of two that can drift apart. This script
# only resolves its own directory and hands off:
#   ./daily.sh "My New Sandwich Recipe"   -> ./run.sh daily "My New Sandwich Recipe"
#   ./daily.sh                            -> ./run.sh daily (default playlist, same name)
#
# The launchd plist still calls daily.sh with the playlist arg,
# so the interface is unchanged. The daily run itself (in run.sh):
# auto self-probes each target, dedupes, shuffles, refreshes Flow
# and Rediscover, writes a once-a-day library manifest, logs to
# $STATE/daily.log, takes the single-run lock (dry runs skip it),
# and always has AI tagging on (SETER_AI=1). It never touches
# the v2.6 install or its launchd job. See the daily section in
# run.sh for the hard rules.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/run.sh" daily "$@"
