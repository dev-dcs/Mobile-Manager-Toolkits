/*
 * qcdiag - small Qualcomm DIAG client: NV items, EFS files, SPC, build id.
 *
 * The target has to expose its DIAG port (fb modem diag on), then either
 * through libusb (-u, default) or a serial node (-d /dev/ttyUSB0).
 *
 *   qcdiag info
 *   qcdiag nv read 1877
 *   qcdiag nv write 1877 0x00 0x00 ...      (hex bytes, rest zero-filled)
 *   qcdiag efs ls /nv/item_files/modem/mmode
 *   qcdiag efs get /nv/item_files/modem/mmode/lte_bandpref lte.bin
 *   qcdiag efs put /nv/item_files/modem/mmode/lte_bandpref lte.bin
 *   qcdiag raw 4b 13 00 00
 *
 * Identity items (ESN, IMEI, MEID) are never written.
 * @Dev_DcS
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "usbio.h"

#define DIAG_VERNO_F		0x00
#define DIAG_BAD_CMD_F		0x13
#define DIAG_BAD_PARM_F		0x14
#define DIAG_BAD_LEN_F		0x15
#define DIAG_BAD_MODE_F		0x18
#define DIAG_NV_READ_F		0x26
#define DIAG_NV_WRITE_F		0x27
#define DIAG_SPC_F		0x41
#define DIAG_BAD_SPC_MODE_F	0x42
#define DIAG_SUBSYS_CMD_F	0x4b
#define DIAG_EXT_BUILD_ID_F	0x7c

#define SUBSYS_EFS		0x13

#define EFS_HELLO	0
#define EFS_OPEN	2
#define EFS_CLOSE	3
#define EFS_READ	4
#define EFS_WRITE	5
#define EFS_OPENDIR	11
#define EFS_READDIR	12
#define EFS_CLOSEDIR	13
#define EFS_STAT	15

#define NV_SIZE		128
#define EFS_CHUNK	512

static int fd = -1;
#ifdef HAVE_LIBUSB
static struct usbio usb;
static int use_usb;
#endif
static int tmo = 3000;

/* ---- transport ------------------------------------------------------ */

static long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000;
}

static int tx(const uint8_t *b, int n)
{
#ifdef HAVE_LIBUSB
	if (use_usb)
		return usbio_write(&usb, b, n, tmo) == n ? 0 : -1;
#endif
	while (n > 0) {
		ssize_t w = write(fd, b, n);

		if (w < 0) {
			if (errno == EINTR || errno == EAGAIN) {
				usleep(1000);
				continue;
			}
			return -1;
		}
		b += w;
		n -= w;
	}
	return 0;
}

static int rx(uint8_t *b, int n, int ms)
{
#ifdef HAVE_LIBUSB
	if (use_usb)
		return usbio_read(&usb, b, n, ms);
#endif
	struct pollfd p = { .fd = fd, .events = POLLIN };
	int r = poll(&p, 1, ms);

	if (r <= 0)
		return r;
	r = read(fd, b, n);
	if (r < 0 && (errno == EINTR || errno == EAGAIN))
		return 0;
	return r;
}

/* ---- HDLC framing ---------------------------------------------------- */

static uint16_t crctab[256];

static void crc_init(void)
{
	int i, k;

	for (i = 0; i < 256; i++) {
		uint16_t c = i;

		for (k = 0; k < 8; k++)
			c = (c & 1) ? (c >> 1) ^ 0x8408 : c >> 1;
		crctab[i] = c;
	}
}

static uint16_t crc16(const uint8_t *p, int n)
{
	uint16_t c = 0xffff;

	while (n--)
		c = (c >> 8) ^ crctab[(c ^ *p++) & 0xff];
	return ~c;
}

static int hdlc_put(uint8_t *o, uint8_t b)
{
	if (b == 0x7e || b == 0x7d) {
		o[0] = 0x7d;
		o[1] = b ^ 0x20;
		return 2;
	}
	o[0] = b;
	return 1;
}

