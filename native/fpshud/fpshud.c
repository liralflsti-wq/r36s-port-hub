/*
 * R36S PORT HUB - contador de FPS para ports de jogos (LD_PRELOAD)
 *
 * O hub carrega esta biblioteca so quando o jogador escolhe "Iniciar com
 * contador de FPS". Ela intercepta eglSwapBuffers (chamado direto pelo jogo
 * ou pego por dlsym, como faz o SDL2) e, antes de mostrar cada quadro, desenha
 * "FPS NN" no canto superior esquerdo usando so glScissor + glClear: funciona
 * em OpenGL ES 1 e 2/3 e com gl4es, sem shaders, e o estado do GL e
 * restaurado depois. Se algo faltar, a biblioteca nao desenha nada e o jogo
 * segue normal.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>

/* versoes antigas dos simbolos da glibc: roda em sistemas mais velhos */
#if defined(__aarch64__)
#  define GV_OLD "GLIBC_2.17"
__asm__(".symver dlvsym,dlvsym@GLIBC_2.17");
__asm__(".symver dlopen,dlopen@GLIBC_2.17");
__asm__(".symver gettimeofday,gettimeofday@GLIBC_2.17");
#elif defined(__arm__)
#  define GV_OLD "GLIBC_2.4"
__asm__(".symver dlvsym,dlvsym@GLIBC_2.4");
__asm__(".symver dlopen,dlopen@GLIBC_2.4");
__asm__(".symver gettimeofday,gettimeofday@GLIBC_2.4");
#else
#  define GV_OLD "GLIBC_2.2.5"
#endif

typedef unsigned int EGLBoolean;
typedef void *EGLDisplay;
typedef void *EGLSurface;
typedef int EGLint;
#define EGL_HEIGHT 0x3056
#define EGL_WIDTH 0x3057

typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
#define GL_SCISSOR_TEST 0x0C11
#define GL_SCISSOR_BOX 0x0C10
#define GL_COLOR_CLEAR_VALUE 0x0C22
#define GL_COLOR_WRITEMASK 0x0C23
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_FRAMEBUFFER 0x8D40
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#define GL_VERSION 0x1F02

typedef void *(*dlsym_fn)(void *, const char *);
typedef EGLBoolean (*swap_fn)(EGLDisplay, EGLSurface);
typedef EGLBoolean (*query_fn)(EGLDisplay, EGLSurface, EGLint, EGLint *);
typedef void *(*gpa_fn)(const char *);

static dlsym_fn real_dlsym_p;
static swap_fn real_swap;
static query_fn real_query;
static gpa_fn real_gpa;

static struct {
  int ok, tried, es2;
  void (*Clear)(GLbitfield);
  void (*ClearColor)(GLfloat, GLfloat, GLfloat, GLfloat);
  void (*Scissor)(GLint, GLint, GLsizei, GLsizei);
  void (*Enable)(GLenum);
  void (*Disable)(GLenum);
  GLboolean (*IsEnabled)(GLenum);
  void (*GetIntegerv)(GLenum, GLint *);
  void (*GetFloatv)(GLenum, GLfloat *);
  void (*GetBooleanv)(GLenum, GLboolean *);
  void (*ColorMask)(GLboolean, GLboolean, GLboolean, GLboolean);
  void (*BindFramebuffer)(GLenum, GLuint);
  const unsigned char *(*GetString)(GLenum);
} gl;

static void *real_dlsym(void *h, const char *n)
{
  if (!real_dlsym_p) {
    real_dlsym_p = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    if (!real_dlsym_p) real_dlsym_p = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", GV_OLD);
    if (!real_dlsym_p) return NULL;
  }
  return real_dlsym_p(h, n);
}

/* procura uma funcao do GLES de verdade (antes do gl4es, se houver) */
static void *glsym(const char *n)
{
  static const char *libs[] = { "libGLESv2.so.2", "libGLESv2.so", "libmali.so",
    "libGLESv1_CM.so.1", "libGLESv1_CM.so", NULL };
  void *p = NULL;
  for (int i = 0; libs[i] && !p; i++) {
    void *h = dlopen(libs[i], RTLD_LAZY | RTLD_NOLOAD);
    if (h) p = real_dlsym(h, n);
  }
  if (!p && real_gpa) p = real_gpa(n);
  if (!p) p = real_dlsym(RTLD_DEFAULT, n);
  return p;
}

