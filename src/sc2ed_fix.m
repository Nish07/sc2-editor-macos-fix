#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/mman.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <sys/sysctl.h>

#define SC2ED_FIX_VERSION "1.2"

/* ================= byte patches ================= */

static const unsigned char sig_gl_gate[] = {
    0x89,0xC8, 0x83,0xC8,0x10, 0x80,0x3A,0x00, 0x0F,0x44,0xC1
};
static const unsigned char rep_gl_gate[] = { 0x90,0x90,0x90 };

typedef struct {
    const char          *name;
    const unsigned char *sig;
    size_t               siglen;
    size_t               patch_off;   /* offset of the bytes to replace, within sig */
    const unsigned char *repl;
    size_t               repllen;
    unsigned long long   hint;        /* known address for the verified build, 0 = scan only */
    int                  done;
    int                  warned;      /* ambiguous-signature warning already logged */
} fix_t;

static fix_t FIXES[] = {
    { "gl-gate (videocard error on launch)",
      sig_gl_gate, sizeof sig_gl_gate, 8, rep_gl_gate, sizeof rep_gl_gate,
      0x1025cea99ULL, 0, 0 },
};
#define NFIXES (sizeof(FIXES)/sizeof(FIXES[0]))

/* ================= call redirects ================= */
/*
 * Some fixes need behaviour, not just different bytes. These rewrite the rel32
 * of a specific `call` so it lands in one of our functions instead. The hook
 * calls the original and adjusts the result.
 */

typedef struct {
    const char          *name;
    const unsigned char *sig;      /* bytes at the call site, starting with E8 */
    size_t               siglen;
    unsigned long long   site;      /* address of the E8 */
    void                *hook;      /* our replacement */
    int                  done;
} hook_t;

/*
 * HOOK 1 -- empty object preview panes.
 *
 * The Editor renders a doodad preview, wraps it in an NSBitmapImageRep, then
 * reads it back. Its readback only understands 24bpp and 32bpp; modern macOS
 * hands it a 64bpp (16-bit-per-channel) rep, so it logs
 *   COpenGLDevice::GetImageBits: *** cannot handle 64bpp images
 * and the preview pane stays empty.
 *
 * Return a 32bpp copy so the Editor's existing 32bpp path handles it. AppKit
 * does the conversion, so this works whatever exotic format macOS returns.
 */
#define MAKE_IMAGE_REP 0x103baa320ULL
typedef id (*mkrep_t)(void *, unsigned, unsigned, unsigned, unsigned, unsigned);

static void logf_(const char *fmt, ...);

static id hk_make_image_rep(void *buf, unsigned a, unsigned b,
                            unsigned c, unsigned d, unsigned e) {
    id result = ((mkrep_t)MAKE_IMAGE_REP)(buf, a, b, c, d, e);
    if (!result) return result;

    /*
     * No @autoreleasepool here on purpose. The replacement must outlive this
     * function -- the Editor keeps using it after we return -- so it has to be
     * autoreleased into the CALLER's pool, not one of ours. Draining a local
     * pool here deallocates it before the Editor touches it.
     */
    @try {
        if (![result isKindOfClass:[NSBitmapImageRep class]]) return result;
        NSBitmapImageRep *src = (NSBitmapImageRep *)result;

        NSInteger bpp = [src bitsPerPixel];
        if (bpp == 24 || bpp == 32) return result;   /* already understood */

        NSInteger w = [src pixelsWide], h = [src pixelsHigh];
        if (w <= 0 || h <= 0) return result;

        NSBitmapImageRep *dst = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:w
                          pixelsHigh:h
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSDeviceRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:32];
        if (!dst) return result;

        NSGraphicsContext *g =
            [NSGraphicsContext graphicsContextWithBitmapImageRep:dst];
        if (!g) { [dst release]; return result; }

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:g];
        [src drawInRect:NSMakeRect(0, 0, (CGFloat)w, (CGFloat)h)];
        [NSGraphicsContext restoreGraphicsState];

        static int once = 0;
        if (!once) { once = 1;
            logf_("sc2ed_fix: converting %ldbpp image previews to 32bpp", (long)bpp); }
        return [dst autorelease];
    } @catch (NSException *ex) {
        logf_("sc2ed_fix: preview conversion failed (%s) - leaving as-is",
              [[ex name] UTF8String]);
        return result;
    }
}