static int send_pkt(const uint8_t *p, int n)
{
	static uint8_t o[2 * (EFS_CHUNK + 1024) + 8];
	uint16_t c = crc16(p, n);
	int i, k = 0;

	if (n > EFS_CHUNK + 1024)
		return -1;
	for (i = 0; i < n; i++)
		k += hdlc_put(o + k, p[i]);
	k += hdlc_put(o + k, c & 0xff);
	k += hdlc_put(o + k, c >> 8);
	o[k++] = 0x7e;
	return tx(o, k);
}

static uint8_t rbuf[16384];
static int rlen;

/* next complete frame with a good crc, payload without crc; -1 on timeout */
static int recv_pkt(uint8_t *out, int max, long deadline)
{
	for (;;) {
		uint8_t *flag = memchr(rbuf, 0x7e, rlen);

		if (flag) {
			int flen = flag - rbuf, k, n = 0, esc = 0;

			for (k = 0; k < flen; k++) {
				uint8_t b = rbuf[k];

				if (esc) {
					b ^= 0x20;
					esc = 0;
				} else if (b == 0x7d) {
					esc = 1;
					continue;
				}
				if (n < max)
					out[n++] = b;
			}
			rlen -= flen + 1;
			memmove(rbuf, flag + 1, rlen);
			if (n >= 3 && crc16(out, n - 2) == (out[n - 2] | out[n - 1] << 8))
				return n - 2;
			continue;	/* empty or damaged frame, try the next one */
		}

		long left = deadline - now_ms();
		int r;

		if (left <= 0 || rlen >= (int)sizeof(rbuf))
			return -1;
		r = rx(rbuf + rlen, sizeof(rbuf) - rlen, (int)left);
		if (r < 0)
			return -1;
		rlen += r;
	}
}

static const char *diag_err(uint8_t c)
{
	switch (c) {
	case DIAG_BAD_CMD_F: return "command not supported";
	case DIAG_BAD_PARM_F: return "bad parameter";
	case DIAG_BAD_LEN_F: return "bad length";
	case DIAG_BAD_MODE_F: return "phone is in the wrong mode";
	case DIAG_BAD_SPC_MODE_F: return "locked, send the SPC first";
	}
	return NULL;
}

/* send a request and wait for the reply to it, log packets are skipped */
static int xfer(const uint8_t *req, int n, uint8_t *rsp, int max)
{
	long end = now_ms() + tmo;

	if (send_pkt(req, n)) {
		fprintf(stderr, "qcdiag: write failed\n");
		return -1;
	}
	for (;;) {
		int r = recv_pkt(rsp, max, end);

		if (r < 0) {
			fprintf(stderr, "qcdiag: no answer (is the port in DIAG mode?)\n");
			return -1;
		}
		if (diag_err(rsp[0]) && r > 1 && rsp[1] == req[0]) {
			fprintf(stderr, "qcdiag: %s\n", diag_err(rsp[0]));
			return -1;
		}
		if (rsp[0] != req[0])
			continue;
		if (req[0] == DIAG_SUBSYS_CMD_F &&
		    (r < 4 || rsp[1] != req[1] || rsp[2] != req[2] || rsp[3] != req[3]))
			continue;
		return r;
	}
}

/* ---- helpers --------------------------------------------------------- */

static void put16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t *p, uint32_t v) { put16(p, v); put16(p + 2, v >> 16); }
static uint16_t get16(const uint8_t *p) { return p[0] | p[1] << 8; }
static uint32_t get32(const uint8_t *p) { return get16(p) | (uint32_t)get16(p + 2) << 16; }

