#!/usr/bin/env bash
#
# nativesym — native, plus the `symbols` tool.
#
# The question: does giving the model exact declaration extents remove the reading cost that broke
# three rounds on a 1,052-line file? `search` finds where a method STARTS; a plan saying "insert
# after the whole of X" needs where it ENDS, and getting there from grep means reading the file and
# counting braces.
#
# Its control is `native` on the same plan under the same harness tree. The tool is switched on by
# an environment variable rather than by editing the tool list, precisely so the tree is identical
# between the two arms — bench/compare prints CONFOUNDED when it is not, and this project has
# already discarded 25 runs to that mistake.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativesym"; }
export NATIVE_SYMBOLS=1
