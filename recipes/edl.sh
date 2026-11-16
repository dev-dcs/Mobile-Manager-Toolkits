# bkerler edl - Qualcomm EDL tool (Python, alternative to qdl for legacy)
deps=""
provides=""
# python tool, vendored; fb python wrapper calls it

build() {
	mkdir -p "$OUT/python/edl"
	cp -a edlclient "$OUT/python/edl/" 2>/dev/null || cp -a . "$OUT/python/edl/"
	put_license LICENSE
}
