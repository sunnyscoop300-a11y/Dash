// Hurtig Sokoban-løser (færrest skub, BFS) til BoxDog-banegeneratoren.
// Læser baner fra stdin, adskilt af tomme linjer; skriver én linje pr. bane:
//   <skub> <stillinger>     eller   -1 <stillinger>  (ingen løsning / grænse)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MAXC 128
typedef struct { uint64_t a, b; uint8_t p; } st;

static int W, H, N;
static uint8_t wall[MAXC], goal[MAXC], live[MAXC];
static int nb[MAXC][4];
static const int DX[4] = {1, -1, 0, 0}, DY[4] = {0, 0, 1, -1};

static inline int has(const st *s, int c) { return c < 64 ? (s->a >> c) & 1 : (s->b >> (c - 64)) & 1; }
static inline void setb(st *s, int c) { if (c < 64) s->a |= 1ULL << c; else s->b |= 1ULL << (c - 64); }
static inline void clrb(st *s, int c) { if (c < 64) s->a &= ~(1ULL << c); else s->b &= ~(1ULL << (c - 64)); }

static uint64_t LIMIT = 6000000;
static st *tab; static uint8_t *brugt; static uint64_t cap;
static st *kø; static uint64_t kh, kt;

static inline uint64_t hsh(const st *s) {
	uint64_t h = s->a * 0x9E3779B97F4A7C15ULL ^ (s->b + 0x632BE59BD9B4E019ULL) * 0xC2B2AE3D27D4EB4FULL ^ s->p * 0x165667B19E3779F9ULL;
	return h ^ (h >> 29);
}
static int indsæt(const st *s) {
	uint64_t i = hsh(s) & (cap - 1);
	while (brugt[i]) {
		if (tab[i].a == s->a && tab[i].b == s->b && tab[i].p == s->p) return 0;
		i = (i + 1) & (cap - 1);
	}
	brugt[i] = 1; tab[i] = *s; return 1;
}

static uint8_t rset[MAXC]; static int stak[MAXC];
static int region(const st *s, int p) {   // fylder rset, giver mindste felt
	memset(rset, 0, N); int n = 0, m = p; stak[n++] = p; rset[p] = 1;
	while (n) {
		int c = stak[--n]; if (c < m) m = c;
		for (int d = 0; d < 4; d++) {
			int q = nb[c][d];
			if (q < 0 || wall[q] || rset[q] || has(s, q)) continue;
			rset[q] = 1; stak[n++] = q;
		}
	}
	return m;
}
static int fast(const st *s, int c) {      // 2x2-blok af mur/kasser uden for mål
	int x = c % W, y = c / W;
	for (int ox = -1; ox <= 0; ox++) for (int oy = -1; oy <= 0; oy++) {
		int ok = 1, udenmål = 0;
		for (int i = 0; i < 2 && ok; i++) for (int j = 0; j < 2; j++) {
			int xx = x + ox + i, yy = y + oy + j;
			if (xx < 0 || yy < 0 || xx >= W || yy >= H) { ok = 0; break; }
			int q = yy * W + xx;
			if (wall[q]) continue;
			if (has(s, q)) { if (!goal[q]) udenmål = 1; continue; }
			ok = 0; break;
		}
		if (ok && udenmål) return 1;
	}
	return 0;
}

static void løs(char rows[][MAXC], int h) {
	H = h; W = 0;
	for (int y = 0; y < h; y++) { int l = strlen(rows[y]); if (l > W) W = l; }
	N = W * H;
	if (N > MAXC) { printf("-2 0\n"); return; }
	st s0 = {0, 0, 0}; int p0 = -1, ng = 0, nbx = 0;
	for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
		int c = y * W + x; char ch = x < (int)strlen(rows[y]) ? rows[y][x] : ' ';
		wall[c] = ch == '#' || ch == 'H'; goal[c] = ch == '.' || ch == '*' || ch == '+';
		if (ch == '$' || ch == '*') { setb(&s0, c); nbx++; }
		if (ch == '@' || ch == '+') p0 = c;
		ng += goal[c];
		for (int d = 0; d < 4; d++) {
			int xx = x + DX[d], yy = y + DY[d];
			nb[c][d] = (xx < 0 || yy < 0 || xx >= W || yy >= H) ? -1 : yy * W + xx;
		}
	}
	if (p0 < 0 || ng != nbx) { printf("-3 0\n"); return; }
	// levende felter: en kasse kan trækkes fra et mål hertil
	memset(live, 0, N); int n = 0;
	for (int c = 0; c < N; c++) if (goal[c]) { live[c] = 1; stak[n++] = c; }
	while (n) {
		int c = stak[--n];
		for (int d = 0; d < 4; d++) {
			int q = nb[c][d]; if (q < 0 || wall[q] || live[q]) continue;
			int r = nb[q][d]; if (r < 0 || wall[r]) continue;
			live[q] = 1; stak[n++] = q;
		}
	}
	st mål = {0, 0, 0};
	for (int c = 0; c < N; c++) if (goal[c]) setb(&mål, c);
	for (int c = 0; c < N; c++) if (has(&s0, c) && !live[c]) { printf("-1 0\n"); return; }

	memset(brugt, 0, cap);
	kh = kt = 0;
	s0.p = region(&s0, p0);
	indsæt(&s0); kø[kt++] = s0;
	uint64_t lag_slut = kt; int dybde = 0, antal = 1;
	while (kh < kt) {
		if (kh == lag_slut) { dybde++; lag_slut = kt; }
		st s = kø[kh++];
		if (s.a == mål.a && s.b == mål.b) { printf("%d %d\n", dybde, antal); return; }
		region(&s, s.p);
		uint8_t r[MAXC]; memcpy(r, rset, N);
		for (int c = 0; c < N; c++) {
			if (!has(&s, c)) continue;
			for (int d = 0; d < 4; d++) {
				int t = nb[c][d], pl = nb[c][d ^ 1];
				if (t < 0 || pl < 0 || !r[pl] || wall[t] || has(&s, t) || !live[t]) continue;
				st ns = s; clrb(&ns, c); setb(&ns, t);
				if (!goal[t] && fast(&ns, t)) continue;
				ns.p = region(&ns, c);
				if (indsæt(&ns)) {
					antal++;
					if ((uint64_t)antal > LIMIT) { printf("-1 %d\n", antal); return; }
					kø[kt++] = ns;
				}
			}
		}
	}
	printf("-1 %d\n", antal);
}

int main(int argc, char **argv) {
	if (argc > 1) LIMIT = strtoull(argv[1], 0, 10);
	cap = 1; while (cap < LIMIT * 2) cap <<= 1;
	tab = malloc(cap * sizeof(st)); brugt = malloc(cap); kø = malloc((LIMIT + 64) * sizeof(st));
	static char rows[64][MAXC]; int h = 0; char line[512];
	while (fgets(line, sizeof line, stdin)) {
		line[strcspn(line, "\n")] = 0;
		if (line[0] == 0) { if (h) { løs(rows, h); fflush(stdout); h = 0; } continue; }
		strncpy(rows[h], line, MAXC - 1); rows[h][MAXC - 1] = 0; h++;
	}
	if (h) løs(rows, h);
	return 0;
}
