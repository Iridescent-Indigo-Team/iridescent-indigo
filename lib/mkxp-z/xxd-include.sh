#!/bin/sh
#
# Generate a C-include-style xxd dump with a fixed symbol name.
#
# xxd's `-i` derives the symbol name from the input path (so it varies with the
# build-directory depth, e.g. `../assets/icon.png` vs `../../assets/icon.png`),
# and the `-n` option used to pin it is only available in newer xxd releases.
# This wrapper works with any xxd by rewriting the symbol name afterwards.
#
# Usage: xxd-include.sh SYMBOL INFILE

symbol="$1"
infile="$2"

xxd -i "$infile" | sed \
    -e "1s/^unsigned char [^ ]*/unsigned char ${symbol}[]/" \
    -e "\$s/^unsigned int [^ ]*/unsigned int ${symbol}_len/"