static void hexdump(const uint8_t *p, int n)
{
	int i, k;

	for (i = 0; i < n; i += 16) {
		printf("%04x ", i);
		for (k = 0; k < 16; k++) {
			if (i + k < n)
				printf(" %02x", p[i + k]);
			else
				printf("   ");
		}
		printf("  ");
		for (k = 0; k < 16 && i + k < n; k++)
			putchar(isprint(p[i + k]) ? p[i + k] : '.');
		putchar('\n');
	}
}

static int parse_hex(int argc, char **argv, uint8_t *out, int max)
{
	int n = 0, i;

	for (i = 0; i < argc; i++) {
		const char *s = argv[i];

		if (!strncasecmp(s, "0x", 2))
			s += 2;
		/* accept "0a0b0c" as well as "0a 0b 0c" */
		while (*s) {
			unsigned v;

			if (!isxdigit(s[0]) || !isxdigit(s[1]) || sscanf(s, "%2x", &v) != 1 || n >= max)
				return -1;
			out[n++] = v;
			s += 2;
		}
	}
	return n;
}

static int is_identity_nv(unsigned id)
{
	return id == 0 || id == 550 || id == 1943;	/* ESN, IMEI, MEID */
}

static int is_identity_path(const char *p)
{
	const char *b = strrchr(p, '/');

	b = b ? b + 1 : p;
	return !strcmp(b, "0") || !strcmp(b, "550") || !strcmp(b, "1943") ||
	       strcasestr(p, "imei") || strcasestr(p, "meid") || strcasestr(p, "/esn");
}

/* ---- commands -------------------------------------------------------- */

static int cmd_info(void)
{
	uint8_t q[1] = { DIAG_EXT_BUILD_ID_F }, r[1024];
	int n = xfer(q, 1, r, sizeof(r)), i;

	if (n < 0) {
		q[0] = DIAG_VERNO_F;
		n = xfer(q, 1, r, sizeof(r));
		if (n < 0)
			return 1;
		printf("verno ");
		for (i = 1; i < n; i++)
			putchar(isprint(r[i]) ? r[i] : ' ');
		putchar('\n');
		return 0;
	}
	if (n >= 12)
		printf("msm_hw %08x  model %08x\n", get32(r + 4), get32(r + 8));
	for (i = 12; i < n;) {
		const char *s = (const char *)r + i;
		int l = strnlen(s, n - i);

		if (l)
			printf("%s %.*s\n", i == 12 ? "build" : "model", l, s);
		i += l + 1;
	}
	return 0;
}

static const char *nv_status(uint16_t s)
{
	static const char *const t[] = {
		"done", "busy", "bad command", "full", "failed", "not set",
		"bad parameter", "read only", "bad target", "no memory", "not allocated"
	};
	return s < sizeof(t) / sizeof(*t) ? t[s] : "unknown";
}

static int cmd_nv(int argc, char **argv)
{
	uint8_t q[3 + NV_SIZE + 2] = { 0 }, r[512];
	unsigned long id;
	char *e;
	int n, w;

	if (argc < 2)
		return -1;
	w = !strcmp(argv[0], "write");
	if (!w && strcmp(argv[0], "read"))
		return -1;
	id = strtoul(argv[1], &e, 0);
	if (*e || id > 0xffff) {
		fprintf(stderr, "qcdiag: bad item id\n");
		return 1;
	}
	if (w && is_identity_nv(id)) {
		fprintf(stderr, "qcdiag: item %lu is a device identity, not touching it\n", id);
		return 1;
	}
	q[0] = w ? DIAG_NV_WRITE_F : DIAG_NV_READ_F;
	put16(q + 1, id);
	if (w && parse_hex(argc - 2, argv + 2, q + 3, NV_SIZE) < 0) {
		fprintf(stderr, "qcdiag: data must be hex bytes, %d max\n", NV_SIZE);
		return 1;
	}

	n = xfer(q, sizeof(q), r, sizeof(r));
	if (n < (int)sizeof(q)) {
		if (n >= 0)
			fprintf(stderr, "qcdiag: short reply (%d)\n", n);
		return 1;
	}
	if (get16(r + 3 + NV_SIZE)) {
		fprintf(stderr, "qcdiag: item %lu: %s\n", id, nv_status(get16(r + 3 + NV_SIZE)));
		return 2;
	}
	if (w) {
		printf("item %lu written\n", id);
	} else {
		int len = NV_SIZE;

		while (len > 1 && !r[3 + len - 1])
			len--;
		hexdump(r + 3, len);
	}
	return 0;
}

