#!/bin/sh
# PLANNOTATOR_BROWSER target for review.py: plannotator runs this with the review URL instead of
# opening a browser; recording it lets review.py put a proxy in front and show the page in agterm.
printf '%s\n' "$1" > "${AGREV_READY:?AGREV_READY is not set}"