static void load_gl(void)
{
  if (gl.tried) return;
  gl.tried = 1;
  if (!real_gpa) real_gpa = (gpa_fn)real_dlsym(RTLD_DEFAULT, "eglGetProcAddress");
  gl.Clear = glsym("glClear");
  gl.ClearColor = glsym("glClearColor");
  gl.Scissor = glsym("glScissor");
  gl.Enable = glsym("glEnable");
  gl.Disable = glsym("glDisable");
  gl.IsEnabled = glsym("glIsEnabled");
  gl.GetIntegerv = glsym("glGetIntegerv");
  gl.GetFloatv = glsym("glGetFloatv");
  gl.GetBooleanv = glsym("glGetBooleanv");
  gl.ColorMask = glsym("glColorMask");
  gl.GetString = glsym("glGetString");
  gl.BindFramebuffer = glsym("glBindFramebuffer");
  gl.ok = gl.Clear && gl.ClearColor && gl.Scissor && gl.Enable && gl.Disable &&
          gl.IsEnabled && gl.GetIntegerv && gl.GetFloatv && gl.GetBooleanv && gl.ColorMask;
}

/* fonte 5x7: F P S espaco 0-9 */
static const unsigned char FONT[][7] = {
  { 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10 }, /* F */
  { 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 }, /* P */
  { 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E }, /* S */
  { 0, 0, 0, 0, 0, 0, 0 },                      /* espaco */
  { 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E }, /* 0 */
  { 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E }, /* 1 */
  { 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F }, /* 2 */
  { 0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E }, /* 3 */
  { 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 }, /* 4 */
  { 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E }, /* 5 */
  { 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E }, /* 6 */
  { 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 }, /* 7 */
  { 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E }, /* 8 */
  { 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C }, /* 9 */
};
static int glyph(char c)
{
  if (c == 'F') return 0;
  if (c == 'P') return 1;
  if (c == 'S') return 2;
  if (c >= '0' && c <= '9') return 4 + (c - '0');
  return 3;
}

static double now(void)
{
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1e6;
}

static int frames, shown = -1;
static double t0;

static void rect(int x, int y, int w, int h, int H)
{
  /* y a partir do topo; o GL conta de baixo para cima */
  gl.Scissor(x, H - y - h, w, h);
  gl.Clear(GL_COLOR_BUFFER_BIT);
}