static int cmd_spc(const char *code)
{
	uint8_t q[7] = { DIAG_SPC_F }, r[64];
	int n;

	if (strlen(code) != 6) {
		fprintf(stderr, "qcdiag: SPC is 6 digits\n");
		return 1;
	}
	memcpy(q + 1, code, 6);
	n = xfer(q, sizeof(q), r, sizeof(r));
	if (n < 2)
		return 1;
	puts(r[1] ? "SPC accepted" : "SPC rejected");
	return r[1] ? 0 : 2;
}

static int efs_req(uint8_t *q, uint16_t cmd)
{
	q[0] = DIAG_SUBSYS_CMD_F;
	q[1] = SUBSYS_EFS;
	put16(q + 2, cmd);
	return 4;
}

static void efs_hello(void)
{
	uint8_t q[4 + 40], r[128];
	int n = efs_req(q, EFS_HELLO), i;
	static const uint32_t v[10] = {
		0x100000, 0x100000, 0x100000, 0x100000, 0x100000, 0x100000, 1, 1, 1, 0xffffffff
	};

	for (i = 0; i < 10; i++, n += 4)
		put32(q + n, v[i]);
	/* older basebands choke on HELLO, just ignore whatever comes back */
	xfer(q, n, r, sizeof(r));
}

static int efs_open(const char *path, uint32_t flags, uint32_t mode)
{
	uint8_t q[600], r[64];
	int n = efs_req(q, EFS_OPEN), l = strlen(path) + 1;

	if (l > 512)
		return -1;
	put32(q + n, flags);
	put32(q + n + 4, mode);
	memcpy(q + n + 8, path, l);
	n = xfer(q, n + 8 + l, r, sizeof(r));
	if (n < 12)
		return -1;
	if (get32(r + 8)) {
		fprintf(stderr, "qcdiag: open %s: %s\n", path, strerror(get32(r + 8)));
		return -1;
	}
	return (int)get32(r + 4);
}

static void efs_close(int h)
{
	uint8_t q[8], r[64];
	int n = efs_req(q, EFS_CLOSE);

	put32(q + n, h);
	xfer(q, n + 4, r, sizeof(r));
}

static int cmd_efs_get(const char *path, const char *out)
{
	uint8_t q[16], r[EFS_CHUNK + 64];
	FILE *f = stdout;
	uint32_t off = 0;
	int h = efs_open(path, 0, 0);

	if (h < 0)
		return 1;
	if (out && !(f = fopen(out, "wb"))) {
		perror(out);
		efs_close(h);
		return 1;
	}
	for (;;) {
		int n = efs_req(q, EFS_READ), got;

		put32(q + n, h);
		put32(q + n + 4, EFS_CHUNK);
		put32(q + n + 8, off);
		n = xfer(q, n + 12, r, sizeof(r));
		if (n < 20 || get32(r + 16)) {
			fprintf(stderr, "qcdiag: read %s failed at %u\n", path, off);
			break;
		}
		got = (int)get32(r + 12);
		if (got <= 0)
			break;
		fwrite(r + 20, 1, got, f);
		off += got;
	}
	efs_close(h);
	if (f != stdout)
		fclose(f);
	fprintf(stderr, "%u bytes\n", off);
	return 0;
}

