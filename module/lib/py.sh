# shared python locator for the vendored-python fb tools - @Dev_DcS
# shellcheck shell=sh
#
# Static tools in /system/bin cannot embed a Python, so the python-based
# tools (avbtool, payload, oppo, unisoc, mtkclient) run under whatever
# Python the user has: Termux, a rooted /data python, or one in PATH.

FB_PY=""

find_py() {
	[ -n "$FB_PY" ] && return 0
	for p in \
		"$PYTHON" \
		"$PREFIX/bin/python3" \
		/data/data/com.termux/files/usr/bin/python3 \
		/data/local/tmp/python3/bin/python3 \
		"$(command -v python3 2>/dev/null)" \
		"$(command -v python 2>/dev/null)"
	do
		[ -n "$p" ] && [ -x "$p" ] && { FB_PY=$p; return 0; }
	done
	return 1
}

need_py() {
	find_py && return 0
	cat >&2 <<EOF
! this command needs Python, which Android does not ship.
  Install Termux + python, or point \$PYTHON at a python3 binary:
    pkg install python          # in Termux
    PYTHON=/path/to/python3 fb $*
EOF
	exit 3
}

# pyrun <script.py> [args...] - run a vendored script isolated (-I: ignore the
# target's site-packages and env, so a planted module cannot hijack it)
pyrun() {
	find_py || need_py "$@"
	"$FB_PY" -I "$@"
}

# pymod <dir> <module> [args...] - run `python -m module` with <dir> on the path,
# for vendored multi-file tools
pymod() {
	d=$1 m=$2
	shift 2
	find_py || need_py "$m"
	PYTHONPATH="$d${PYTHONPATH:+:$PYTHONPATH}" "$FB_PY" -I -m "$m" "$@"
}
