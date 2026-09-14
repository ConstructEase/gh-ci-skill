# Named-check wait rerun

Pinned gh-ci commit: `9594571c` (materialized as 1.3.2). The local loopback
mock used the 60-second `scan_ruby` flip. This directory contains 15 T3
rows and 15 corrected gh-axi T7–T9 rows, plus their aggregates. No real GitHub
requests were made. Original judge outputs were retained alongside regraded
outputs where applicable.