static int cmd_efs_put(const char *path, const char *in)
{
	uint8_t q[EFS_CHUNK + 32], r[64], buf[EFS_CHUNK];
	uint32_t off = 0;
	size_t got;
	FILE *f;
	int h;

	if (is_identity_path(path)) {
		fprintf(stderr, "qcdiag: %s looks like a device identity, not touching it\n", path);
		return 1;
	}
	if (!(f = fopen(in, "rb"))) {
		perror(in);
		return 1;
	}
	/* O_WRONLY | O_CREAT | O_TRUNC, rw-r--r-- */
	h = efs_open(path, 01 | 0100 | 01000, 0644);
	if (h < 0) {
		fclose(f);
		return 1;
	}
	while ((got = fread(buf, 1, sizeof(buf), f)) > 0) {
		int n = efs_req(q, EFS_WRITE);

		put32(q + n, h);
		put32(q + n + 4, off);
		memcpy(q + n + 8, buf, got);
		n = xfer(q, n + 8 + got, r, sizeof(r));
		if (n < 20 || get32(r + 16) || get32(r + 12) != got) {
			fprintf(stderr, "qcdiag: write %s failed at %u\n", path, off);
			efs_close(h);
			fclose(f);
			return 1;
		}
		off += got;
	}
	efs_close(h);
	fclose(f);
	printf("%s: %u bytes written\n", path, off);
	return 0;
}

static int cmd_efs_stat(const char *path)
{
	uint8_t q[600], r[64];
	int n = efs_req(q, EFS_STAT), l = strlen(path) + 1;

	if (l > 512)
		return 1;
	memcpy(q + n, path, l);
	n = xfer(q, n + l, r, sizeof(r));
	if (n < 32)
		return 1;
	if (get32(r + 4)) {
		fprintf(stderr, "qcdiag: %s: %s\n", path, strerror(get32(r + 4)));
		return 2;
	}
	printf("mode %06o size %u nlink %u mtime %u\n", get32(r + 8), get32(r + 12),
	       get32(r + 16), get32(r + 24));
	return 0;
}

static int cmd_efs_ls(const char *path)
{
	uint8_t q[600], r[700];
	int n = efs_req(q, EFS_OPENDIR), l = strlen(path) + 1, seq;
	uint32_t dir;

	if (l > 512)
		return 1;
	memcpy(q + n, path, l);
	n = xfer(q, n + l, r, sizeof(r));
	if (n < 12)
		return 1;
	if (get32(r + 8)) {
		fprintf(stderr, "qcdiag: %s: %s\n", path, strerror(get32(r + 8)));
		return 2;
	}
	dir = get32(r + 4);

	for (seq = 1;; seq++) {
		static const char tc[] = "-dli";
		uint32_t type;

		n = efs_req(q, EFS_READDIR);
		put32(q + n, dir);
		put32(q + n + 4, seq);
		n = xfer(q, n + 8, r, sizeof(r));
		if (n < 41 || get32(r + 12) || !r[40])
			break;
		type = get32(r + 16);
		printf("%c %06o %8u  %.*s\n", type < 4 ? tc[type] : '?', get32(r + 20),
		       get32(r + 24), n - 40, (char *)r + 40);
	}

	n = efs_req(q, EFS_CLOSEDIR);
	put32(q + n, dir);
	xfer(q, n + 4, r, sizeof(r));
	return 0;
}

static int cmd_raw(int argc, char **argv)
{
	uint8_t q[1024], r[4096];
	int n = parse_hex(argc, argv, q, sizeof(q));

	if (n <= 0) {
		fprintf(stderr, "qcdiag: raw wants hex bytes\n");
		return 1;
	}
	if (q[0] == DIAG_NV_WRITE_F && n >= 3 && is_identity_nv(get16(q + 1))) {
		fprintf(stderr, "qcdiag: not writing identity items, raw or not\n");
		return 1;
	}
	n = xfer(q, n, r, sizeof(r));
	if (n < 0)
		return 1;
	hexdump(r, n);
	return 0;
}

/* ---- main ------------------------------------------------------------ */

