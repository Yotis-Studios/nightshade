/* sdl_abi_dump.c — authoritative dump of SDL2 struct offsets + constant values.
 *
 * This machine has NO system SDL2 headers installed (only the runtime
 * libSDL2-2.0.so.0.18.2). The headers used here were extracted from the
 * Ubuntu jammy package libsdl2-dev 2.0.20+dfsg-2ubuntu1.22.04.1 into
 * /tmp/sdl2dev. SDL2 struct layouts and enum values are ABI-frozen across all
 * of 2.0.x, so 2.0.20 headers describe the 2.0.18 runtime exactly. This
 * program ALSO calls SDL_GetVersion() at runtime and asserts the loaded lib is
 * what we think it is.
 *
 * Build:
 *   gcc -I/tmp/sdl2dev/usr/include/SDL2 -I/tmp/sdl2dev/usr/include \
 *       -o sdl_abi_dump sdl_abi_dump.c -lSDL2
 * Run:
 *   SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./sdl_abi_dump
 */
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "SDL.h"

#define O(S, F) printf("  %-46s %3zu   (size %2zu)\n", #S "." #F, offsetof(S, F), sizeof(((S *)0)->F))
#define SZ(S)   printf("SIZEOF %-42s = %zu\n", #S, sizeof(S))
#define C(X)    printf("  %-46s %ld  (0x%lX)\n", #X, (long)(X), (long)(X))
#define CU(X)   printf("  %-46s %lu  (0x%lX)\n", #X, (unsigned long)(X), (unsigned long)(X))

