/*
 * pacextractor - extract partitions from Unisoc/Spreadtrum .pac firmware files.
 *
 *   pacextractor list firmware.pac
 *   pacextractor extract firmware.pac [output_dir]
 *   pacextractor extract firmware.pac -p boot,system [output_dir]
 *
 * The PAC format is a simple concatenation with a fixed-size header table.
 * @Dev_DcS
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>	/* strncasecmp */

#define PAC_MAGIC 0xFFFAFFFA
#define MAX_PARTS 128

#pragma pack(push, 1)
struct pac_header {
	uint32_t version;
	uint32_t size;          /* total pac size */
	uint16_t product[256];  /* UTF-16LE product name */
	uint16_t firmware[256]; /* UTF-16LE firmware version */
	uint32_t part_count;
	uint32_t part_offset;   /* offset of first file_header */
	uint32_t mode;
	uint32_t magic;         /* PAC_MAGIC */
	uint16_t reserved[214];
	uint32_t crc;
};

struct file_header {
	uint32_t length;        /* sizeof this struct */
	uint16_t id[256];
	uint16_t name[256];
	uint16_t unused[512];
	uint32_t size;          /* file size in bytes */
	uint32_t type;
	uint32_t flag;
	uint32_t data_offset;   /* absolute offset in .pac */
	uint32_t check;
	uint16_t reserved[124];
};
#pragma pack(pop)

/* UTF-16LE → ASCII, lossy; buf must be at least n+1 bytes */
static void u16_to_ascii(char *dst, const uint16_t *src, int n)
{
	int i;

	for (i = 0; i < n && src[i]; i++)
		dst[i] = (src[i] < 128) ? (char)src[i] : '?';
	dst[i] = 0;
}

static int want(const char *name, const char *filter)
{
	const char *p, *q;
	size_t n;

	if (!filter || !*filter)
		return 1;
	p = filter;
	n = strlen(name);
	while (*p) {
		q = strchr(p, ',');
		if (!q)
			q = p + strlen(p);
		if ((size_t)(q - p) == n && !strncasecmp(p, name, n))
			return 1;
		p = *q ? q + 1 : q;
	}
	return 0;
}

static int extract_file(FILE *fp, const struct file_header *fh, const char *outdir,
			 const char *name)
{
	FILE *out;
	char path[1024];
	uint8_t buf[65536];
	uint32_t left;

	snprintf(path, sizeof(path), "%s/%s", outdir, name);
	out = fopen(path, "wb");
	if (!out) {
		fprintf(stderr, "  %s: %s\n", path, strerror(errno));
		return -1;
	}
	if (fseek(fp, fh->data_offset, SEEK_SET)) {
		fprintf(stderr, "  %s: seek to %u failed\n", name, fh->data_offset);
		fclose(out);
		return -1;
	}
	left = fh->size;
	while (left) {
		size_t chunk = left < sizeof(buf) ? left : sizeof(buf);
		size_t r = fread(buf, 1, chunk, fp);

		if (r != chunk) {
			fprintf(stderr, "  %s: short read at offset %u\n", name,
				fh->data_offset + fh->size - left);
			fclose(out);
			return -1;
		}
		fwrite(buf, 1, r, out);
		left -= r;
	}
	fclose(out);
	return 0;
}

int main(int argc, char **argv)
{
	struct pac_header hdr;
	struct file_header fh;
	FILE *fp;
	const char *cmd, *file, *outdir = ".", *filter = NULL;
	char name[260], id[260];
	uint32_t i, off;
	int do_extract;

	if (argc < 3) {
		fprintf(stderr, "usage: pacextractor list|extract <file.pac> [-p parts] [outdir]\n");
		return 1;
	}
	cmd = argv[1];
	file = argv[2];
	if (!strcmp(cmd, "list"))
		do_extract = 0;
	else if (!strcmp(cmd, "extract"))
		do_extract = 1;
	else {
		fprintf(stderr, "pacextractor: unknown command '%s'\n", cmd);
		return 1;
	}
	for (i = 3; i < (uint32_t)argc; i++) {
		if (!strcmp(argv[i], "-p") && i + 1 < (uint32_t)argc)
			filter = argv[++i];
		else
			outdir = argv[i];
	}

	fp = fopen(file, "rb");
	if (!fp) {
		fprintf(stderr, "pacextractor: %s: %s\n", file, strerror(errno));
		return 1;
	}
	if (fread(&hdr, sizeof(hdr), 1, fp) != 1) {
		fprintf(stderr, "pacextractor: %s: too small for a PAC header\n", file);
		fclose(fp);
		return 1;
	}
	if (hdr.magic != PAC_MAGIC) {
		fprintf(stderr, "pacextractor: %s: not a PAC file (magic %08x)\n", file, hdr.magic);
		fclose(fp);
		return 1;
	}
	u16_to_ascii(name, hdr.product, 255);
	printf("product  %s\n", name);
	u16_to_ascii(name, hdr.firmware, 255);
	printf("firmware %s\n", name);
	printf("parts    %u\n\n", hdr.part_count);

	if (hdr.part_count > MAX_PARTS)
		hdr.part_count = MAX_PARTS;

	off = hdr.part_offset;
	for (i = 0; i < hdr.part_count; i++) {
		if (fseek(fp, off, SEEK_SET) || fread(&fh, sizeof(fh), 1, fp) != 1)
			break;
		u16_to_ascii(name, fh.name, 255);
		u16_to_ascii(id, fh.id, 255);

		if (!do_extract) {
			printf("  %-24s %-24s %10u  offset=%u\n", id, name, fh.size, fh.data_offset);
		} else if (fh.size > 0 && want(id, filter)) {
			printf("  %-24s %u bytes... ", id, fh.size);
			fflush(stdout);
			if (extract_file(fp, &fh, outdir, name[0] ? name : id))
				printf("FAILED\n");
			else
				printf("ok\n");
		}
		off += fh.length ? fh.length : sizeof(fh);
	}

	fclose(fp);
	return 0;
}