static void draw(EGLDisplay dpy, EGLSurface surf)
{
  load_gl();
  if (!gl.ok) return;
  if (!real_query) {
    real_query = (query_fn)real_dlsym(RTLD_DEFAULT, "eglQuerySurface");
    if (!real_query && real_gpa) real_query = (query_fn)real_gpa("eglQuerySurface");
  }
  EGLint W = 640, H = 480;
  if (real_query) {
    EGLint w = 0, h = 0;
    if (real_query(dpy, surf, EGL_WIDTH, &w) && real_query(dpy, surf, EGL_HEIGHT, &h) && w > 0 && h > 0) {
      W = w; H = h;
    }
  }

  char txt[16] = "FPS ";
  int v = shown < 0 ? 0 : (shown > 999 ? 999 : shown);
  int n = 4;
  if (shown < 0) { txt[n++] = ' '; txt[n++] = ' '; }
  else {
    if (v >= 100) txt[n++] = '0' + v / 100;
    if (v >= 10) txt[n++] = '0' + (v / 10) % 10;
    txt[n++] = '0' + v % 10;
  }
  txt[n] = 0;

  /* tamanho do pixel da fonte: 4 px numa tela de 480 linhas */
  int s = H / 120; if (s < 2) s = 2; if (s > 8) s = 8;
  int pad = s * 2, m = s * 2;
  int bw = n * 6 * s - s + pad * 2, bh = 7 * s + pad * 2;
  if (bw > W || bh > H) return;

  /* guarda o estado */
  GLboolean sc = gl.IsEnabled(GL_SCISSOR_TEST);
  GLint box[4] = { 0, 0, 0, 0 };
  GLfloat cc[4] = { 0, 0, 0, 0 };
  GLboolean cm[4] = { 1, 1, 1, 1 };
  GLint fb = 0;
  gl.GetIntegerv(GL_SCISSOR_BOX, box);
  gl.GetFloatv(GL_COLOR_CLEAR_VALUE, cc);
  gl.GetBooleanv(GL_COLOR_WRITEMASK, cm);
  if (gl.es2 < 0) {} /* reservado */
  if (gl.BindFramebuffer && gl.GetString) {
    const char *ver = (const char *)gl.GetString(GL_VERSION);
    if (ver && !strstr(ver, "ES-CM") && !strstr(ver, "ES 1.")) {
      gl.GetIntegerv(GL_FRAMEBUFFER_BINDING, &fb);
      if (fb) gl.BindFramebuffer(GL_FRAMEBUFFER, 0);
    } else fb = 0;
  }

  gl.Enable(GL_SCISSOR_TEST);
  gl.ColorMask(1, 1, 1, 1);
  /* fundo escuro */
  gl.ClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  rect(m, m, bw, bh, H);
  /* cor pelo desempenho: verde, amarelo, vermelho */
  if (shown >= 50) gl.ClearColor(0.25f, 1.0f, 0.35f, 1.0f);
  else if (shown >= 30) gl.ClearColor(1.0f, 0.85f, 0.2f, 1.0f);
  else if (shown >= 0) gl.ClearColor(1.0f, 0.3f, 0.3f, 1.0f);
  else gl.ClearColor(1.0f, 1.0f, 1.0f, 1.0f);
  for (int i = 0; i < n; i++) {
    const unsigned char *g = FONT[glyph(txt[i])];
    int cx = m + pad + i * 6 * s;
    for (int r = 0; r < 7; r++) {
      unsigned char row = g[r];
      int c = 0;
      while (c < 5) {
        if (row & (0x10 >> c)) {
          int c2 = c;
          while (c2 < 5 && (row & (0x10 >> c2))) c2++;
          rect(cx + c * s, m + pad + r * s, (c2 - c) * s, s, H);
          c = c2;
        } else c++;
      }
    }
  }

  /* devolve o estado */
  gl.ClearColor(cc[0], cc[1], cc[2], cc[3]);
  gl.ColorMask(cm[0], cm[1], cm[2], cm[3]);
  gl.Scissor(box[0], box[1], box[2], box[3]);
  if (!sc) gl.Disable(GL_SCISSOR_TEST);
  if (fb) gl.BindFramebuffer(GL_FRAMEBUFFER, (GLuint)fb);
}

static EGLBoolean hud_swap(EGLDisplay dpy, EGLSurface surf)
{
  double t = now();
  if (t0 == 0) t0 = t;
  frames++;
  if (t - t0 >= 0.5) {
    shown = (int)(frames / (t - t0) + 0.5);
    frames = 0;
    t0 = t;
  }
  draw(dpy, surf);
  return real_swap ? real_swap(dpy, surf) : 0;
}

/* jogo ligado direto ao libEGL */
EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surf)
{
  if (!real_swap) real_swap = (swap_fn)real_dlsym(RTLD_NEXT, "eglSwapBuffers");
  return hud_swap(dpy, surf);
}

/* SDL2 e outros pegam o eglSwapBuffers por dlsym ou eglGetProcAddress */
void *dlsym(void *h, const char *n)
{
  void *p = real_dlsym(h, n);
  if (p && n && strcmp(n, "eglSwapBuffers") == 0) {
    if (p != (void *)eglSwapBuffers) real_swap = (swap_fn)p;
    return (void *)eglSwapBuffers;
  }
  if (p && n && strcmp(n, "eglGetProcAddress") == 0 && p != (void *)real_gpa) {
    real_gpa = (gpa_fn)p;
  }
  return p;
}
