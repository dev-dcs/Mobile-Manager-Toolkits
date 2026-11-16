# sqlite3 shell, built for poking at pulled app databases (.recover included)
deps=""
provides="sqlite3"

build() {
	"$CC" $CFLAGS -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION \
		-DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_FTS5 \
		-DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_BYTECODE_VTAB \
		shell.c sqlite3.c -o sqlite3 $LDFLAGS
	put_bin sqlite3
}