static void usage(void)
{
	fputs("usage: qcdiag [-d tty | -u [vid:pid]] [-i iface] [-t sec] <command>\n"
	      "  info                     build id of the modem\n"
	      "  spc <6 digits>           unlock items that need the service code\n"
	      "  nv read <id>\n"
	      "  nv write <id> <hex...>   up to 128 bytes, rest is zero\n"
	      "  efs ls <dir>\n"
	      "  efs stat <path>\n"
	      "  efs get <path> [file]    stdout if no file\n"
	      "  efs put <path> <file>\n"
	      "  raw <hex...>             any diag packet, reply as hexdump\n"
	      "default transport is libusb: first vendor interface that is not adb\n", stderr);
}

static int open_tty(const char *path)
{
	struct termios t;

	fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "qcdiag: %s: %s\n", path, strerror(errno));
		return -1;
	}
	if (tcgetattr(fd, &t) == 0) {
		cfmakeraw(&t);
		cfsetispeed(&t, B115200);
		cfsetospeed(&t, B115200);
		t.c_cflag |= CLOCAL | CREAD;
		tcsetattr(fd, TCSANOW, &t);
		tcflush(fd, TCIOFLUSH);
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *dev = NULL, *usbid = NULL;
	int iface = -1, o, res;

	(void)iface;

	while ((o = getopt(argc, argv, "+d:u::i:t:h")) != -1) {
		switch (o) {
		case 'd': dev = optarg; break;
		case 'u': usbid = optarg; break;
		case 'i': iface = atoi(optarg); break;
		case 't': tmo = atoi(optarg) * 1000; break;
		default: usage(); return o == 'h' ? 0 : 1;
		}
	}
	if (optind < argc && strchr(argv[optind], ':') && !usbid && !dev)
		usbid = argv[optind++];
	argc -= optind;
	argv += optind;
	if (argc < 1) {
		usage();
		return 1;
	}
	crc_init();

	if (dev) {
		if (open_tty(dev))
			return 1;
	} else {
#ifdef HAVE_LIBUSB
		int vid, pid;

		if (usbio_parse_id(usbid, &vid, &pid)) {
			fprintf(stderr, "qcdiag: bad vid:pid\n");
			return 1;
		}
		if (usbio_open(&usb, vid, pid, iface, iface < 0 ? 0xff : -1, -1, -1)) {
			fprintf(stderr, "qcdiag: no DIAG interface found (fb modem diag on, then replug)\n");
			return 1;
		}
		use_usb = 1;
#else
		fprintf(stderr, "qcdiag: built without libusb, use -d\n");
		return 1;
#endif
	}

	if (!strcmp(argv[0], "info"))
		res = cmd_info();
	else if (!strcmp(argv[0], "spc") && argc == 2)
		res = cmd_spc(argv[1]);
	else if (!strcmp(argv[0], "nv"))
		res = cmd_nv(argc - 1, argv + 1);
	else if (!strcmp(argv[0], "efs") && argc >= 3) {
		efs_hello();
		if (!strcmp(argv[1], "ls"))
			res = cmd_efs_ls(argv[2]);
		else if (!strcmp(argv[1], "stat"))
			res = cmd_efs_stat(argv[2]);
		else if (!strcmp(argv[1], "get"))
			res = cmd_efs_get(argv[2], argc > 3 ? argv[3] : NULL);
		else if (!strcmp(argv[1], "put") && argc == 4)
			res = cmd_efs_put(argv[2], argv[3]);
		else
			res = -1;
	} else if (!strcmp(argv[0], "raw"))
		res = cmd_raw(argc - 1, argv + 1);
	else
		res = -1;

	if (res < 0) {
		usage();
		res = 1;
	}
#ifdef HAVE_LIBUSB
	if (use_usb)
		usbio_close(&usb);
#endif
	if (fd >= 0)
		close(fd);
	return res;
}
