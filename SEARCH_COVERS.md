# Covers in search results

Search results show six books per page with a thumbnail next to each title. Text appears first, then up to two cover workers load images for the visible page. Changing pages or closing the menu cancels those workers.

Placeholders show whether a cover is queued, being looked up or connecting. During the image transfer, the label shows a percentage when Content-Length is available, or received KB when it is not. No extra HEAD request is needed. Each cover has a 12-second deadline and the page has a 40-second deadline.

Covers come from the file or edition linked by the result. Files are checked for an image signature and limited to 1 MiB. They are stored under KOReader's data directory in `cache/annas-covers`, with atomic writes and a 160-file limit. Failed lookups are cached for five minutes. Remove this directory to clear the cache.

See `tests/SEARCH_COVERS.md` for the tests.
