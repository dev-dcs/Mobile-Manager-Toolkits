# mtkclient (bkerler) - MTK brom/da/preloader. python, master build only.
# warning: the Loader/*.bin download agents are ~50MB on their own, that's
# basically all the weight in the master zip. could prune to just V5/V6 someday.
deps=""
provides=""

build() {
	mkdir -p "$OUT/python/mtkclient"
	cp -a mtkclient "$OUT/python/mtkclient/" 2>/dev/null
	cp -a mtk_gui mtk_payload mtk "$OUT/python/mtkclient/" 2>/dev/null || true
	cp -a mtk_*.py "$OUT/python/mtkclient/" 2>/dev/null || true
	put_license LICENSE
}