static const unsigned char sig_mkrep[] = { 0xE8,0x51,0xA3,0x5D,0x01, 0x48,0x85,0xC0 };

static hook_t HOOKS[] = {
    { "image-preview (empty object preview panes)",
      sig_mkrep, sizeof sig_mkrep, 0x1025cffcaULL, (void *)hk_make_image_rep, 0 },
};
#define NHOOKS (sizeof(HOOKS)/sizeof(HOOKS[0]))

#define POLL_US     1000     /* 1ms between passes */
#define POLL_PASSES 120000   /* give up after ~120s */
#define SCAN_EVERY  100      /* full __text scan only every Nth pass (see find_site) */

/* ------------------------------------------------------------------ */
static void logf_(const char *fmt, ...) {
    const char *h = getenv("HOME");
    if (!h) return;
    char path[512];
    snprintf(path, sizeof path, "%s/Library/Logs/sc2ed-fix.log", h);
    FILE *f = fopen(path, "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

/* Locate __TEXT,__text of the main executable so we can scan it. */
static int text_range(unsigned char **start, size_t *len) {
    const struct mach_header_64 *mh =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!mh) return 0;
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct load_command *lc = (const struct load_command *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sc =
                (const struct segment_command_64 *)lc;
            if (!strcmp(sc->segname, "__TEXT")) {
                const struct section_64 *s =
                    (const struct section_64 *)(sc + 1);
                for (uint32_t j = 0; j < sc->nsects; j++, s++) {
                    if (!strcmp(s->sectname, "__text")) {
                        *start = (unsigned char *)((uintptr_t)s->addr +
                                                   (uintptr_t)slide);
                        *len   = (size_t)s->size;
                        return 1;
                    }
                }
            }
        }
        lc = (const struct load_command *)((char *)lc + lc->cmdsize);
    }
    return 0;
}

static int write_bytes(unsigned char *at, const unsigned char *b, size_t n) {
    size_t     pagesz = (size_t)getpagesize();
    uintptr_t  base   = (uintptr_t)at & ~(uintptr_t)(pagesz - 1);
    uintptr_t  end    = ((uintptr_t)at + n + pagesz - 1) & ~(uintptr_t)(pagesz - 1);
    size_t     span   = (size_t)(end - base);

    if (mprotect((void *)base, span, PROT_READ | PROT_WRITE) != 0) return 0;
    memcpy(at, b, n);
    if (mprotect((void *)base, span, PROT_READ | PROT_EXEC) != 0)
        logf_("sc2ed_fix: warning - could not restore R+X on %p", (void *)base);
    return 1;
}

/*
 * Try the known address first -- a short compare, safe to run every pass.
 * The __text scan is ~60MB, so it only runs when the caller allows it
 * (every SCAN_EVERY passes); running it every pass would peg a core during
 * the exact seconds the editor is busy decrypting itself.
 */
static unsigned char *find_site(fix_t *f, unsigned char *ts, size_t tl, int allow_scan) {
    if (f->hint) {
        unsigned char *p = (unsigned char *)f->hint;
        if (p >= ts && p + f->siglen <= ts + tl && !memcmp(p, f->sig, f->siglen))
            return p;
    }
    if (!ts || !allow_scan) return NULL;

    unsigned char *hit = NULL;
    int count = 0;
    for (size_t i = 0; i + f->siglen <= tl; i++) {
        if (!memcmp(ts + i, f->sig, f->siglen)) {
            if (!hit) hit = ts + i;
            if (++count > 1) break;
        }
    }
    if (count > 1) {
        if (!f->warned) {
            logf_("sc2ed_fix: [%s] signature is ambiguous (%d+ matches) - refusing to patch",
                  f->name, count);
            f->warned = 1;
        }
        return NULL;
    }
    return hit;
}

/*
 * Redirect a call's rel32 at a known site to our hook.
 *
 * The site is a hardcoded address, so it MUST be bounds-checked against this
 * process's __text before being read. Without that check, loading into any
 * other binary (DYLD_INSERT_LIBRARIES is inherited by child processes) reads
 * an unmapped address and segfaults -- which is exactly what happened to
 * BlizzardBrowser, killing the in-editor Battle.net login.
 */
