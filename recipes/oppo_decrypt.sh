# oppo_decrypt - Oppo/Realme/OnePlus .ofp/.ops firmware decryptor (Python)
deps=""
provides=""

build() {
	mkdir -p "$OUT/python/oppo_decrypt"
	cp -a *.py "$OUT/python/oppo_decrypt/" 2>/dev/null
	put_license LICENSE
}
