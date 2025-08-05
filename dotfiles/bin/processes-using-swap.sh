#!/usr/bin/env bash

grep '^VmSwap:' /proc/*/status \
  | grep -v '0 kB$' \
  | sed -re 's#^/proc/([0-9]+)/status:VmSwap:[ \t]+([0-9]+) kB$#\1 \2#' \
  | sort -nrk2 \
  | while read pid swap; do \
      printf "%s kB %-6s " ${swap} ${pid}; \
      cat /proc/${pid}/cmdline | xargs -0 | fold -sw160 | sed -re '/^$/d; 1!s/^/\t\t\t\t/;'; \
    done | less -cRS