int main(void)
{
    SDL_version linked, compiled;
    SDL_GetVersion(&linked);
    SDL_VERSION(&compiled);
    printf("### VERSION\n");
    printf("  header (compiled against): %d.%d.%d\n", compiled.major, compiled.minor, compiled.patch);
    printf("  runtime (actually loaded): %d.%d.%d\n", linked.major, linked.minor, linked.patch);
    printf("  sizeof(void*) = %zu\n\n", sizeof(void *));

    printf("### EVENT STRUCTS\n");
    SZ(SDL_Event);
    SZ(SDL_CommonEvent);
    SZ(SDL_KeyboardEvent);
    SZ(SDL_MouseMotionEvent);
    SZ(SDL_MouseButtonEvent);
    SZ(SDL_MouseWheelEvent);
    SZ(SDL_WindowEvent);
    SZ(SDL_TextInputEvent);
    printf("\n-- SDL_CommonEvent --\n");
    O(SDL_CommonEvent, type);
    O(SDL_CommonEvent, timestamp);
    printf("\n-- SDL_MouseMotionEvent (event.motion) --\n");
    O(SDL_MouseMotionEvent, type);
    O(SDL_MouseMotionEvent, timestamp);
    O(SDL_MouseMotionEvent, windowID);
    O(SDL_MouseMotionEvent, which);
    O(SDL_MouseMotionEvent, state);
    O(SDL_MouseMotionEvent, x);
    O(SDL_MouseMotionEvent, y);
    O(SDL_MouseMotionEvent, xrel);
    O(SDL_MouseMotionEvent, yrel);
    printf("\n-- SDL_MouseButtonEvent (event.button) --\n");
    O(SDL_MouseButtonEvent, type);
    O(SDL_MouseButtonEvent, timestamp);
    O(SDL_MouseButtonEvent, windowID);
    O(SDL_MouseButtonEvent, which);
    O(SDL_MouseButtonEvent, button);
    O(SDL_MouseButtonEvent, state);
    O(SDL_MouseButtonEvent, clicks);
    O(SDL_MouseButtonEvent, x);
    O(SDL_MouseButtonEvent, y);
    printf("\n-- SDL_MouseWheelEvent (event.wheel) --\n");
    O(SDL_MouseWheelEvent, type);
    O(SDL_MouseWheelEvent, x);
    O(SDL_MouseWheelEvent, y);
    O(SDL_MouseWheelEvent, direction);
    O(SDL_MouseWheelEvent, preciseX);
    O(SDL_MouseWheelEvent, preciseY);
    printf("\n-- SDL_KeyboardEvent (event.key) --\n");
    O(SDL_KeyboardEvent, type);
    O(SDL_KeyboardEvent, timestamp);
    O(SDL_KeyboardEvent, windowID);
    O(SDL_KeyboardEvent, state);
    O(SDL_KeyboardEvent, repeat);
    O(SDL_KeyboardEvent, keysym);
    printf("  %-46s %3zu\n", "SDL_KeyboardEvent.keysym.scancode",
           offsetof(SDL_KeyboardEvent, keysym) + offsetof(SDL_Keysym, scancode));
    printf("  %-46s %3zu\n", "SDL_KeyboardEvent.keysym.sym",
           offsetof(SDL_KeyboardEvent, keysym) + offsetof(SDL_Keysym, sym));
    printf("  %-46s %3zu\n", "SDL_KeyboardEvent.keysym.mod",
           offsetof(SDL_KeyboardEvent, keysym) + offsetof(SDL_Keysym, mod));
    printf("\n-- SDL_WindowEvent (event.window) --\n");
    O(SDL_WindowEvent, type);
    O(SDL_WindowEvent, windowID);
    O(SDL_WindowEvent, event);
    O(SDL_WindowEvent, data1);
    O(SDL_WindowEvent, data2);

    printf("\n### EVENT TYPE CONSTANTS\n");
    C(SDL_FIRSTEVENT);
    C(SDL_QUIT);
    C(SDL_WINDOWEVENT);
    C(SDL_KEYDOWN);
    C(SDL_KEYUP);
    C(SDL_TEXTINPUT);
    C(SDL_MOUSEMOTION);
    C(SDL_MOUSEBUTTONDOWN);
    C(SDL_MOUSEBUTTONUP);
    C(SDL_MOUSEWHEEL);
    C(SDL_CONTROLLERAXISMOTION);
    C(SDL_CONTROLLERBUTTONDOWN);
    C(SDL_CONTROLLERBUTTONUP);
    C(SDL_CONTROLLERDEVICEADDED);
    printf("\n### MOUSE BUTTONS / STATE\n");
    C(SDL_BUTTON_LEFT);
    C(SDL_BUTTON_MIDDLE);
    C(SDL_BUTTON_RIGHT);
    C(SDL_BUTTON_X1);
    C(SDL_BUTTON_X2);
    C(SDL_BUTTON_LMASK);
    C(SDL_BUTTON_MMASK);
    C(SDL_BUTTON_RMASK);
    C(SDL_BUTTON_X1MASK);
    C(SDL_BUTTON_X2MASK);
    C(SDL_PRESSED);
    C(SDL_RELEASED);
    C(SDL_ENABLE);
    C(SDL_DISABLE);
    C(SDL_QUERY);
    C(SDL_MOUSEWHEEL_NORMAL);
    C(SDL_MOUSEWHEEL_FLIPPED);

    printf("\n### RECT / POINT / VERTEX\n");
    SZ(SDL_Rect);
    O(SDL_Rect, x); O(SDL_Rect, y); O(SDL_Rect, w); O(SDL_Rect, h);
    SZ(SDL_FRect);
    O(SDL_FRect, x); O(SDL_FRect, y); O(SDL_FRect, w); O(SDL_FRect, h);
    SZ(SDL_Point);
    O(SDL_Point, x); O(SDL_Point, y);
    SZ(SDL_FPoint);
    O(SDL_FPoint, x); O(SDL_FPoint, y);
    SZ(SDL_Color);
    O(SDL_Color, r); O(SDL_Color, g); O(SDL_Color, b); O(SDL_Color, a);
    SZ(SDL_Vertex);
    O(SDL_Vertex, position);
    O(SDL_Vertex, color);
    O(SDL_Vertex, tex_coord);

    printf("\n### BLEND MODES\n");
    C(SDL_BLENDMODE_NONE);
    C(SDL_BLENDMODE_BLEND);
    C(SDL_BLENDMODE_ADD);
    C(SDL_BLENDMODE_MOD);
    C(SDL_BLENDMODE_MUL);
    C(SDL_BLENDMODE_INVALID);
    printf("  -- custom blend factors/ops (for SDL_ComposeCustomBlendMode) --\n");
    C(SDL_BLENDFACTOR_ZERO);
    C(SDL_BLENDFACTOR_ONE);
    C(SDL_BLENDFACTOR_SRC_COLOR);
    C(SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR);
    C(SDL_BLENDFACTOR_SRC_ALPHA);
    C(SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA);
    C(SDL_BLENDFACTOR_DST_COLOR);
    C(SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR);
    C(SDL_BLENDFACTOR_DST_ALPHA);
    C(SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA);
    C(SDL_BLENDOPERATION_ADD);
    C(SDL_BLENDOPERATION_SUBTRACT);
    C(SDL_BLENDOPERATION_REV_SUBTRACT);
    C(SDL_BLENDOPERATION_MINIMUM);
    C(SDL_BLENDOPERATION_MAXIMUM);

    printf("\n### RENDERER / TEXTURE\n");
    C(SDL_RENDERER_SOFTWARE);
    C(SDL_RENDERER_ACCELERATED);
    C(SDL_RENDERER_PRESENTVSYNC);
    C(SDL_RENDERER_TARGETTEXTURE);
    C(SDL_TEXTUREACCESS_STATIC);
    C(SDL_TEXTUREACCESS_STREAMING);
    C(SDL_TEXTUREACCESS_TARGET);
    C(SDL_ScaleModeNearest);
    C(SDL_ScaleModeLinear);
    C(SDL_ScaleModeBest);
    C(SDL_FLIP_NONE);
    C(SDL_FLIP_HORIZONTAL);
    C(SDL_FLIP_VERTICAL);
    SZ(SDL_RendererInfo);
    O(SDL_RendererInfo, name);
    O(SDL_RendererInfo, flags);
    O(SDL_RendererInfo, num_texture_formats);
    O(SDL_RendererInfo, texture_formats);
    O(SDL_RendererInfo, max_texture_width);
    O(SDL_RendererInfo, max_texture_height);

    printf("\n### PIXEL FORMATS (byte order notes are for LITTLE-ENDIAN x86-64)\n");
    printf("  SDL_BYTEORDER == SDL_LIL_ENDIAN ? %s\n",
           (SDL_BYTEORDER == SDL_LIL_ENDIAN) ? "YES" : "NO");
    CU(SDL_PIXELFORMAT_RGB24);
    CU(SDL_PIXELFORMAT_BGR24);
    CU(SDL_PIXELFORMAT_RGB888);
    CU(SDL_PIXELFORMAT_ARGB8888);
    CU(SDL_PIXELFORMAT_RGBA8888);
    CU(SDL_PIXELFORMAT_ABGR8888);
    CU(SDL_PIXELFORMAT_BGRA8888);
    CU(SDL_PIXELFORMAT_XRGB8888);
    CU(SDL_PIXELFORMAT_RGBA32);
    CU(SDL_PIXELFORMAT_ARGB32);
    CU(SDL_PIXELFORMAT_BGRA32);
    CU(SDL_PIXELFORMAT_ABGR32);
    CU(SDL_PIXELFORMAT_RGB565);
    CU(SDL_PIXELFORMAT_RGBA5551);
    printf("  RGBA32 == ABGR8888 ? %s\n",
           (SDL_PIXELFORMAT_RGBA32 == SDL_PIXELFORMAT_ABGR8888) ? "YES" : "NO");

    printf("\n### AUDIO\n");
    SZ(SDL_AudioSpec);
    O(SDL_AudioSpec, freq);
    O(SDL_AudioSpec, format);
    O(SDL_AudioSpec, channels);
    O(SDL_AudioSpec, silence);
    O(SDL_AudioSpec, samples);
    O(SDL_AudioSpec, padding);
    O(SDL_AudioSpec, size);
    O(SDL_AudioSpec, callback);
    O(SDL_AudioSpec, userdata);
    CU(AUDIO_U8);
    CU(AUDIO_S8);
    CU(AUDIO_S16LSB);
    CU(AUDIO_S16SYS);
    CU(AUDIO_S32LSB);
    CU(AUDIO_S32SYS);
    CU(AUDIO_F32LSB);
    CU(AUDIO_F32SYS);
    C(SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
    C(SDL_AUDIO_ALLOW_FORMAT_CHANGE);
    C(SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
    C(SDL_AUDIO_ALLOW_ANY_CHANGE);
    C(SDL_MIX_MAXVOLUME);
    SZ(SDL_AudioCVT);
    O(SDL_AudioCVT, needed);
    O(SDL_AudioCVT, src_format);
    O(SDL_AudioCVT, dst_format);
    O(SDL_AudioCVT, rate_incr);
    O(SDL_AudioCVT, buf);
    O(SDL_AudioCVT, len);
    O(SDL_AudioCVT, len_cvt);
    O(SDL_AudioCVT, len_mult);
    O(SDL_AudioCVT, len_ratio);

    printf("\n### INIT / WINDOW FLAGS\n");
    CU(SDL_INIT_TIMER);
    CU(SDL_INIT_AUDIO);
    CU(SDL_INIT_VIDEO);
    CU(SDL_INIT_JOYSTICK);
    CU(SDL_INIT_GAMECONTROLLER);
    CU(SDL_INIT_EVENTS);
    CU(SDL_INIT_EVERYTHING);
    CU(SDL_WINDOW_FULLSCREEN);
    CU(SDL_WINDOW_FULLSCREEN_DESKTOP);
    CU(SDL_WINDOW_OPENGL);
    CU(SDL_WINDOW_SHOWN);
    CU(SDL_WINDOW_HIDDEN);
    CU(SDL_WINDOW_BORDERLESS);
    CU(SDL_WINDOW_RESIZABLE);
    CU(SDL_WINDOW_INPUT_GRABBED);
    CU(SDL_WINDOW_MOUSE_CAPTURE);
    CU(SDL_WINDOW_ALLOW_HIGHDPI);
    CU(SDL_WINDOWPOS_CENTERED);
    CU(SDL_WINDOWPOS_UNDEFINED);
    C(SDL_WINDOWEVENT_SHOWN);
    C(SDL_WINDOWEVENT_RESIZED);
    C(SDL_WINDOWEVENT_SIZE_CHANGED);
    C(SDL_WINDOWEVENT_FOCUS_GAINED);
    C(SDL_WINDOWEVENT_FOCUS_LOST);
    C(SDL_WINDOWEVENT_CLOSE);

    printf("\n### RWops / misc\n");
    C(RW_SEEK_SET);
    C(RW_SEEK_CUR);
    C(RW_SEEK_END);

    printf("\n### KEY SCANCODES (SDL_GetKeyboardState index) — FPS-relevant\n");
    C(SDL_SCANCODE_A); C(SDL_SCANCODE_B); C(SDL_SCANCODE_C); C(SDL_SCANCODE_D);
    C(SDL_SCANCODE_E); C(SDL_SCANCODE_F); C(SDL_SCANCODE_G); C(SDL_SCANCODE_Q);
    C(SDL_SCANCODE_R); C(SDL_SCANCODE_S); C(SDL_SCANCODE_T); C(SDL_SCANCODE_V);
    C(SDL_SCANCODE_W); C(SDL_SCANCODE_X); C(SDL_SCANCODE_Z);
    C(SDL_SCANCODE_1); C(SDL_SCANCODE_2); C(SDL_SCANCODE_3); C(SDL_SCANCODE_4);
    C(SDL_SCANCODE_5); C(SDL_SCANCODE_0);
    C(SDL_SCANCODE_RETURN); C(SDL_SCANCODE_ESCAPE); C(SDL_SCANCODE_BACKSPACE);
    C(SDL_SCANCODE_TAB); C(SDL_SCANCODE_SPACE); C(SDL_SCANCODE_GRAVE);
    C(SDL_SCANCODE_F1); C(SDL_SCANCODE_F5); C(SDL_SCANCODE_F11);
    C(SDL_SCANCODE_LCTRL); C(SDL_SCANCODE_LSHIFT); C(SDL_SCANCODE_LALT);
    C(SDL_SCANCODE_RCTRL); C(SDL_SCANCODE_RSHIFT);
    C(SDL_SCANCODE_RIGHT); C(SDL_SCANCODE_LEFT); C(SDL_SCANCODE_DOWN); C(SDL_SCANCODE_UP);
    C(SDL_NUM_SCANCODES);

    printf("\n### KEYCODES (event.key.keysym.sym) — FPS-relevant\n");
    C(SDLK_ESCAPE); C(SDLK_SPACE); C(SDLK_RETURN); C(SDLK_TAB); C(SDLK_BACKQUOTE);
    C(SDLK_w); C(SDLK_a); C(SDLK_s); C(SDLK_d); C(SDLK_e); C(SDLK_q); C(SDLK_r);
    C(SDLK_f); C(SDLK_g); C(SDLK_v); C(SDLK_c); C(SDLK_1); C(SDLK_2); C(SDLK_3);
    C(SDLK_F1); C(SDLK_F5); C(SDLK_F11);
    C(SDLK_LSHIFT); C(SDLK_LCTRL); C(SDLK_LALT);
    C(SDLK_UP); C(SDLK_DOWN); C(SDLK_LEFT); C(SDLK_RIGHT);

    printf("\n### HINT STRINGS\n");
    printf("  SDL_HINT_RENDER_SCALE_QUALITY     = \"%s\"\n", SDL_HINT_RENDER_SCALE_QUALITY);
    printf("  SDL_HINT_RENDER_VSYNC             = \"%s\"\n", SDL_HINT_RENDER_VSYNC);
    printf("  SDL_HINT_MOUSE_RELATIVE_MODE_WARP = \"%s\"\n", SDL_HINT_MOUSE_RELATIVE_MODE_WARP);
    printf("  SDL_HINT_RENDER_DRIVER            = \"%s\"\n", SDL_HINT_RENDER_DRIVER);
    printf("  SDL_HINT_FRAMEBUFFER_ACCELERATION = \"%s\"\n", SDL_HINT_FRAMEBUFFER_ACCELERATION);
    printf("  SDL_HINT_MOUSE_RELATIVE_SCALING   = \"%s\"\n", SDL_HINT_MOUSE_RELATIVE_SCALING);
    printf("  SDL_HINT_GRAB_KEYBOARD            = \"%s\"\n", SDL_HINT_GRAB_KEYBOARD);

    printf("\n### FUNCTION PROTOTYPE SANITY (types the FFI must match)\n");
    printf("  sizeof(SDL_AudioDeviceID)=%zu  sizeof(SDL_AudioFormat)=%zu\n",
           sizeof(SDL_AudioDeviceID), sizeof(SDL_AudioFormat));
    printf("  sizeof(SDL_BlendMode)=%zu  sizeof(SDL_RendererFlip)=%zu  sizeof(SDL_ScaleMode)=%zu\n",
           sizeof(SDL_BlendMode), sizeof(SDL_RendererFlip), sizeof(SDL_ScaleMode));
    printf("  sizeof(Uint64)=%zu  sizeof(SDL_Keycode)=%zu  sizeof(SDL_Scancode)=%zu\n",
           sizeof(Uint64), sizeof(SDL_Keycode), sizeof(SDL_Scancode));
    printf("  RenderCopyEx angle is 'const double' -> f64\n");

    return 0;
}
