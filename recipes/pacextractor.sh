# pacextractor - Unisoc/Spreadtrum .pac firmware extractor (in-tree C)
deps=""
provides="pacextractor"

build() {
	"$CC" $CFLAGS -std=c99 -Wall -o pacextractor pacextractor.c $LDFLAGS
	put_bin pacextractor
}
