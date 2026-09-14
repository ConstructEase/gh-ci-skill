# Named-check wait rerun

Pinned gh-ci commit: `9594571c` (materialized as 1.3.2). The local loopback
mock used the 60-second `scan_ruby` flip. This directory contains 15 T3
rows and 15 corrected gh-axi T7–T9 rows, plus their aggregates. No real GitHub
requests were made. Per-run transcripts, call logs, and original and regraded
judge outputs are retained privately by the maintainer outside this repository
because they embed the private answer keys. This directory retains only the
result TSVs, aggregates, and this manifest.