static int install_hook(hook_t *h, unsigned char *ts, size_t tl) {
    unsigned char *p = (unsigned char *)h->site;
    if (!ts) return 0;
    if (p < ts || p + h->siglen > ts + tl) return 0;
    if (memcmp(p, h->sig, h->siglen)) return 0;
    int32_t rel = (int32_t)((intptr_t)h->hook - (intptr_t)(h->site + 5));
    if (write_bytes(p + 1, (const unsigned char *)&rel, 4))
        logf_("sc2ed_fix: hooked [%s] at 0x%llx", h->name, h->site);
    else
        logf_("sc2ed_fix: could not hook [%s]", h->name);
    return 1;
}

static void *worker(void *_unused) {
    (void)_unused;
    unsigned char *ts = NULL; size_t tl = 0;
    if (!text_range(&ts, &tl))
        logf_("sc2ed_fix: could not locate __text (scanning disabled)");

    size_t remaining = NFIXES + NHOOKS;
    for (long i = 0; i < POLL_PASSES && remaining; i++) {
        int allow_scan = (i % SCAN_EVERY) == 0;

        for (size_t k = 0; k < NFIXES; k++) {
            fix_t *f = &FIXES[k];
            if (f->done) continue;
            unsigned char *site = find_site(f, ts, tl, allow_scan);
            if (!site) continue;
            if (write_bytes(site + f->patch_off, f->repl, f->repllen))
                logf_("sc2ed_fix: applied [%s] at %p", f->name, (void *)site);
            else
                logf_("sc2ed_fix: mprotect failed for [%s] - not applied", f->name);
            f->done = 1;
            remaining--;
        }
        for (size_t k = 0; k < NHOOKS; k++) {
            hook_t *h = &HOOKS[k];
            if (h->done) continue;
            if (!install_hook(h, ts, tl)) continue;
            h->done = 1;
            remaining--;
        }
        usleep(POLL_US);
    }
    for (size_t k = 0; k < NFIXES; k++)
        if (!FIXES[k].done)
            logf_("sc2ed_fix: [%s] signature not found - skipped "
                  "(different SC2 build?)", FIXES[k].name);
    for (size_t k = 0; k < NHOOKS; k++)
        if (!HOOKS[k].done)
            logf_("sc2ed_fix: [%s] signature not found - skipped "
                  "(different SC2 build?)", HOOKS[k].name);
    return NULL;
}

/*
 * Log the environment at startup. Signatures are build-specific, so a bug
 * report is only actionable if it says which SC2 build and macOS version it
 * came from -- this makes a pasted log self-sufficient.
 */
static void log_environment(void) {
    @autoreleasepool {
        const char *sc2 = "unknown", *os = "unknown";
        @try {
            NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
            NSString *v = [info objectForKey:@"CFBundleShortVersionString"];
            if (!v) v = [info objectForKey:@"CFBundleVersion"];
            if (v) sc2 = [v UTF8String];
            NSString *o = [[NSProcessInfo processInfo] operatingSystemVersionString];
            if (o) os = [o UTF8String];
        } @catch (NSException *ex) { /* keep the defaults */ }

        int translated = 0; size_t sz = sizeof translated;
        if (sysctlbyname("sysctl.proc_translated", &translated, &sz, NULL, 0) != 0)
            translated = 0;

        logf_("sc2ed_fix: v%s | SC2 %s | macOS %s | %s%s",
              SC2ED_FIX_VERSION, sc2, os,
#if defined(__x86_64__)
              "x86_64",
#else
              "arm64",
#endif
              translated ? " (Rosetta)" : "");
    }
}

/*
 * Only ever touch the StarCraft II Editor itself.
 *
 * DYLD_INSERT_LIBRARIES is inherited by child processes, so without this the
 * shim also loads into helpers such as BlizzardBrowser (the in-editor
 * Battle.net login window) where none of our addresses mean anything.
 */
static int is_the_editor(void) {
    @autoreleasepool {
        @try {
            NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
            if (bid && [bid isEqualToString:@"com.blizzard.starcraft2.editor"]) return 1;
        } @catch (NSException *ex) { /* fall through */ }
    }
    return 0;
}

__attribute__((constructor))
static void sc2ed_fix_init(void) {
    if (!is_the_editor()) return;   /* a helper process -- do nothing at all */
    logf_("sc2ed_fix: loaded (pid %d, %zu patch(es), %zu hook(s))",
          getpid(), (size_t)NFIXES, (size_t)NHOOKS);
    log_environment();
    pthread_t t;
    if (pthread_create(&t, NULL, worker, NULL) == 0) pthread_detach(t);
}
