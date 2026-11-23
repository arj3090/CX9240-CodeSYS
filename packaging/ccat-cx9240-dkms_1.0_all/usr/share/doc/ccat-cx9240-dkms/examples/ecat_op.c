// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Manufacturing Automation, LLC
/* ecat_op.c - minimal EtherCAT master bring-up for ONE EL2008 on the CX9240 internal bus.
 * EEPROM identity, INIT->PREOP->SAFEOP->OP, cyclic LWR process data. Outputs are held at 0
 * unless a value is given: sudo ./ecat_op eth0 [seconds] [output_byte_hex]
 * Build: gcc -O2 -o ecat_op ecat_op.c */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>

enum { APRD = 1, APWR = 2, FPRD = 4, FPWR = 5, BRD = 7, BWR = 8, LWR = 0x0B };
static int s; static uint8_t mac[6], idx; static long lost;
static int dg(uint8_t cmd, uint16_t adp, uint16_t ado, uint8_t *d, int dlen)
{
	uint8_t f[128], r[1600]; int flen = 26 + dlen + 2, n, t;
	memset(f, 0, sizeof f); memset(f, 0xff, 6); memcpy(f + 6, mac, 6); f[12] = 0x88; f[13] = 0xA4;
	uint16_t el = ((12 + dlen) & 0x7ff) | (1 << 12); f[14] = el; f[15] = el >> 8;
	f[16] = cmd; f[17] = ++idx; f[18] = adp; f[19] = adp >> 8; f[20] = ado; f[21] = ado >> 8; f[22] = dlen;
	memcpy(f + 26, d, dlen);
	if (flen < 60) flen = 60;
	if (send(s, f, flen, 0) < 0) return -1;
	for (t = 0; t < 4; t++) {
		n = recv(s, r, sizeof r, 0);
		if (n < 28 + dlen) break;
		if (r[12] == 0x88 && r[13] == 0xA4 && r[17] == idx) {
			memcpy(d, r + 26, dlen); return r[26 + dlen] | (r[27 + dlen] << 8);
		}
	}
	lost++; return -2;
}
static int rd16(uint16_t st, uint16_t ado) { uint8_t d[2] = {0}; dg(FPRD, st, ado, d, 2); return d[0] | d[1] << 8; }
static uint32_t eeprom(uint16_t st, uint16_t word)
{
	uint8_t d[6] = {0x00, 0x01, word, word >> 8, 0, 0}; int i;
	dg(FPWR, st, 0x0502, d, 6);
	for (i = 0; i < 100 && (rd16(st, 0x0502) & 0x8000); i++) usleep(1000);
	memset(d, 0, 4); dg(FPRD, st, 0x0508, d, 4);
	return d[0] | d[1] << 8 | d[2] << 16 | (uint32_t)d[3] << 24;
}
static int state(uint16_t st, uint8_t want)
{
	uint8_t d[2] = {want, 0}; int i, al = 0;
	dg(FPWR, st, 0x0120, d, 2);
	for (i = 0; i < 300; i++) { al = rd16(st, 0x0130); if ((al & 0x1f) == want) break; usleep(2000); }
	printf("  AL request 0x%02x -> status 0x%04x%s", want, al, (al & 0x1f) == want ? "  OK\n" : "  FAILED");
	if ((al & 0x1f) != want) printf(" (AL status code 0x%04x)\n", rd16(st, 0x0134));
	return (al & 0x1f) == want;
}
int main(int argc, char **argv)
{
	const char *ifn = argc > 1 ? argv[1] : "eth0";
	int secs = argc > 2 ? atoi(argv[2]) : 5; uint8_t outv = argc > 3 ? strtoul(argv[3], 0, 16) : 0;
	const uint16_t ST = 0x1001;
	struct ifreq ifr; struct sockaddr_ll sll = {0}; struct timeval tv = {0, 100000};
	uint8_t d[32]; int w, i;
	s = socket(AF_PACKET, SOCK_RAW, htons(0x88A4)); if (s < 0) { perror("socket"); return 1; }
	strncpy(ifr.ifr_name, ifn, IFNAMSIZ - 1); ioctl(s, SIOCGIFINDEX, &ifr);
	sll.sll_family = AF_PACKET; sll.sll_ifindex = ifr.ifr_ifindex; sll.sll_protocol = htons(0x88A4);
	bind(s, (struct sockaddr *)&sll, sizeof sll);
	ioctl(s, SIOCGIFHWADDR, &ifr); memcpy(mac, ifr.ifr_hwaddr.sa_data, 6);
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

	memset(d, 0, 2); w = dg(BRD, 0, 0x0000, d, 2); printf("slaves on bus (BRD wkc): %d\n", w);
	if (w != 1) { printf("expected exactly 1 slave\n"); return 2; }
	d[0] = 0x11; d[1] = 0; dg(BWR, 0, 0x0120, d, 2);                 /* INIT + error ack */
	memset(d, 0, 32); dg(BWR, 0, 0x0600, d, 32); memset(d, 0, 32); dg(BWR, 0, 0x0800, d, 32);
	d[0] = ST & 0xff; d[1] = ST >> 8; w = dg(APWR, 0, 0x0010, d, 2); printf("set station address 0x%04x: wkc=%d\n", ST, w);
	usleep(20000);
	printf("EEPROM: vendor=0x%08x product=0x%08x revision=0x%08x serial=0x%08x\n",
	       eeprom(ST, 8), eeprom(ST, 10), eeprom(ST, 12), eeprom(ST, 14));
	if (!state(ST, 0x01)) return 3;
	{ uint8_t sm[8] = {0x00, 0x0F, 0x01, 0x00, 0x44, 0x00, 0x01, 0x00}; w = dg(FPWR, ST, 0x0800, sm, 8); printf("SM0 (0x0F00 len 1 out): wkc=%d\n", w); }
	if (!state(ST, 0x02)) return 4;
	{ uint8_t fm[16] = {0,0,0,0, 1,0, 0, 7, 0x00,0x0F, 0, 0x02, 0x01, 0,0,0}; w = dg(FPWR, ST, 0x0600, fm, 16); printf("FMMU0 (logical 0 -> 0x0F00): wkc=%d\n", w); }
	if (!state(ST, 0x04)) return 5;
	/* SAFEOP->OP needs valid outputs flowing: request OP, then cycle LWR */
	d[0] = 0x08; d[1] = 0; dg(FPWR, ST, 0x0120, d, 2);
	{
		long n = 0, good = 0, cyc = (long)secs * 500; int al = 0; struct timespec a, b; long maxus = 0;
		for (n = 0; n < cyc; n++) {
			uint8_t o = outv;
			clock_gettime(CLOCK_MONOTONIC, &a);
			w = dg(LWR, 0, 0, &o, 1);          /* logical address 0 */
			clock_gettime(CLOCK_MONOTONIC, &b);
			long us = (b.tv_sec - a.tv_sec) * 1000000L + (b.tv_nsec - a.tv_nsec) / 1000; if (us > maxus) maxus = us;
			if (w == 1) good++;
			if (n == 250) { al = rd16(ST, 0x0130); printf("  AL status after 0.5 s of process data: 0x%04x %s\n", al, (al & 0x1f) == 8 ? "= OPERATIONAL" : "(not OP)"); }
			usleep(2000 - (us < 1900 ? us : 1900));
		}
		al = rd16(ST, 0x0130);
		printf("cyclic LWR 2 ms x%ld (output byte 0x%02x): wkc==1 on %ld, lost frames %ld, worst round trip %ld us, final AL 0x%04x\n",
		       cyc, outv, good, lost, maxus, al);
	}
	{ uint8_t o = 0; dg(LWR, 0, 0, &o, 1); }
	state(ST, 0x01);
	return 0;
}
