# NIGHTSHADE — ART BIBLE

**Version:** 1.0 (recon)
**Author:** Art Direction
**Status:** Source of truth. If the code disagrees with this document, the code is wrong.
**Scope:** Palette, lighting, atmosphere, texture generation, silhouette, HUD, post-FX, composition, anti-goals.

---

## 0. THESIS

> **We are not making a game that looks like a PS1 game. We are making the game a PS1 art
> director would have made if they'd had six months and no publisher.**

The PS1 aesthetic is not "low-poly + ugly textures." It is a *specific set of technical
constraints that forced specific artistic solutions*, and those solutions — saturated limited
palettes, aggressive atmospheric fog, high-contrast value structure, chunky readable
silhouettes, dithered gradients — are **timelessly good design**. Games like *Ocarina of Time*,
*Turok 2*, *Vagrant Story*, *Silent Hill*, *Ape Escape*, and *Metal Gear Solid* still look
beautiful in 2026 because they were art-directed *around* the limits, not despite them.

The three pillars of Nightshade's look:

1. **ATMOSPHERE OVER DETAIL.** We cannot render detail. We can render *depth*. Fog, value
   separation, and colored light do 90% of the work. A foggy violet dusk with 400 triangles
   beats a clear noon with 4000.
2. **A DISCIPLINED, TINTED PALETTE.** Nothing in this game is a pure RGB primary. Every green
   is pushed toward yellow or teal, every blue toward cyan or violet, every grey toward warm or
   cool. Untinted color is the #1 tell of amateur work.
3. **ONE SIGNATURE COLOR.** The game is called Nightshade. The world is warm — ochre, olive,
   bark, dust. The *threat* and the *reward* are **violet**. Violet is the enemy's rim light,
   the enemy's glowing core, the XP bar, the loot beam, the toxic flora, the boss arena. Warm
   world + violet accent = instant readability and instant brand.

Everything below serves those three pillars.

---

## 1. THE CURRENT BASELINE IS BAD. HERE IS EXACTLY WHY.

Reference images inspected: `wobbleweed/docs/scene.png`, `scene_gpu.png`, `ground.png`,
`tree.png`, `cube.png`.

The renderer is fine. The **art direction is absent**. Specific, itemized failures:

### 1.1 There is no atmospheric perspective at all — this is the fatal one
Distant grass at the horizon is *exactly* as saturated, as contrasty, and as bright as grass
under the player's feet. The ground meets the sky at a razor-sharp, full-contrast line. The
result: the world reads as a **small green rug on a blue wall**, not a landscape. There is no
sense of scale, depth, distance, or space. Every other problem in this list is secondary to
this one. **Fog is not a nice-to-have; it is the primary art tool of this project.**

### 1.2 The ground texture is green television static
`tex_grass()` writes independent random noise per texel (`g = 90 + n % 70`, `r = 35 + n2 % 35`).
Per-texel white noise has three fatal properties:
- **No structure at any scale.** Real surfaces have clumps, patches, blades, wear paths. Noise
  has none, so the eye finds nothing to read and the surface reads as "error."
- **It aliases catastrophically.** At 320×240 with nearest sampling and a moving camera, single-
  texel noise shimmers and crawls. It will look worse in motion than in a screenshot.
- **The variance is far too wide** (±35 on green, ±17 on red) *and* uniformly distributed, so
  there is no dominant value — no read, no silhouette, just mush.

Compounding it, in `ground.png` you can see an 8-pixel-ish blocky value pattern fighting the
fine noise: two incompatible frequencies at once. And there is a visible repeating tile in the
mid-distance because the 64×64 tile has no low-frequency content to disguise the repeat.

### 1.3 The ground is lit by exactly one number
`render_world_gpu` computes `glight = face_light(v3(0,1,0))` **once** and applies it to all 256
ground quads. Every square metre of terrain is the identical brightness. The ground plane
therefore reads as flat cardboard. There is no undulation, no clumping of light and shade, no
sense that light is falling on a surface. Per-vertex lighting is *free* here and is being
thrown away.

### 1.4 The value structure has no darks
Sample the images: essentially nothing is below ~30% luminance. The darkest pixel in the frame
is roughly the tree canopy at RGB(42,98,44). The entire image lives in the mid-to-light band.
An image with no true dark and no true light has **no contrast anchor**, and reads as washed
out and toy-like regardless of what's in it. Professional images pin both ends of the range.

### 1.5 The palette is straight out of the RGB cube
Sky `(60,100,196) → (150,186,226)`; grass around `(50,125,45)`; leaves `(58,138,62)`; trunk
`(112,78,46)`; crate `(210,210,210)/(70,70,70)`. These are *default* colors — the values you
get when you type a number rather than choose one. Three hues total (blue, green, brown), all at
similar saturation and similar value, no accent, no complementary tension, nothing that says
"someone decided this."

### 1.6 The clouds read as broken texture, not clouds
`tex_sky` draws 8-px axis-aligned rectangles of pale blue in a horizontal band. They have hard
edges, uniform value, no vertical structure, no lit/shadow side, and they stop abruptly at the
band boundary (`band = 1 - |ty - 0.34| * 1.7`). In `tree.png` and `ground.png` they look exactly
like decompression artifacts. The *gradient* underneath them is the single genuinely good thing
in the current renderer — keep the gradient, delete these clouds entirely.

### 1.7 The crate is a debug checkerboard
`tex_checker(64,64,4)` at values 210/70. This is a *diagnostic* texture — its whole purpose is
to make affine warping visible. Shipping it means the hero prop in every screenshot has zero
material identity, zero color, and a value contrast (3:1) so violent it pulls the eye away from
everything else in frame.

### 1.8 The tree is a hexagon on a stick
Flat single-color canopy `(58,138,62)`, flat single-color trunk, no taper, no value break
between the top and underside of the canopy, no branch, no asymmetry. It has no silhouette
interest and reads as a 2D shape pasted onto a 3D scene. A tree at PS1 poly counts can be
gorgeous — see below — but it needs a *shape*, a top-to-bottom value gradient, and at least one
asymmetric element.

### 1.9 Nothing is grounded
No contact shadow of any kind. The crate and the tree float. A **single dark quad on the ground
beneath every object** (5 triangles for a blob, or 2 for a quad) would fix this instantly and is
the highest value-per-triangle spend available anywhere in this project.

### 1.10 The composition is a null composition
Camera at eye height, subject dead centre, horizon on the exact middle line, no foreground
framing element, no verticality, no leading line, nothing at the edges. Even a perfect renderer
photographs badly from this angle. See §10 (Money Shots) for what the camera should be doing.

---

## 2. THE TECHNICAL SUBSTRATE (read this before designing anything)

These facts constrain every art decision. They are derived from `wobbleweed/src/geom.hml`,
`scene_gpu.hml`, and `sdl.hml`.

### 2.1 Vertex color MULTIPLIES the texture. You can only darken. Never brighten.
`SDL_RenderGeometry` modulates: `out = texel * vertexColor`. Vertex color is u8 per channel.
Therefore:

> **RULE T1 — Every texture in the atlas is authored at its FULL-SUN NOON appearance.**
> The albedo you paint *is* the brightest that surface will ever be. All shading, all fog tint,
> all time-of-day, all shadow comes from multiplying that value *down*.

Corollary: `ambient + sun·max(0, N·L)` must peak at exactly `1.0` per channel and never
exceed it. Corollary 2: a texture authored dark can never be made bright — so **no albedo in
the world atlas may have a luminance below ~72**, or its shadow side (ambient floor ≈ 0.35)
lands at luminance 25 and becomes an unreadable black hole.

### 2.2 Vertex ALPHA is free fog. This is the single most important technical insight in this document.
`put_vert` currently hard-codes alpha to 255 at byte offset 11. It doesn't have to.

Because `geom.hml` sorts **back-to-front (painter's algorithm)** and the sky quad is drawn
first, a triangle drawn with `alpha < 255` under `SDL_BLENDMODE_BLEND` composites over
*whatever is already behind it* — which, at the horizon, is the sky, and in the mid-field is
already-fogged geometry. Successive back-to-front `over` operations are **exactly the correct
compositing order for atmospheric perspective.**

> **RULE T2 — Distance fog is implemented as per-vertex alpha, costs zero extra triangles, and
> is mathematically correct because of the painter's sort.**

Required engine patch (small):
```
sdl.hml:   SDL_SetRenderDrawBlendMode(ren, 1 /*SDL_BLENDMODE_BLEND*/)
           SDL_SetTextureBlendMode(tex, 1) in upload_texture()
           (add: extern fn SDL_SetTextureBlendMode(tex: ptr, mode: i32): i32;
                 extern fn SDL_SetRenderDrawBlendMode(ren: ptr, mode: i32): i32;)
geom.hml:  put_vert writes  ptr_write_u8(ptr_offset(buf, o+11, 1), v.a & 255)
           (default v.a = 255 everywhere it isn't set)
```

### 2.3 Blend mode is a property of the SDL texture, therefore **blend mode is a material**.
There is no per-triangle blend state. This is actually a gift: it forces a clean material model.

> **RULE T3 — The entire game ships FOUR SDL textures.**
> | # | Texture | Size | Blend mode | Contents |
> |---|---------|------|------------|----------|
> | 1 | `ATLAS_WORLD` | 256×256 | `BLEND` | 64 tiles of 32×32. All opaque world surfaces + foliage cutouts. |
> | 2 | `ATLAS_FX` | 128×128 | `ADD` | 64 tiles of 16×16. Muzzle flash, tracer, glow cards, embers, emissive eyes, loot beams, lightning. |
> | 3 | `ATLAS_HUD` | 128×128 | `BLEND` | 4×6 font, 8×12 font, icons, crosshair parts, minimap chrome, vignette gradient strip. |
> | 4 | `TEX_SKY` | 512×160 | none (opaque) | Panorama: gradient + clouds + sun/moon + stars. Re-baked on time-of-day tick. |

### 2.4 Draw calls come from texture *runs* after the depth sort — so render in fixed layers.
`batch_flush` emits one `SDL_RenderGeometry` per run of same-texture triangles *after* sorting
by depth. If world and FX triangles interleave in depth, you get dozens of draw calls.

> **RULE T4 — Four render layers, each depth-sorted only within itself, flushed in order:**
> 1. `LAYER_SKY` — 2–4 triangles, `TEX_SKY`, no sort.
> 2. `LAYER_WORLD` — everything opaque + alpha-fogged, `ATLAS_WORLD`, back-to-front sort.
> 3. `LAYER_FX` — additive, `ATLAS_FX`, back-to-front sort (order barely matters for additive).
> 4. `LAYER_HUD` — screen space, `ATLAS_HUD` + `ATLAS_FX`, insertion order, no sort.
>
> Result: **5–7 draw calls per frame, total.** Also artistically correct: FX always glow *over*
> the world, HUD always over everything.

### 2.5 UVs cannot wrap. Tiling is per-quad.
`SDL_RenderGeometry` on SDL2's software renderer clamps outside [0,1], and we're using an atlas
anyway. Therefore a texture repeat = an extra quad = 2 more triangles.

> **RULE T5 — Terrain detail comes from VERTEX COLOR, not from texture repetition.**
> Ground quads are **4 m × 4 m** with UV 0..1. Never subdivide the ground to get more texture
> detail; subdivide only where you want more *lighting* detail. Per-vertex color variation
> (hue/value jitter keyed off world position) is free and gives the ground the large-scale
> patchiness that noise cannot.

Also: inset all atlas UVs by **half a texel** (`+0.5/256`, `-0.5/256`) to prevent nearest-
neighbour rounding from sampling the neighbouring tile.

### 2.6 Fog distance IS the triangle budget.
Visible ground quads ≈ `(π/4) · FOG_FAR² / 16`, doubled for triangles.

| `FOG_FAR` | ground tris | headroom for props/enemies/FX/HUD (budget 2500) |
|---|---|---|
| 26 m (night) | ~66 | ~2400 |
| 48 m (overcast) | ~226 | ~2270 |
| 72 m (noon, **shipping cap**) | ~508 | ~1990 |
| 90 m | ~795 | ~1700 |
| 120 m | ~1414 | ~1080 — **too expensive, forbidden** |

> **RULE T6 — `FOG_FAR` never exceeds 72 m. The camera far plane is set to `FOG_FAR * 1.06`,
> not the current hard-coded 200.0.** Nothing may ever pop into existence unfogged.

### 2.7 Per-vertex dynamic point lights are nearly free, and they are our best-looking feature.
Lighting is already per-vertex CPU work. Adding `N` point lights costs one subtract, one dot,
one reciprocal-ish attenuation per vertex per light. At 2500 triangles that's affordable for
**up to 4 simultaneous dynamic lights.** A muzzle flash that genuinely lights the wall next to
you at night is the single most impressive thing this engine can do. Budget for it from day one.

### 2.8 There is no z-buffer, no per-pixel anything, no shaders, no readback.
All post-processing must be screen-space geometry. See §9.

---

## 3. THE MASTER PALETTE

Authored as full-sun-noon albedo (Rule T1). All values are the *texture* color; the renderer
only ever darkens them.

### 3.1 Design constraints on the palette
- **No pure hues.** No `(0,255,0)`, no `(0,0,255)`, no `(255,0,0)` anywhere except the two
  designated UI danger colors.
- **Warm world, cool sky, violet threat.** Terrain/flora/architecture sit in yellow-green
  through ochre through warm grey. The sky and shadows are cool. Enemies and loot are violet.
- **Each family is a 3–4 step value ramp of a single tinted hue.** A texture picks steps from
  *one* family plus at most one accent from another. This is what makes it look authored.
- **Minimum albedo luminance 72** (Rule T1 corollary).

### 3.2 SKY & ATMOSPHERE
| Name | Hex | RGB | Use |
|---|---|---|---|
| `SKY_ZENITH` | `#2C5FB8` | 44, 95, 184 | Top of noon gradient |
| `SKY_MID` | `#4E8FD6` | 78, 143, 214 | Mid band |
| `SKY_HORIZON` | `#A8D2E8` | 168, 210, 232 | Horizon band; also the noon fog target |
| `CLOUD_LIT` | `#F2F0E4` | 242, 240, 228 | Sunlit cloud top — **warm white, never `#FFFFFF`** |
| `CLOUD_MID` | `#D3D8DE` | 211, 216, 222 | Cloud body |
| `CLOUD_SHADOW` | `#96A3B8` | 150, 163, 184 | Cloud underside |
| `SUN_DISC` | `#FFF4C8` | 255, 244, 200 | Sun core (only place near-white is allowed) |
| `SUN_HALO` | `#FFD98A` | 255, 217, 138 | Sun corona |
| `MOON_DISC` | `#DCE4F0` | 220, 228, 240 | Moon |
| `MOON_MARE` | `#A8B4C8` | 168, 180, 200 | Moon craters |
| `STAR_BRIGHT` | `#FFFFF0` | 255, 255, 240 | Tier-1 stars |
| `STAR_DIM` | `#8C9AB8` | 140, 154, 184 | Tier-3 stars |

### 3.3 TERRAIN
| Name | Hex | RGB | Use |
|---|---|---|---|
| `GRASS_HI` | `#9FB84A` | 159, 184, 74 | Grass highlight tufts |
| `GRASS_MID` | `#7A9636` | 122, 150, 54 | **Grass base — the game's most-seen color** |
| `GRASS_LO` | `#516327` | 81, 99, 39 | Grass shadow clumps |
| `GRASS_DRY` | `#B8A855` | 184, 168, 85 | Dry patches, trails, seams |
| `DIRT_HI` | `#B08A54` | 176, 138, 84 | Dirt highlight |
| `DIRT_MID` | `#8A6840` | 138, 104, 64 | Dirt base |
| `DIRT_LO` | `#5C452A` | 92, 69, 42 | Dirt shadow / clod |
| `SAND` | `#D8C68E` | 216, 198, 142 | Beach, desert, path |
| `SAND_LO` | `#A8945F` | 168, 148, 95 | Sand shadow |
| `MUD` | `#6A5840` | 106, 88, 64 | Wet ground (min-luminance floor respected) |
| `SNOW_HI` | `#EAF0F6` | 234, 240, 246 | Snow lit |
| `SNOW_LO` | `#B6C4D4` | 182, 196, 212 | Snow shadow — **blue, not grey** |

### 3.4 FOLIAGE
| Name | Hex | RGB | Use |
|---|---|---|---|
| `LEAF_HI` | `#8CC44E` | 140, 196, 78 | Canopy top |
| `LEAF_MID` | `#5A9A3C` | 90, 154, 60 | Canopy body |
| `LEAF_LO` | `#356B2E` | 53, 107, 46 | Canopy underside |
| `PINE_HI` | `#4E8468` | 78, 132, 104 | Conifer lit — **teal-shifted, distinct from deciduous** |
| `PINE_LO` | `#2E5A4A` | 46, 90, 74 | Conifer shadow |
| `LEAF_AUTUMN` | `#CE7E30` | 206, 126, 48 | Autumn / dead accent |
| `LEAF_SICK` | `#9AA84A` | 154, 168, 74 | Diseased zone flora |
| `BARK_HI` | `#96724A` | 150, 114, 74 | Trunk lit side |
| `BARK_LO` | `#5A422C` | 90, 66, 44 | Trunk shadow side |
| `NIGHTSHADE_FLORA` | `#7A4A9E` | 122, 74, 158 | The plant itself (albedo; the *glow* is in `ATLAS_FX`) |

### 3.5 STONE & CONCRETE
| Name | Hex | RGB | Use |
|---|---|---|---|
| `STONE_HI` | `#B0A896` | 176, 168, 150 | Warm stone lit |
| `STONE_MID` | `#867E6C` | 134, 126, 108 | Warm stone body |
| `STONE_LO` | `#565044` | 86, 80, 68 | Warm stone crevice |
| `GRANITE_HI` | `#8E96A4` | 142, 150, 164 | Cool stone lit |
| `GRANITE_LO` | `#565E6E` | 86, 94, 110 | Cool stone shadow |
| `STONE_MOSS` | `#66744A` | 102, 116, 74 | Moss on stone |
| `CONCRETE_HI` | `#C6C0AE` | 198, 192, 174 | Concrete lit |
| `CONCRETE_MID` | `#9A9484` | 154, 148, 132 | Concrete body |
| `CONCRETE_LO` | `#605A4E` | 96, 90, 78 | Concrete stain / seam |
| `RUST` | `#A05230` | 160, 82, 48 | Corrosion streak |
| `RUST_DARK` | `#6E3A22` | 110, 58, 34 | Deep corrosion |

### 3.6 WOOD & MANMADE
| Name | Hex | RGB | Use |
|---|---|---|---|
| `WOOD_HI` | `#A67C4C` | 166, 124, 76 | Plank lit |
| `WOOD_MID` | `#7E5C36` | 126, 92, 54 | Plank body |
| `WOOD_LO` | `#584022` | 88, 64, 34 | Plank gap / grain |
| `FABRIC_RED` | `#9A3A34` | 154, 58, 52 | Awnings, banners (hub warmth) |
| `FABRIC_CREAM` | `#D8CCA8` | 216, 204, 168 | Tents, canvas |
| `PAINT_TEAL` | `#3E8C8A` | 62, 140, 138 | Hub building trim — cozy accent |
| `PAINT_OCHRE` | `#C89A44` | 200, 154, 68 | Hub building trim |
| `ROOF_TILE` | `#8E4A3C` | 142, 74, 60 | Hub roofing |

### 3.7 METAL
| Name | Hex | RGB | Use |
|---|---|---|---|
| `STEEL_HI` | `#C4C8D0` | 196, 200, 208 | Metal specular band |
| `STEEL_MID` | `#8A909A` | 138, 144, 154 | Metal body |
| `STEEL_LO` | `#565C68` | 86, 92, 104 | Metal shadow |
| `GUNMETAL_HI` | `#7A8088` | 122, 128, 136 | Weapon receiver lit |
| `GUNMETAL_LO` | `#4A5058` | 74, 80, 88 | Weapon receiver shadow (floor case) |
| `BRASS` | `#C89A3C` | 200, 154, 60 | Cartridges, trim |
| `BRASS_LO` | `#8E6C26` | 142, 108, 38 | Cartridge shadow |
| `POLYMER` | `#5E6058` | 94, 96, 88 | Weapon furniture (green-grey, not black) |

### 3.8 THE NIGHTSHADE ACCENT — the signature
| Name | Hex | RGB | Use |
|---|---|---|---|
| `NS_CORE` | `#C74FFF` | 199, 79, 255 | **The brand color.** Enemy emissive, XP bar, loot beam |
| `NS_MID` | `#8A2BD4` | 138, 43, 212 | Enemy panel accents, rim light color |
| `NS_DEEP` | `#3D1259` | 61, 18, 89 | Corrupted-zone fog tint, enemy shadow tone |
| `NS_HALO` | `#E8A6FF` | 232, 166, 255 | Additive glow card around anything `NS_CORE` |
| `VENOM` | `#6BE07A` | 107, 224, 122 | Secondary accent: health pickups, healing, safe zones |
| `VENOM_HALO` | `#B4FFC0` | 180, 255, 192 | Additive glow for `VENOM` |

**Usage law:** violet and green in this family appear ONLY on things that are (a) hostile, (b)
collectable, or (c) player progression. They never appear as environment decoration except in
designated corrupted zones, where they replace the *fog tint* rather than the surfaces. This is
what makes them read as information at 320×240.

### 3.9 COMBAT & FX (all live in `ATLAS_FX`, additive)
| Name | Hex | RGB | Use |
|---|---|---|---|
| `MUZZLE_CORE` | `#FFF8DC` | 255, 248, 220 | Flash centre — the only near-white in the game |
| `MUZZLE_MID` | `#FFC44A` | 255, 196, 74 | Flash body |
| `MUZZLE_EDGE` | `#FF7020` | 255, 112, 32 | Flash outer petals |
| `TRACER` | `#FFDC6E` | 255, 220, 110 | Bullet tracer streak |
| `IMPACT_SPARK` | `#FFE8A0` | 255, 232, 160 | Ricochet spark |
| `EMBER` | `#FF8A2A` | 255, 138, 42 | Falling embers, fire motes |
| `EXPLO_HOT` | `#FFF4D0` | 255, 244, 208 | Explosion core, frame 1–2 |
| `EXPLO_MID` | `#FF9A30` | 255, 154, 48 | Explosion body, frame 3–5 |
| `EXPLO_COOL` | `#B04A20` | 176, 74, 32 | Explosion dying, frame 6–8 |
| `LIGHTNING` | `#E8F0FF` | 232, 240, 255 | Storm flash overlay |

### 3.10 BLOOD & GORE (in `ATLAS_WORLD`, opaque decals)
| Name | Hex | RGB | Use |
|---|---|---|---|
| `BLOOD_FRESH` | `#B41E1E` | 180, 30, 30 | Hit spray, fresh decal |
| `BLOOD_MID` | `#7E1418` | 126, 20, 24 | Decal body |
| `BLOOD_DRY` | `#4E1216` | 78, 18, 22 | Old decal, pooled edge (exempt from min-luminance: decals only) |
| `ICHOR` | `#8A3ADC` | 138, 58, 220 | Nightshade-corrupted enemy blood — violet, ties to brand |

### 3.11 UI
| Name | Hex | RGB | Use |
|---|---|---|---|
| `UI_WHITE` | `#F4F4EC` | 244, 244, 236 | Primary text, crosshair, hitmarker (warm white) |
| `UI_DIM` | `#9AA0A6` | 154, 160, 166 | Secondary text, inactive |
| `UI_BLACK` | `#0A0C10` | 10, 12, 16 | Every drop shadow, every plate, every outline |
| `UI_AMBER` | `#FFC444` | 255, 196, 68 | Ammo, objectives, XP numerals |
| `UI_DANGER` | `#FF3B30` | 255, 59, 48 | Low health, kill marker, damage vignette, enemy blips |
| `UI_GOOD` | `#6BE07A` | 107, 224, 122 | Health bar fill, pickups |
| `UI_XP` | `#C74FFF` | 199, 79, 255 | XP bar fill (= `NS_CORE`) |

---

## 4. LIGHTING MODEL

### 4.1 The equation (per vertex, CPU, in `scene_gpu.hml`)

```
N   = world-space normal (normalized)
V   = normalize(eye - worldpos)
L   = SUN_DIR (unit, points TOWARD the sun)

ndl    = max(0, dot(N, L))
up     = max(0, -N.y)                     // faces pointing down catch ground bounce
rim    = pow(1 - max(0, dot(N, V)), 3)    // 0 at facing, 1 at grazing

light  = AMBIENT_RGB
       + SUN_RGB    * ndl
       + BOUNCE_RGB * up
       + RIM_RGB    * rim                 // RIM_RGB is nonzero for ENTITIES only
       + sum over up to 4 dynamic point lights:
             d    = length(lightpos - worldpos)
             att  = max(0, 1 - d / light.radius); att = att * att
             light += light.color * att * max(0.25, dot(N, normalize(lightpos - worldpos)))
             // the 0.25 floor means point lights also fill, not just key — critical for
             // muzzle flashes reading as an omnidirectional pop rather than a hard spot.

light  = clamp(light, 0, 1)               // per channel

// fog (§5) then folds in:
vcolor = light * lerp(1.0, FOG_TINT_MUL, f) * 255
valpha = 255 * (1 - f * FOG_ALPHA_MAX)
```

**Cost check:** two dots + a pow-3 (do it as `t=1-d; t*t*t`) + one clamp per vertex, plus
~5 ops per dynamic light. At 2500 triangles / ~4000 vertices with 2 average dynamic lights this
is ~60k float ops/frame. Negligible compiled.

### 4.2 Invariants
- **`AMBIENT_RGB + SUN_RGB` must equal exactly `(1,1,1)` per channel** at every keyframe. That
  is what makes Rule T1 hold: a surface facing the sun renders at exactly its authored albedo.
- **`AMBIENT_RGB` is the shadow color and it is always the complement of the sun.** Warm sun ⇒
  cool ambient. This one rule is responsible for most of the beauty in retro 3D. Never use grey
  ambient.
- **`BOUNCE_RGB` is the ground's albedo × 0.10–0.16.** Over grass it's olive; over sand it's
  warm ochre; over snow it's pale blue. Applied to downward-facing normals only. This makes
  undersides of leaves, crates, ledges, and character chins pick up the environment for free and
  is the difference between "objects placed in a scene" and "objects that belong in a scene."
- **`RIM_RGB` is zero for terrain and architecture.** It is nonzero for: enemies (`NS_MID` ×
  0.55), NPCs (sky horizon color × 0.35), pickups (`VENOM` × 0.5), and the player's viewmodel
  (sky horizon × 0.25). Rim on the world would look like a bug; rim on entities is *the*
  readability tool.
- **Ambient floor never drops below 0.14 in any channel**, even at deep night, or the image
  goes to pure black and reads as a crash. Night is *blue and dark*, not black.

### 4.3 Faked shadowing (we have no shadow maps and never will)
1. **Contact blob.** Every entity and prop emits a single ground quad (2 tris) directly beneath
   it, alpha-blended, `UI_BLACK` at alpha `0.45 * (1 - height/2.0)`, sized ~1.15× the object's
   footprint, offset +0.02 m above the ground to avoid z-fighting (we have no z-buffer, so this
   is about painter's-sort ordering: force blobs into the sort with a depth epsilon that keeps
   them just in front of the terrain). **This is the highest-value 2 triangles in the project.**
2. **Baked ambient occlusion in vertex color.** When generating terrain and building meshes,
   darken vertices that sit in concave corners or at the base of walls by up to ×0.55 over a
   0.8 m falloff. Free at build time, transforms interiors and building bases.
3. **Directional face darkening on architecture.** Any face whose normal points away from
   `SUN_DIR` gets an extra ×0.88 beyond the `ndl` term. Slightly wrong physically; makes
   buildings read as solid volumes at a glance.
4. **Interior "cave darkness."** Volumes flagged as interior override `AMBIENT_RGB` with a
   local, much darker, hue-shifted ambient and a much shorter `FOG_FAR` (8–14 m). Stepping into
   a bunker should visibly change the entire palette. Blend the override over 0.5 s.

### 4.4 Emissive
Emissives cannot be done with multiply. Emissive surfaces are **extra geometry in `ATLAS_FX`**
drawn in `LAYER_FX` with vertex color `(255,255,255,255)` and additive blend:
- Enemy eyes / core vent: 2–6 tris, `NS_CORE`.
- Window lights in the hub: 2 tris per window, `#FFD8A0`.
- Loot beam: a 4-tri tapered vertical card, `NS_HALO`, alpha pulsing 0.4→0.8 at 0.8 Hz.
- Every emissive of screen size > 6 px gets a **glow card**: a second, larger (2.5–3×), softer
  additive quad drawn behind it. This is our bloom. It is 2 triangles and it is the difference
  between "a bright pixel" and "a light source."

---

## 5. THE DAY/NIGHT CYCLE

A full cycle is **24 real minutes** (1 min = 1 hour). Values interpolate linearly between
keyframes; the *sky panorama* is re-baked incrementally (§7.5).

`SUN_DIR` is given as (x, y, z) unit-ish; y>0 is above horizon. Azimuth rotates through the
cycle so shadows and the sun disc actually move.

### 5.1 Keyframe table

| | **DAWN** 05:30 | **MORNING** 08:00 | **NOON** 12:00 | **GOLDEN** 18:15 | **DUSK** 19:30 | **NIGHT** 22:00 | **DEEP** 02:00 |
|---|---|---|---|---|---|---|---|
| `SUN_DIR` | (0.94, 0.10, 0.32) | (0.66, 0.60, 0.45) | (0.18, 0.96, 0.22) | (-0.72, 0.42, -0.55) | (-0.95, 0.08, -0.30) | (-0.30, -0.55, -0.78) | (0.20, -0.90, 0.39) |
| `SUN_RGB` | (0.80, 0.50, 0.28) | (0.72, 0.64, 0.48) | (0.58, 0.56, 0.50) | (0.76, 0.54, 0.24) | (0.44, 0.24, 0.30) | (0.22, 0.24, 0.34)¹ | (0.14, 0.16, 0.26)¹ |
| `AMBIENT_RGB` | (0.20, 0.18, 0.28) | (0.28, 0.30, 0.38) | (0.42, 0.44, 0.50) | (0.24, 0.22, 0.32) | (0.22, 0.20, 0.34) | (0.16, 0.18, 0.30) | (0.14, 0.15, 0.26) |
| **sum (must ≤1)** | (1.00,0.68,0.56) | (1.00,0.94,0.86) | (1.00,1.00,1.00) | (1.00,0.76,0.56) | (0.66,0.44,0.64) | (0.38,0.42,0.64) | (0.28,0.31,0.52) |
| `BOUNCE_RGB` (grass) | (0.09, 0.08, 0.04) | (0.11, 0.13, 0.06) | (0.13, 0.16, 0.07) | (0.12, 0.09, 0.04) | (0.06, 0.05, 0.05) | (0.03, 0.04, 0.06) | (0.02, 0.03, 0.05) |
| `FOG_TINT_MUL` | (0.86, 0.62, 0.52) | (0.82, 0.86, 0.94) | (0.76, 0.84, 0.94) | (0.96, 0.72, 0.44) | (0.52, 0.42, 0.62) | (0.18, 0.22, 0.36) | (0.13, 0.16, 0.30) |
| `FOG_NEAR` | 8 m | 14 m | 20 m | 12 m | 6 m | 4 m | 3 m |
| `FOG_FAR` | 52 m | 66 m | **72 m** | 64 m | 40 m | 26 m | 22 m |
| `FOG_ALPHA_MAX` | 1.0 | 1.0 | 1.0 | 1.0 | 0.90 | 0.55² | 0.45² |
| `SKY_ZENITH` | `#2A3A72` (42,58,114) | `#3268C2` (50,104,194) | `#2C5FB8` (44,95,184) | `#2E4A8E` (46,74,142) | `#231C46` (35,28,70) | `#0C1028` (12,16,40) | `#080A1E` (8,10,30) |
| `SKY_MID` | `#7A5A96` (122,90,150) | `#5A96DA` (90,150,218) | `#4E8FD6` (78,143,214) | `#8A5A82` (138,90,130) | `#4A2C56` (74,44,86) | `#141A38` (20,26,56) | `#0E1230` (14,18,48) |
| `SKY_HORIZON` | `#E8A468` (232,164,104) | `#A8CCE4` (168,204,228) | `#A8D2E8` (168,210,232) | `#FF9E44` (255,158,68) | `#9E4E52` (158,78,82) | `#26304E` (38,48,78) | `#161C34` (22,28,52) |
| `CLOUD_LIT` | `#FFD0A0` (255,208,160) | `#F2F0E4` (242,240,228) | `#F2F0E4` (242,240,228) | `#FFC070` (255,192,112) | `#B4707A` (180,112,122) | `#3A4260` (58,66,96) | `#2A3050` (42,48,80) |
| `CLOUD_SHADOW` | `#8E6E88` (142,110,136) | `#A8B4C6` (168,180,198) | `#96A3B8` (150,163,184) | `#8E5A72` (142,90,114) | `#4E3450` (78,52,80) | `#1A2038` (26,32,56) | `#12182C` (18,24,44) |
| `STAR_ALPHA` | 0.15 | 0.0 | 0.0 | 0.0 | 0.35 | 1.0 | 1.0 |
| `SUN/MOON` | sun, halo huge | sun | sun, small halo | sun, halo huge | sun setting | moon | moon high |

¹ At night `SUN_RGB` is the **moon** term; `SUN_DIR` still drives it (use `-SUN_DIR` so the moon
opposes the sun and the sky's key light direction stays sane).
² At night `FOG_ALPHA_MAX < 1` deliberately: we do *not* want distant geometry to fade to the
near-black sky and disappear entirely — silhouettes must survive. The rest of the fog at night
comes from `FOG_TINT_MUL`, which is very dark, so the multiply does the work. See §6.3.

### 5.2 Weather variants (override on top of the ToD keyframe)

| | **OVERCAST** | **RAIN** | **STORM** | **NIGHTSHADE BLOOM**³ |
|---|---|---|---|---|
| `SUN_RGB` × | 0.42 | 0.30 | 0.20 | 0.55 |
| `AMBIENT_RGB` | lerp 0.65 → (0.58,0.59,0.62) | lerp 0.7 → (0.44,0.46,0.52) | lerp 0.8 → (0.30,0.31,0.38) | lerp 0.6 → (0.22,0.14,0.32) |
| `FOG_TINT_MUL` × | (0.94,0.95,0.97) grey | (0.80,0.84,0.90) | (0.60,0.62,0.72) | (0.66,0.40,0.92) **violet** |
| `FOG_NEAR / FAR` | 10 / 48 m | 6 / 34 m | 3 / 20 m | 5 / 30 m |
| Extra | — | 40 rain streak sprites | rain + lightning | violet emissive flora + drifting motes |

³ `NIGHTSHADE BLOOM` is not weather, it's a **corrupted-zone override** that fades in over 3 s
as the player crosses the boundary. It is the game's signature environmental state.

**Lightning (storm only, every 4–11 s):** for 2 frames set `AMBIENT_RGB = (0.90, 0.92, 1.00)`
and `SUN_RGB = (0.10,0.08,0.00)`, draw a full-screen `LIGHTNING` additive quad at alpha 0.55,
then 1 frame at ambient (0.55,0.57,0.66), then return. Total cost: 2 triangles and a variable
change, for the single most dramatic visual in the game. Thunder audio delayed by distance.

### 5.3 What the cycle is *for*
- **Pacing.** Night has `FOG_FAR = 26 m`, which is a *different game*: close-quarters, tense,
  muzzle flashes as the primary light source. Day is exploration and long sightlines.
- **Performance.** Night costs ~1/8 the ground triangles of noon. The cycle is a free
  performance valve.
- **Screenshots.** Golden hour and dusk are what people will post. Bias the tutorial, the hub
  reveal, and any scripted vista to land at `GOLDEN`.

---

## 6. FOG — THE MOST IMPORTANT TOOL IN THIS PROJECT

### 6.1 The curve
```
d  = distance(camera, vertex)          // true radial distance, not view-z; radial avoids
                                       // the "fog gets thinner at the screen edges" artifact
t  = clamp((d - FOG_NEAR) / (FOG_FAR - FOG_NEAR), 0, 1)
f  = t * t * (3 - 2*t)                 // smoothstep: crisp near field, fast far falloff
```
Why smoothstep and not linear: linear fog puts visible haze on things 25 m away, which
destroys mid-range target readability (a CoD sin). Smoothstep keeps the first ~40% of the range
essentially clear, then falls off hard. Why not exponential: exponential never reaches 1, so
geometry never fully disappears and you get a visible "wall of not-quite-gone" at the far
plane.

### 6.2 Application (two channels, both from the same `f`)
```
vcolor.rgb = light.rgb * lerp(1.0, FOG_TINT_MUL, f)
vcolor.a   = 255 * (1 - f * FOG_ALPHA_MAX)
```
- The **tint multiply** re-hues distant geometry toward the atmosphere. At noon that means
  distant hills desaturate and go slightly blue. At golden hour they go orange. At night they go
  near-black-blue.
- The **alpha** dissolves geometry into whatever is behind it — the sky at the horizon, or
  already-fogged geometry in the mid-field. Correct `over` compositing because of the painter's
  sort (Rule T2).

Both are needed. Tint alone can't reach the sky's brightness (multiply only darkens). Alpha
alone leaves distant geometry the wrong *hue* until it's nearly gone.

**Optimization:** if `f < 0.02`, force `a = 255`. This makes the entire near field opaque and
skips the software renderer's blend path for the majority of on-screen pixels.

### 6.3 Night is different, deliberately
At night the sky is `#0C1028` — nearly black. If distant geometry faded fully to it, the world
would become a featureless void and the player would feel blind, not atmospheric. So at night:
- `FOG_ALPHA_MAX = 0.55` — geometry never fully dissolves; a faint silhouette always survives.
- `FOG_TINT_MUL = (0.18, 0.22, 0.36)` — very dark and very blue; the multiply does the heavy
  lifting and preserves *shape* while killing *detail*.
- The result: distant trees read as blue-black silhouettes against a slightly-less-black sky.
  That is the correct and beautiful night look, and it is what makes a muzzle flash feel like an
  event.

### 6.4 Height fog (ground mist) — cheap and gorgeous
Add a second, independent fog term keyed on world Y:
```
h  = clamp((MIST_TOP - vertex.y) / (MIST_TOP - MIST_BOTTOM), 0, 1)
fh = h * h * MIST_DENSITY
f  = max(f, fh)        // combine by max, not add — avoids double-darkening
```
`MIST_BOTTOM = terrain height`, `MIST_TOP = terrain + 1.6 m`, `MIST_DENSITY` 0.0 at noon, 0.55
at dawn, 0.7 at night, 0.85 in valleys/swamp biomes. Effect: valleys fill with mist, hilltops
stand clear, and walking downhill visibly submerges you. Cost: two subtractions per vertex.
**This is the cheapest "wow" in the entire document.**

### 6.5 What fog buys us
1. It hides the draw distance, so `FOG_FAR = 72 m` feels like a world, not a box.
2. It creates depth from a flat palette, replacing the aerial perspective we can't compute.
3. It's a triangle budget lever (§2.6).
4. It's a *mood* lever — the same terrain at NOON/GOLDEN/NIGHT/STORM reads as four locations.
5. It disguises geometry popping. Chunks stream in at `FOG_FAR`, where `f = 1.0` and they are
   invisible. **Never stream in a chunk closer than `FOG_FAR`.**

### 6.6 Fog anti-rules
- Never fog the sky quad (it *is* the fog target).
- Never fog the HUD or the viewmodel.
- Never let `FOG_NEAR` drop below 3 m — fog on your own gun barrel looks broken.
- Fog color must always be derived from the sky's horizon band at that time of day, tinted
  toward the ambient. A fog color that doesn't match the horizon produces a visible band at the
  skyline and is the classic amateur tell.

---

## 7. TEXTURE RULES & GENERATORS

### 7.1 Hard rules
1. **Tile size 32×32** for world surfaces. 16×16 for FX and small props. 64×64 only for hero
   assets (the player's weapon, a boss, the hub's signature building) — max 4 such tiles.
2. **Texel density: 1 texel = 4 cm** on walls/props (32 px tile = 1.28 m), **1 texel = 12 cm**
   on ground (32 px tile = 3.84 m ≈ one 4 m ground quad). Consistency here is what makes a world
   feel coherent; inconsistent density is instantly noticeable even at 320×240.
3. **≤ 12 distinct colors per tile**, chosen from at most 2 palette families (§3) plus black.
4. **Structure lives at 4–10 texel wavelength.** Anything finer than 3 texels must be *grain*
   (±6 luminance) not *structure*. This is the fix for the shimmer described in §1.2.
5. **Every tile has a value range of at least 60 luminance and no more than 130.** Less and it
   reads flat; more and it fights the lighting.
6. **Ordered dither between adjacent ramp steps, always.** A 4×4 Bayer threshold at the boundary
   between two palette steps is the single most PS1-authentic texture technique and it costs
   one array lookup.
7. **Half-texel UV inset** on every atlas tile (Rule T5).
8. **No tile may be a solid color.** Even "concrete" gets grain, a seam, and a stain.

### 7.2 Shared primitives (pseudocode, Hemlock-shaped)

```
// 4x4 Bayer ordered-dither threshold matrix, 0..15 normalized to 0..1
BAYER4 = [ 0, 8, 2,10,
          12, 4,14, 6,
           3,11, 1, 9,
          15, 7,13, 5 ]
fn bayer(x, y) -> f64 { return BAYER4[(y & 3) * 4 + (x & 3)] / 16.0 }

// integer hash -> 0..1  (reuse wobbleweed's hash2, it's fine)
fn h01(x, y, seed) -> f64 { return hash2(x * 73 + seed, y * 151 + seed * 7) / 255.0 }

// value noise: hash lattice + smoothstep interpolation. `period` MUST divide the tile
// size so the texture tiles seamlessly.
fn vnoise(x, y, period, seed) -> f64 {
    fx = x / period; fy = y / period
    ix = floor(fx);  iy = floor(fy)
    tx = fx - ix;    ty = fy - iy
    tx = tx*tx*(3-2*tx); ty = ty*ty*(3-2*ty)
    // wrap lattice coords by (tile_size / period) for seamlessness
    n00 = h01(ix,   iy,   seed); n10 = h01(ix+1, iy,   seed)
    n01 = h01(ix,   iy+1, seed); n11 = h01(ix+1, iy+1, seed)
    return lerp(lerp(n00,n10,tx), lerp(n01,n11,tx), ty)   // (with ty on the outer lerp)
}

// fractal sum, 2-3 octaves ONLY (more is wasted at 32px)
fn fbm(x, y, period, seed) -> f64 {
    return vnoise(x,y,period,seed) * 0.60
         + vnoise(x,y,period/2,seed+31) * 0.28
         + vnoise(x,y,period/4,seed+97) * 0.12
}

// Quantize a 0..1 value onto an N-step palette ramp WITH dither at the boundaries.
// `ramp` is an array of RGB triples, dark -> light.
fn ramp_pick(ramp, v, x, y) -> rgb {
    s   = v * (len(ramp) - 1)
    i   = floor(s)
    frac= s - i
    if (frac > bayer(x, y)) { i = i + 1 }        // <-- THE dither. This is the whole trick.
    return ramp[clamp(i, 0, len(ramp)-1)]
}

// final grain pass, applied to every tile
fn grain(rgb, x, y, amt) -> rgb {
    g = (hash2(x*3+1, y*5+2) % (2*amt+1)) - amt   // amt = 6 typical
    return clamp_rgb(rgb.r+g, rgb.g+g, rgb.b+g)
}
```

### 7.3 The generators

Every generator returns a 32×32 tile written into `ATLAS_WORLD` at cell (cx, cy).

#### GRASS — replaces the current static
```
ramp = [GRASS_LO, GRASS_MID, GRASS_MID, GRASS_HI]   // MID doubled: it dominates
for y in 0..31, x in 0..31:
    // large clump structure (period 16 -> 2 clumps per tile) + medium (period 8)
    n = fbm(x, y, 16, SEED_GRASS)
    c = ramp_pick(ramp, n, x, y)
    // BLADES: short vertical 2-3px strokes of the next-lighter step, sparse
    if (h01(x, y, 11) > 0.90):
        len = 2 + (hash2(x,y) % 2)
        for k in 0..len: setpixel(x, y-k, GRASS_HI)      // drawn as a pass after the base
    // DRY PATCH: a second low-freq field, thresholded hard
    if (fbm(x, y, 32, SEED_DRY) > 0.66):
        c = blend(c, GRASS_DRY, 0.65)
    c = grain(c, x, y, 5)
```
Result: readable clumps at ~8 px, sparse blade highlights that survive nearest sampling, and
low-frequency dry patches that break up the tile repeat. Variance is ±30, not ±70.

#### DIRT / PATH
```
ramp = [DIRT_LO, DIRT_MID, DIRT_MID, DIRT_HI]
n = fbm(x, y, 12, SEED_DIRT) * 0.75 + vnoise(x, y, 4, SEED_DIRT+5) * 0.25
c = ramp_pick(ramp, n, x, y)
// PEBBLES: 6-9 per tile, 2x2 or 3x2 blobs of DIRT_HI with a 1px DIRT_LO shadow below-right
for each pebble p: blob(p.x, p.y, DIRT_HI); pixel(p.x+1, p.y+1, DIRT_LO)
c = grain(c, x, y, 6)
```

#### STONE / ROCK
```
ramp = [STONE_LO, STONE_MID, STONE_MID, STONE_HI]
// Worley-ish cracked look without a real Worley: two offset fbm fields differenced
a = fbm(x, y, 16, SEED_STONE)
b = fbm(x+7, y+13, 16, SEED_STONE+41)
n = 0.5 + (a - b) * 0.9                        // ridged, produces crack-like valleys
c = ramp_pick(ramp, n, x, y)
// CRACKS: where |a-b| is very small, force the darkest step -> thin dark seams
if (abs(a - b) < 0.035): c = STONE_LO
// MOSS: only on the top 40% of the tile (assumes the tile is used on upward faces)
if (y < 13 and fbm(x, y, 10, SEED_MOSS) > 0.58): c = blend(c, STONE_MOSS, 0.7)
c = grain(c, x, y, 5)
```
The `a - b` ridge trick gives believable cracked rock in ~8 lines. Use it everywhere you want
"cracked/veined/marbled."

#### WOOD PLANK
```
PLANK_H = 8                                   // 4 planks per 32px tile
ramp = [WOOD_LO, WOOD_MID, WOOD_MID, WOOD_HI]
for y, x:
    plank = y / PLANK_H
    // per-plank tone jitter -> planks read as individual boards
    tone = 0.5 + (h01(plank, 0, SEED_PLANK) - 0.5) * 0.45
    // GRAIN: stretched noise, 6x wider than tall
    g = vnoise(x, y*6 + plank*97, 12, SEED_GRAIN)
    n = tone * 0.65 + g * 0.35
    c = ramp_pick(ramp, n, x, y)
    // GAP: 1px dark line between planks + 1px highlight below it
    if (y % PLANK_H == 0)      c = WOOD_LO * 0.6
    else if (y % PLANK_H == 1) c = WOOD_HI
    // NAILS: 2 per plank at fixed x, 1px STEEL_LO
c = grain(c, x, y, 4)
```

#### METAL PANEL
```
ramp = [STEEL_LO, STEEL_MID, STEEL_MID, STEEL_HI]
// Metal reads as metal because of a BROAD VERTICAL VALUE SWEEP (fake anisotropic
// specular), not because of noise.
sweep = 0.30 + 0.70 * (1 - abs(y - 10) / 22)     // bright band near the top third
n = sweep * 0.72 + vnoise(x*4, y, 16, SEED_METAL) * 0.28   // horizontal brushing
c = ramp_pick(ramp, n, x, y)
// PANEL LINES: 1px STEEL_LO border inset 1px, + 1px STEEL_HI highlight inside it
// RIVETS: 4 corners, 2x2, STEEL_HI with STEEL_LO on the lower-right texel
// RUST STREAKS: vertical, starting at rivets, fbm-masked, blend to RUST/RUST_DARK
if (fbm(x, y*3, 14, SEED_RUST) > 0.62): c = blend(c, RUST, 0.55)
c = grain(c, x, y, 4)
```
The sweep is essential. Without a broad bright-to-dark gradient across the tile, "metal" is
indistinguishable from "grey concrete."

#### CONCRETE
```
ramp = [CONCRETE_LO, CONCRETE_MID, CONCRETE_MID, CONCRETE_HI]
n = fbm(x, y, 20, SEED_CONC) * 0.55 + 0.45      // low contrast base
c = ramp_pick(ramp, n, x, y)
// AGGREGATE: single-texel darker specks, density 4%
if (h01(x,y,77) > 0.96) c = CONCRETE_LO
// FORM SEAMS: one horizontal and one vertical 1px CONCRETE_LO line at fixed offsets
// WATER STAINING: vertical fbm streaks from the top edge, multiply 0.82, top 60% only
if (y < 20 and fbm(x, y*4, 18, SEED_STAIN) > 0.60) c = c * 0.84
// CHIP: one 3x3 notch of CONCRETE_LO at a corner
c = grain(c, x, y, 5)
```
Concrete without staining and seams reads as fog. The stains are what make it architecture.

#### FOLIAGE CARD (canopy / bush, alpha-cutout)
Foliage is drawn as **cross-quads** (2 intersecting quads, 8 tris) using an alpha-cutout tile.
Because we only have per-vertex alpha and no per-pixel alpha test, **cutout is impossible** —
so foliage tiles must be *opaque and shaped by geometry*, or drawn as a small number of solid
leaf-cluster quads. Decision:
> **Foliage is geometry, not cutouts.** A tree canopy is 3 stacked, rotated, tapered hexagonal
> discs (see §8.4), each with a lit top ramp and dark underside in vertex color. Bushes are 2–3
> low tapered prisms. This costs more triangles but is the only thing that works and it looks
> *better* — it gives real silhouette and real Gouraud shading.

The foliage *texture* is then a simple leaf-mass tile:
```
ramp = [LEAF_LO, LEAF_MID, LEAF_MID, LEAF_HI]
n = fbm(x, y, 8, SEED_LEAF)                    // small clumps = individual leaf masses
c = ramp_pick(ramp, n, x, y)
// dark voids: 5% of texels forced to LEAF_LO*0.7 -> reads as gaps between leaves
if (h01(x,y,53) > 0.95) c = LEAF_LO * 0.7
c = grain(c, x, y, 7)
```

#### SNOW / SAND (soft granular)
```
ramp = [SNOW_LO, SNOW_LO, SNOW_HI, SNOW_HI]    // only 2 real steps -> big dither field
n = fbm(x, y, 24, SEED_SNOW) * 0.8 + 0.1
c = ramp_pick(ramp, n, x, y)                   // the Bayer dither IS the look here
// WIND RIPPLES: sin(x*0.4 + fbm) thresholded, 1px SNOW_HI lines
c = grain(c, x, y, 3)
```
With only two steps and heavy dithering, snow and sand get the classic PS1 checkerboard
gradient. Lean into it.

### 7.4 Atlas layout (`ATLAS_WORLD`, 256×256, 8×8 cells of 32×32)

```
      col0        col1        col2        col3        col4        col5        col6        col7
row0  GRASS_A     GRASS_B     GRASS_DRY   DIRT        PATH        MUD         SAND        SNOW
row1  STONE_A     STONE_B     STONE_MOSS  GRANITE     CLIFF       GRAVEL      COBBLE      RUBBLE
row2  WOOD_PLNK   WOOD_LOG    BARK        LEAF_DECID  LEAF_PINE   LEAF_AUTMN  BUSH        NS_FLORA
row3  CONCRETE    CONC_STAIN  BRICK       METAL_PNL   METAL_RUST  GRATE       PIPE        VENT
row4  ROOF_TILE   PLASTER     FABRIC_RED  FABRIC_CRM  PAINT_TEAL  PAINT_OCHR  WINDOW      DOOR
row5  ENEMY_A     ENEMY_A2    ENEMY_B     ENEMY_B2    ENEMY_C     NPC_A       NPC_B       CIVILIAN
row6  GUN_BODY    GUN_METAL   GUN_WOOD    GUN_POLY    HANDS       AMMO_BOX    CRATE       BARREL
row7  BLOOD_DEC   SCORCH_DEC  BULLET_DEC  SIGN_A      SIGN_B      DEBUG_GRID  (spare)     (spare)
```

`ATLAS_FX` (128×128, 8×8 cells of 16×16): muzzle flash ×3 frames, tracer, impact spark ×2,
explosion ×6 frames, ember, smoke puff ×3, glow card (soft radial) ×2 sizes, enemy eye, loot
beam, rain streak, lightning bolt ×2, dust mote, water splash ×2, healing sparkle, XP mote.

### 7.5 Generation cost & timing
`ATLAS_WORLD` = 65,536 texels × ~35 ops ≈ 2.3 M ops. `TEX_SKY` = 81,920 texels × ~25 ops ≈
2.0 M ops. Compiled, both together are well under 200 ms at boot — acceptable behind a title
card. **The sky must be re-baked as the ToD changes**: regenerate **20 rows per frame** on a
rolling cursor, so a full sky refresh takes 8 frames (133 ms) and never causes a hitch. Upload
only the dirty rows via `SDL_UpdateTexture` with a rect.

### 7.6 On a PNG loader
`wobbleweed/src/png.hml` already exists. **Do not use it for world art.** Procedural generation
is faster to iterate, costs no disk, guarantees palette compliance, and makes variation free
(reseed a tile per biome). The one justified use for PNG would be a hand-authored font/icon
sheet — and even that is cheaper to generate from a packed bitfield table in code. **Ship with
zero image files.** This is a feature, not a limitation: "the entire game's art is generated in
1400 lines of code" is a genuinely great thing to be able to say.

---

## 8. GEOMETRY & SILHOUETTE

### 8.1 The readability math
At 320×240 with `fovy = 1.15 rad`, a 1.8 m tall enemy subtends:

| Distance | Screen height |
|---|---|
| 10 m | 37 px |
| 20 m | 19 px |
| 30 m | 12 px |
| 40 m | 9 px |
| 60 m | 6 px |
| 72 m (`FOG_FAR`) | 5 px, and 100% fogged |

> **RULE S1 — Every enemy must be identifiable by class at 12 px (30 m) and detectable as a
> threat at 6 px (60 m).**

At 6 px an enemy is a *smudge*. Nothing about its geometry survives. The only things that
survive are:
1. **Value contrast against the background** (a dark shape on a light background, or vice versa)
2. **Motion**
3. **An emissive marker** — 2–6 additive triangles from `ATLAS_FX` at `NS_CORE`

> **RULE S2 — Every hostile carries a persistent emissive marker sized ≥ 2 px at 60 m.**
> On a humanoid: two eyes plus a chest core. On a drone: a single rotating ring. This is not a
> gameplay concession; it is the *entire* long-range readability system, and it doubles as the
> game's brand identity. Violet = danger, always, everywhere.

> **RULE S3 — Every hostile has a violet rim light** (`RIM_RGB = NS_MID * 0.55`). Rim peaks at
> grazing angles, which is exactly the silhouette edge, so the enemy is outlined in violet
> against any background. This is our version of CoD's "enemies are always readable" contract.

### 8.2 Silhouette design rules
1. **Asymmetry is mandatory.** A bilaterally symmetric silhouette is unreadable when small
   because it has no orientation cue. Every enemy gets exactly one asymmetric feature: a single
   shoulder pauldron, one oversized arm, a side-mounted antenna, a cocked head.
2. **A distinct head-to-shoulder ratio per class.** This is the primary class read at 12 px.
   - Grunt: narrow head, narrow shoulders, 1:1.6 head:shoulder width
   - Brute: no visible neck, 1:2.8, very wide
   - Scout: tall thin, head above a hunched profile, 1:1.3
   - Drone: no humanoid form at all — a horizontal lozenge
3. **One "signature protrusion" per class**, at least 3 px long at 30 m (≈ 0.45 m in world
   space): Grunt = backpack antenna; Brute = shoulder spines; Scout = long rifle held high;
   Sniper = a bipod / long barrel; Drone = twin side rotors.
4. **Negative space matters more than positive.** A gap between arm and body reads at 12 px; a
   surface detail does not. Design the *holes*.
5. **Value block the model in vertex color at build time.** Head/upper torso brighter, legs
   darker. This gives every character a built-in top-lit gradient that survives any lighting
   condition and prevents them merging into a single blob.
6. **Never black.** Rule T1's minimum-luminance-72 applies hardest here.

### 8.3 Triangle budgets

| Asset | Triangles | Notes |
|---|---|---|
| Enemy humanoid (LOD0, <15 m) | 180 | + 6 emissive |
| Enemy humanoid (LOD1, 15–35 m) | 90 | + 4 emissive |
| Enemy humanoid (LOD2, >35 m) | 28 | box-man + 2 emissive; at 9 px nobody can tell |
| NPC (hub, always LOD0) | 220 | more charm budget, they're static and few |
| Player viewmodel weapon | 260 | it's on screen 100% of the time — spend here |
| Tree (LOD0) | 96 | 3 canopy discs (24 each) + tapered trunk (24) |
| Tree (LOD1) | 34 | 1 canopy disc + 8-sided trunk |
| Tree (LOD2, >45 m) | 8 | 2 crossed quads, vertex-colored, no texture |
| Bush | 22 | |
| Rock | 18 | |
| Crate / barrel | 12 / 24 | |
| Building (hub, modular) | 120–300 | |
| Ground quad | 2 | 4 m × 4 m |
| Contact shadow blob | 2 | mandatory on everything |
| HUD, total | ≤ 250 | §9 |
| Post-FX overlay + vignette | 18 | §10 |

**Frame budget: 2500 triangles.** A typical combat frame: 500 ground + 400 props/trees +
5 enemies × 90 = 450 + 300 building + 250 HUD + 120 FX + 18 post = **2038**. Comfortable.

### 8.4 The tree, specifically (fixing §1.8)
```
Trunk:   6-sided tapered prism, 4 vertical segments, radius 0.22 -> 0.13 m.
         Vertex color: BARK_HI on the +SUN_DIR side, BARK_LO opposite, baked at build time.
         Segment 2 kinks 8-12 degrees in a random direction. NEVER straight.
Canopy:  3 hexagonal discs, radii 2.1 / 1.7 / 1.1 m, at heights 3.4 / 4.4 / 5.1 m,
         each rotated 20 degrees from the last, each offset 0.15-0.3 m laterally in a
         random direction (asymmetry, Rule 8.2.1).
         Each disc has a TOP fan (LEAF_HI at the rim -> LEAF_MID at centre... no:
         LEAF_HI at CENTRE -> LEAF_MID at rim, because the centre catches the sun)
         and a BOTTOM fan baked to LEAF_LO * 0.75.
         The vertical value break between disc top and disc bottom is what turns
         "hexagon" into "mass."
Branch:  ONE visible branch stub, 4 tris, sticking out asymmetrically at 2.6 m.
Shadow:  1 contact blob quad, radius 1.9 m.
Total:   ~96 tris.
```
Plus per-instance variation, free: rotate the whole tree by a random yaw, scale 0.85–1.25, and
jitter the canopy vertex colors ±8%. Twenty trees from one mesh and nobody will notice.

### 8.5 The viewmodel weapon
The single most-looked-at object in the game. Rules:
- **Occupies the lower-right, never more than 38% of screen height, never crossing the crosshair.**
- **Strong top-to-bottom value gradient** baked into vertex color (`GUNMETAL_HI` on top
  surfaces, `GUNMETAL_LO` underneath) so it separates from any background it's held against.
- **A 1-texel `STEEL_HI` specular line** along the top edge of the receiver and barrel. This
  fake highlight is what makes it read as metal at this resolution.
- **Silhouette must be identifiable in a 32×32 inventory icon.** If the SMG and the rifle have
  the same silhouette, redesign one.
- **`RIM_RGB = SKY_HORIZON * 0.25`** so the weapon picks up a subtle edge from the sky and
  never looks pasted on.
- Idle sway: ±2 px at 0.4 Hz, plus a 1 px vertical bob synced to footsteps. Fire kick: the
  weapon translates back 0.06 m and rotates up 4° over 2 frames, returns over 5. Sprint: rotate
  the weapon 35° and drop it 0.1 m, over 6 frames.

### 8.6 Chunk / world geometry
- Chunks are **32 m × 32 m** = 8×8 ground quads = 128 triangles per chunk.
- Terrain height from 2-octave value noise; **the ground mesh must have real height variation**
  (§1.3's real fix) — even ±1.5 m over 32 m completely transforms the read, because per-vertex
  lighting then varies across the ground and the horizon line stops being a ruler edge.
- Chunk vertex colors carry: `ndl` from the terrain normal, baked AO in creases, biome tint, and
  a low-frequency value patchiness (`fbm(worldx, worldz, 24 m)` mapped to ×0.86–1.0). That last
  one is what gives the ground large-scale interest that no 32 px texture can.
- **Chunks activate at `FOG_FAR` and beyond, never closer** (§6.5).

---

## 9. THE HUD

### 9.1 Philosophy
PS1-era FPS UI language: **chunky, high-contrast, hard-edged, drop-shadowed, no anti-aliasing,
no gradients, no transparency except for deliberate plates.** Every element must be readable
against grass, sky, concrete, and a muzzle flash. The technique that guarantees that is a
**1-pixel `UI_BLACK` drop shadow at (+1, +1) on every glyph and every line**, plus a
`UI_BLACK` @ 55% alpha plate behind any text block.

### 9.2 Layout — 320×240, coordinates are (x, y) with (0,0) top-left

```
 0                                                                        319
 0 ┌───────────────────────────────────────────────────────────────────────┐
   │        ┌── COMPASS (100..219, 6..15) ──┐          ┌─ MINIMAP ──────┐  │
   │        │ · · N · · · · · | · · · · E · │          │ (252..311,     │  │
   │        └───────────────────────────────┘          │   8..67)       │  │
   │                                                   └────────────────┘  │
   │                                                   ┌ KILLFEED ───────┐ │
   │                                                   │ (right-aligned  │ │
   │                                                   │  to 311,        │ │
   │                                                   │  y = 74, 82,    │ │
   │                                                   │  90, 98)        │ │
   │                                                   └─────────────────┘ │
   │                                                                       │
   │                        HIT-DIRECTION ARCS                             │
   │                        (radius 48 from centre)                        │
   │                                                                       │
   │                       ·        ·                                      │
120│                    ·    CROSSHAIR   ·      (160, 120)                 │
   │                       ·        ·                                      │
   │                                                                       │
   │                   RELOAD BAR (140..179, 132..134)                     │
   │                                                                       │
   │              INTERACT PROMPT (centred, y = 148)                       │
   │                                                                       │
   │                    XP POPUP "+50" rises 160,206 -> 160,186            │
   │                                                                       │
   │ ┌ HEALTH ────────┐                        ┌─ WEAPON NAME (y=198) ───┐ │
   │ │ ♥ 100          │                        │            AR-9 VESPER  │ │
   │ │ ▓▓▓▓▓▓▓▓▓▓▓▓░░ │                        │ ┌ AMMO ────────────────┐ │ │
   │ └────────────────┘                        │ │           24 / 180   │ │ │
   │        LVL 7  ▓▓▓▓▓▓▓▓░░░░░░ (XP BAR)     └─┴──────────────────────┘ │ │
239└───────────────────────────────────────────────────────────────────────┘
```

### 9.3 Element specifications

| Element | Rect / anchor | Colors | Detail |
|---|---|---|---|
| **Crosshair** | centre (160,120) | `UI_WHITE` fill, `UI_BLACK` 1 px outline | 4 ticks, each 1 px wide × 4 px long, gap = `3 + spread` px from centre. `spread` = 0 (still ADS) → 9 (sprinting/firing). No centre dot by default. 8 tris. |
| **Hitmarker** | centre | `UI_WHITE`; kill = `UI_DANGER` | 4 diagonal ticks at 45°, 4 px long, 4 px gap. 8 frames: 2 hold, 6 alpha-fade. Kill variant is 1.4× scale, red, 12 frames, + a short chime. 8 tris. |
| **Health bar** | x 10–89, y 220–225 (80×6) | fill `UI_GOOD` → `UI_DANGER` below 30% | 1 px `UI_BLACK` border, 1 px inner dark plate. Below 30%: pulse alpha 0.6↔1.0 at 2.4 Hz. 6 tris. |
| **Health numeral** | x 22, y 208, 8×12 font | `UI_WHITE`, `UI_DANGER` < 30 | 3 digits max. Heart icon 8×8 at x 10, y 208. 8 tris. |
| **Ammo, magazine** | right-aligned to x 310, y 206, 8×12 font | `UI_AMBER`, `UI_DANGER` < 25% | Blinks at 4 Hz when < 25%. Up to 3 digits. 6 tris. |
| **Ammo, reserve** | right-aligned to x 310, y 220, 4×6 font | `UI_DIM` | `"/ 180"`. 12 tris. |
| **Weapon name** | right-aligned to x 310, y 196, 4×6 font | `UI_DIM` | Uppercase. Fire-mode glyph (`AUTO`/`SEMI`) to its left in `UI_AMBER`. ~24 tris. |
| **Compass** | x 100–219, y 6–15 | ticks `UI_DIM`, cardinals `UI_WHITE`, objective pip `UI_AMBER` | 120 px strip = 180° of view. Minor tick every 10°, major every 45°, cardinal letters at N/E/S/W in 4×6. Centre marker: a 3 px `UI_WHITE` chevron at x 160, y 4. ~40 tris. |
| **Minimap** | x 252–311, y 8–67 (60×60) | plate `UI_BLACK` @ 55%, border 1 px `UI_WHITE` | Top-down, 64 m across. Player = 5 px `UI_WHITE` triangle at centre, always pointing up (map rotates). Enemies = 2×2 `UI_DANGER` dots, shown only when firing or detected. Objectives = 3×3 `UI_AMBER` diamond, clamped to the rim with a 3 px arrow when off-map. Terrain: nothing — just a dark plate. Cheap and legible. ~34 tris. |
| **Killfeed** | right-aligned to x 311; y = 74, 82, 90, 98 | killer `UI_WHITE`, victim `UI_DIM`, own kills `UI_AMBER` | Max 4 lines, 16 chars each, 4×6 font. 8 px line pitch. Each line lives 5 s then fades over 0.5 s. Weapon icon 8×6 between names. ≤ 128 tris — **the HUD's biggest cost; hard-cap it.** |
| **XP bar** | x 110–209, y 232–235 (100×4) | fill `UI_XP`, plate `UI_BLACK` | 1 px border. Level numeral `LVL 7` at x 82, y 230, 4×6, `UI_AMBER`. On level-up: bar flashes `UI_WHITE` for 4 frames and a `NS_HALO` additive glow card (2 tris) pulses behind it for 20 frames. 6 tris + 24 for text. |
| **XP popup** | starts (160, 206), rises to (160, 186) over 0.8 s | `UI_AMBER` | `"+50"` in 4×6, alpha fades over the last 0.3 s. Max 3 concurrent, stacked 8 px apart. 6 tris each. |
| **Damage vignette** | full screen ring | `UI_DANGER` | 16 triangles forming a border ring, alpha 0 at 42 px inset → `A` at the screen edge. `A = 0.15 + 0.40 * (1 - hp/maxhp)`. On taking a hit, spike `A` by +0.30 for 6 frames. Below 25 % HP, pulse at 1.2 Hz. **16 tris.** |
| **Hit-direction arc** | radius 48 px from centre, 34° wide | `UI_DANGER` | 3 tris per arc, up to 4 concurrent. Points at the attacker in screen space. Full alpha 0.9 for 8 frames, fade over 60. |
| **Reload bar** | x 140–179, y 132–134 (40×3) | fill `UI_WHITE`, plate `UI_BLACK` | Only visible during reload. 4 tris. |
| **Interact prompt** | centred on x 160, y 148, 4×6 | key glyph `UI_AMBER` in a 1 px box, text `UI_WHITE` | `"[E]  PICK UP  AR-9 VESPER"`. `UI_BLACK` @ 60 % plate with 2 px padding. ≤ 60 tris. |
| **Objective marker** | world-projected, clamped to a 16 px screen inset | `UI_AMBER` | 5×5 diamond outline + `"142M"` in 4×6 below it. Off-screen: clamps to the edge and becomes a triangle pointing outward. 10 tris. |
| **Low-ammo / low-health chevron** | screen edges | `UI_DANGER` | 4 short 12 px bars at the mid-points of each screen edge, alpha pulsing. Cheap peripheral alarm. 8 tris. |

**Total worst-case HUD: ~240 triangles.** Within the 250 cap.

### 9.4 Typography
Two fonts, both generated from packed bitfield tables in code, both stored in `ATLAS_HUD`:

- **`FONT_MICRO` — 4×6**, uppercase A–Z, 0–9, and `. , : / % + - [ ] < > ° ♥ ⌁`. 1 px inter-
  character spacing, 8 px line pitch. Used for everything secondary.
- **`FONT_BIG` — 8×12**, digits 0–9 plus `/` and `%` only. Not a scaled-up micro font — it is
  *drawn separately* with a 2 px stroke weight and slightly condensed proportions, so it reads
  as a deliberate display face rather than a blur. Used for health and magazine count.

Both are **hard-edged, no anti-aliasing, 1 px `UI_BLACK` shadow at (+1,+1), always.** Style
reference: the numerals on a 1997 arcade cabinet — square terminals, closed counters, high
x-height. No serifs, no curves finer than 1 px.

### 9.5 HUD juice (the CoD contract)
Every one of these is cheap and every one of them is mandatory:
- **Hitmarker on every damaging hit**, louder/red on kill. Non-negotiable.
- **Crosshair bloom** tied to actual spread. The player must be able to *see* their accuracy.
- **Damage number popups** (optional, `UI_WHITE`, 4×6, rising 12 px over 0.5 s at the hit's
  screen position). Turn on for headshots at minimum.
- **Screen kick on fire**: camera pitch +0.6° over 2 frames, recovering over 6. Plus a 1 px
  screen translation. This is 3 lines of code and it is 40 % of "gunfeel."
- **Low-health desaturation is impossible**, so substitute: vignette pulse + a 1 px `UI_DANGER`
  screen border + audio.
- **Kill confirmation must be triple-redundant**: hitmarker turns red, killfeed line appears,
  XP popup rises. Any one of them can be missed in a firefight.

---

## 10. THE POST-FX STACK

We own no pixels on the GPU path, so post-FX is screen-space geometry. Ordered by
**value per cost** — implement top-down and stop when the frame budget says stop.

| # | Effect | Cost | Verdict |
|---|---|---|---|
| **1** | **Additive glow cards behind every emissive** (our bloom) | 2 tris each, ~20 total | **SHIP. Highest value in the list.** A muzzle flash without a glow card is a bright pixel; with one it's a light source. |
| **2** | **Vignette ring** (16 screen tris, `UI_BLACK`, alpha 0 at 42 px inset → 0.42 at the edge) | 16 tris, one blended edge fill | **SHIP, always on.** Focuses the eye at the centre, hides the frame edge, adds instant "cinematic." Combine the static vignette and the damage vignette into the same 16 triangles by summing their alpha and lerping their color toward `UI_DANGER`. |
| **3** | **Composite overlay** — ONE 320×240 texture combining ordered dither, static grain, and (optional) scanlines, drawn as a single full-screen quad in `SDL_BLENDMODE_MOD` | 2 tris, **one full-screen blended fill** | **SHIP, but measure.** This is the pass that restores the PS1 dither look on the GPU path, where `postfx.hml`'s CPU dither can't run. Bake the 4×4 PS1 dither pattern from `postfx.hml` as ±4/255 offsets, plus ±5 static grain. One full-screen blend costs 76,800 pixels of blend math — profile it; if it costs > 12 % of frame time, make it a settings toggle defaulting on at 720p-window sizes. **Cycle between 3 pre-baked grain variants per frame** for animated grain at zero extra cost. |
| **4** | **Composite edge bleed** — a red-tinted 3 px band on the left screen edge and a cyan-tinted one on the right, alpha 0.10, baked into the *vignette* texture | 0 extra tris | **SHIP.** Free fake chromatic aberration. Sells "this is coming out of an RCA cable." Do not do it across the whole screen — the centre must stay clean. |
| **5** | **Scanlines** — every other row × 0.88, folded into the same texture as #3 | 0 extra tris | **OPTION, default OFF.** Scanlines are a *CRT* affectation, not a PS1 one. At a 3× nearest upscale they eat 50 % of the vertical resolution we barely have. Offer it in settings for the people who want it. |
| **6** | **Interlace / frame-jitter** — alternate the composite overlay's V offset by half a texel each frame | 0 tris | **OPTION, default OFF.** Authentic; also nauseating. |
| **7** | **Radial blur / speed lines** — 8 additive tapered quads from the screen edges during sprint | 8 tris | **SHIP for sprint only.** Alpha 0.18, `UI_WHITE`. Reads as speed; costs nothing. |
| **8** | **Underwater / corrupted-zone tint** — one full-screen `MOD` quad in `NS_DEEP` or a water blue | 2 tris | **SHIP.** The cheapest possible "you are somewhere else" signal. |
| **9** | **Lightning flash** — one full-screen `ADD` quad at `LIGHTNING`, alpha 0.55 for 2 frames | 2 tris | **SHIP.** See §5.2. |
| **10** | **True chromatic aberration, motion blur, depth of field, per-pixel bloom, SSAO** | — | **IMPOSSIBLE. Do not attempt. Do not spend a day discovering this.** |

**Post-FX total: ~50 triangles and 1–2 full-screen blended fills.**

**Order of operations per frame:**
```
1. clear()                                   -> the sky's zenith color (so a dropped sky frame is never black)
2. LAYER_SKY     flush                       (TEX_SKY,     2-4 tris)
3. LAYER_WORLD   sort + flush                (ATLAS_WORLD, ~1400 tris, alpha-fogged)
4. LAYER_FX      sort + flush                (ATLAS_FX,    ~120 tris, additive)
5. composite overlay quad                    (MOD,         2 tris)
6. vignette ring (static + damage summed)    (BLEND,       16 tris)
7. LAYER_HUD     flush, insertion order      (ATLAS_HUD,   ~240 tris)
8. present_geom()
```

---

## 11. THE SKYBOX

`TEX_SKY` is a **512×160** panorama. U spans a full 360° of yaw; V spans zenith (0) to horizon
(1), sampled through a window that scrolls with pitch. Two triangles for the visible quad, four
when it straddles the wrap seam (the existing `emit_sky` logic is correct — keep it, but extend
it to also offset V by pitch).

### 11.1 Gradient stops (V from 0 = zenith to 1 = horizon)
```
V = 0.00   SKY_ZENITH
V = 0.42   SKY_MID            (interpolate 0.00 -> 0.42 with a gamma of 1.35, not linear:
                               real skies change fast near the horizon and slowly overhead)
V = 0.82   lerp(SKY_MID, SKY_HORIZON, 0.55)
V = 0.96   SKY_HORIZON
V = 1.00   SKY_HORIZON * 0.96 (a barely-there darkening right at the horizon line stops the
                               sky and the fog from being *identical*, which reads as a bug)
```
**Every row of the gradient is Bayer-dithered between its two nearest palette steps** (§7.2).
Without this the sky bands visibly, and it's the most-looked-at surface in the game.

### 11.2 Clouds
Two independent layers, both horizontally tileable (lattice period must divide 512):
```
LAYER_FAR:  period 128, drift 0.6 px/s, coverage threshold 0.62, opacity 0.55
LAYER_NEAR: period 64,  drift 1.4 px/s, coverage threshold 0.68, opacity 1.0

for each layer, for each texel:
    n = fbm(u, v*2.6, period, SEED)       // v*2.6 -> horizontally stretched, cloud-shaped
    band = smoothstep applied so clouds concentrate at V 0.25..0.85 and vanish at
           the zenith and at the horizon (the horizon must stay clean for the fog to
           blend into)
    c = n * band
    if c > threshold:
        depth = (c - threshold) / (1 - threshold)        // 0 at the wispy edge, 1 in the core
        // THE CRITICAL PART: a cloud is not one color.
        //   top edge (v decreasing) -> CLOUD_LIT
        //   body                    -> CLOUD_MID
        //   bottom edge             -> CLOUD_SHADOW
        // Compute a vertical gradient WITHIN the cloud by sampling n at (u, v-3):
        above = fbm(u, (v-3)*2.6, period, SEED)
        if (above < threshold)  col = CLOUD_LIT        // this texel is the cloud's top edge
        else if (depth < 0.25)  col = CLOUD_SHADOW     // wispy underside
        else                    col = CLOUD_MID
        // then ramp_pick + Bayer dither against the sky behind it, weighted by depth
        pixel = ramp_pick([sky, CLOUD_SHADOW, CLOUD_MID, CLOUD_LIT], ..., u, v)
```
**The lit-top / shadowed-bottom split is what makes them clouds instead of noise.** This is the
single fix for §1.6. Sun-side clouds additionally get a `SUN_HALO`-tinted edge within 60 px of
the sun's azimuth.

### 11.3 Sun / moon
- **Sun disc:** 9 px radius, `SUN_DISC`, with a **hard edge** (no gradient on the disc itself —
  a hard disc reads as a light source; a soft blob reads as a smudge).
- **Sun halo:** radius 9 → 34 px, `SUN_HALO` falling to sky color with `1 - (r/34)^1.8`, Bayer-
  dithered. At `DAWN` and `GOLDEN` the halo radius goes to 56 px and the falloff exponent to
  1.2 — a huge, soft, dominant sun is 80 % of what makes golden hour beautiful.
- **Sun position** is derived from `SUN_DIR`: azimuth → U, elevation → V. It must actually move.
- **Moon disc:** 11 px, `MOON_DISC`, with 4 `MOON_MARE` blobs (2–4 px) in a fixed pattern, and a
  correct phase (a `MOON_MARE`-darkened crescent mask that advances one step per in-game day).
  Halo radius 20 px, very faint.
- Sun and moon are **baked into the panorama**, not separate geometry. Re-baked with the sky.

### 11.4 Stars
Only where `STAR_ALPHA > 0`, alpha-blended over the gradient before the clouds:
```
Tier 1: density 1/2200 texels, STAR_BRIGHT, 1 px, plus a 1 px cross of 40% brightness
        (the cross is what makes a single pixel read as a *star* rather than a dead pixel)
Tier 2: density 1/700,  lerp(STAR_BRIGHT, STAR_DIM, 0.45), 1 px
Tier 3: density 1/220,  STAR_DIM, 1 px, dithered at 50% so half of them flicker out
        depending on the Bayer cell -> free twinkle when the texture is re-baked
Milky way: a 55 px wide diagonal band across the panorama; inside it, triple the tier-3
        density and add a very faint STAR_DIM * 0.35 haze, fbm-modulated.
All star brightness is multiplied by STAR_ALPHA (fades in at dusk, out at dawn).
```
The star field is generated from a **fixed seed**, so the constellations are the same every
night. Players notice. Put one recognizable asterism in it and never mention it.

### 11.5 Sky anti-rules
- The sky is **never** fogged, never lit, never tinted at runtime — everything is baked.
- The horizon band of the sky must equal `FOG_TINT_MUL` applied to a mid-grey, or a visible seam
  appears where the world meets the sky. Derive one from the other; never author them separately.
- Never let a cloud touch the horizon line.

---

## 12. FIVE MONEY SHOTS

These are the compositions the game must be able to produce. If a build can't produce all five,
it isn't done. Each is specified as a reproducible camera + world + ToD setup.

### 12.1 "The Ridge at Golden Hour"
> ToD `GOLDEN` (18:15). Player stands on a 14 m ridge. Camera at 1.7 m, pitch −6°, looking
> west-southwest into the sun. The sun disc sits 22 px above the horizon with a 56 px halo. A
> line of 9 conifers crosses the lower third in near-silhouette (`ndl ≈ 0`, so they render at
> ambient — deep blue-violet against a `#FF9E44` sky). Below and beyond them, a valley filled
> with height fog (`MIST_DENSITY 0.55`) so only the tops of trees emerge. `FOG_FAR = 64 m`;
> everything past 45 m is a warm orange wash. One structure — a radio mast — stands at 55 m,
> reduced by fog to a thin dark line against the sun. In the near foreground, the bottom-left
> corner, a rock and a tuft of grass at full albedo, un-fogged, to anchor the depth.

**Why it works:** three clean depth planes (foreground rock / midground silhouetted trees /
fog-swallowed valley), a warm-to-cool value split, the sun as a compositional anchor, and the
strongest possible value contrast (near-black trees on near-white sky). This is the screenshot.

### 12.2 "Muzzle Flash in the Fog"
> ToD `NIGHT` (22:00), `FOG_FAR = 26 m`, `MIST_DENSITY 0.7`. Player in a forest clearing,
> firing. The muzzle flash is a **dynamic point light** (§2.7): `radius 9 m`, color
> `MUZZLE_MID`, active for 2 frames. In those frames the trunks of the four nearest trees, the
> ground under the player, and the near edge of a rock are all lit to near-full albedo — a warm
> orange pop against a world that is otherwise `AMBIENT_RGB (0.16,0.18,0.30)` blue-black. The
> flash itself is 3 additive tris plus a 28 px `NS_HALO`-free warm glow card. 14 m out, an
> enemy is visible ONLY as two `NS_CORE` violet eye-dots and a violet rim outline through the
> mist.

**Why it works:** the biggest possible dynamic range event, a warm/cool complementary clash, and
the violet accent doing exactly the job it exists for. This is the shot that sells the game's
identity.

### 12.3 "Willowmere at Dawn" (the cozy hub)
> ToD `DAWN` (05:30). A small village of 11 modular buildings with `ROOF_TILE` roofs,
> `PLASTER` walls, and `PAINT_TEAL` / `PAINT_OCHRE` trim. Camera at 2.4 m looking down a
> curved dirt path (`DIRT`/`PATH` tiles) that leads the eye into the frame. Every window is a
> 2-tri `#FFD8A0` additive quad with a glow card — warm interior light against a
> `#E8A468` dawn horizon and `#2A3A72` zenith. Ground mist at `MIST_DENSITY 0.55` sits at
> ankle height between the buildings. Chimney smoke: 6 additive `SMOKE` sprites drifting up
> and fading. Three NPCs stand in the square at LOD0 with `SKY_HORIZON * 0.35` rim light.
> Fabric awnings in `FABRIC_RED` and `FABRIC_CREAM` give two saturated accents. A tree with
> `LEAF_AUTUMN` canopy sits off-centre-left.

**Why it works:** warmth, human scale, a leading line, many small warm light sources against a
cool ambient, and the Animal Crossing pillar delivered in full. It's the emotional counterweight
to 12.2 and it is why players will come back to the hub.

### 12.4 "Nightshade Bloom"
> `NIGHTSHADE BLOOM` zone override at `NIGHT`. A shallow basin, 40 m across, floored with
> `NS_FLORA` plants — each 6 tris of geometry plus a 2-tri `NS_HALO` additive glow card,
> ~70 of them. `FOG_TINT_MUL = (0.66, 0.40, 0.92)`: the *fog itself* is violet, so distance
> reads as violet rather than blue. `FOG_FAR = 30 m`. Four to six drifting additive `XP_MOTE`
> particles per plant, rising slowly. At the basin's centre, a 12 m black monolith
> (`GRANITE_LO` albedo) with `NS_CORE` emissive seams — the only vertical element, catching a
> `NS_MID` rim on both edges. Two dynamic point lights (`NS_MID`, radius 14 m) at its base,
> slowly pulsing at 0.4 Hz, so the ground and nearby flora breathe.

**Why it works:** total palette commitment. One hue family, one value structure, one light
source, and a strong central vertical. It's the game's logo rendered as a place.

### 12.5 "Storm Assault"
> `STORM` at `AFTERNOON`. `FOG_FAR = 20 m`, `AMBIENT_RGB` lerped to (0.30,0.31,0.38),
> `SUN_RGB × 0.20`. A ruined concrete compound: `CONCRETE`, `CONC_STAIN`, `METAL_RUST`,
> `RUBBLE`. 40 rain-streak additive sprites. The player is behind cover; five enemies advance
> at 12–19 m — at that distance the fog has already reduced them to violet-rimmed shapes with
> `NS_CORE` eyes. **Then the lightning fires**: for two frames `AMBIENT_RGB` jumps to
> (0.90,0.92,1.00) and the entire compound — every enemy, the far wall at 19 m, the rubble —
> is revealed at near-full albedo in a flat, shadowless, blue-white flash. Then it's gone.

**Why it works:** it uses the *absence* of the image as the image. The lightning frame is a
completely different picture from the frame before it, and that contrast is worth more than any
amount of per-pixel effect. Cost: two triangles and one variable.

---

## 13. ANTI-GOALS — how this becomes a bad student project

Every one of these is a specific, observed failure mode. Treat this list as a code review
checklist.

1. **"Ugly on purpose."** PS1 games were not trying to look bad. Every wobble, every dither
   pattern, every fog bank was a *workaround that turned out beautiful*. If a decision's only
   justification is "it's retro," it is not justified. **The test: would a 1998 art director
   have shipped this, or would they have fixed it if they could?**
2. **Per-texel white noise as texture.** §1.2. Structure at 4–10 texels or grain at ±6. Nothing
   in between, ever.
3. **No fog, or fog that doesn't match the sky.** The former makes a rug; the latter puts a
   visible seam at the skyline. §6.6.
4. **Untinted color.** `(0,128,0)` green, `(128,128,128)` grey, `(255,255,255)` white. If a
   color's channels are round numbers or two channels are equal, it was typed, not chosen.
5. **No true darks or no true lights.** §1.4. Every frame needs something below luminance 30 and
   something above 220. Check with a histogram if you have to.
6. **Objects that float.** Every prop and every entity gets its 2-triangle contact blob. No
   exceptions, not even for the crate in the test scene.
7. **Debug textures in shipping scenes.** The checkerboard is a diagnostic. So is the grid, so
   is the magenta "missing texture." Ship with a `DEBUG_GRID` tile that is *magenta*, so it is
   impossible to miss when it leaks into a screenshot.
8. **Anti-aliased or scaled-up UI text.** A blurry glyph on a 320×240 screen is unreadable and
   it screams "I upscaled a modern font." Hand-build both fonts as bitfields. 1 px shadow,
   always.
9. **HUD without a contrast plate.** White text on a sky background disappears. Every text
   block gets a `UI_BLACK` @ 55 % plate or a hard 1 px shadow. Test the HUD against the four
   worst backgrounds: noon sky, snow, a muzzle flash, and `CONCRETE_HI`.
10. **Symmetric, silhouette-identical enemies.** §8.2. If two enemy classes are the same
    silhouette at 12 px, one of them is wasted work.
11. **Bloom, DOF, motion blur, chromatic aberration attempted for real.** §10 row 10. They are
    not possible on this renderer. Every hour spent is an hour not spent on fog and glow cards,
    which *are* possible and look better.
12. **Flat-lit terrain.** §1.3. If `face_light()` is called once for the whole ground, the ground
    is cardboard. Light per vertex, vary per vertex, add height variation.
13. **A flat horizon line.** Even 1.5 m of terrain undulation across 32 m destroys the ruler-edge
    horizon. Combine with mist (§6.4) and it becomes a landscape.
14. **Overshooting the triangle budget and dropping to 40 fps.** A gorgeous 40 fps FPS is a bad
    FPS. 60 is the floor. `FOG_FAR` is the dial; turn it down before you cut anything else.
15. **Too many textures.** Every SDL texture beyond the four in Rule T3 fragments the batch and
    multiplies draw calls after the depth sort. Four. Not five.
16. **Violet used as decoration.** The moment `NS_CORE` appears on a friendly building or a nice
    flower, the "violet = threat/reward" contract breaks and long-range enemy readability dies
    with it. Guard this rule harder than any other in this document.
17. **Skipping the juice.** No hitmarker, no crosshair bloom, no screen kick, no XP popup. These
    cost almost nothing and they are the entire difference between "a tech demo" and "a game."
18. **Sky bands.** If the sky gradient isn't Bayer-dithered, it bands, and it's 40 % of every
    outdoor frame.
19. **Inconsistent texel density.** A 4 cm/texel wall next to a 12 cm/texel wall is instantly
    visible even at this resolution and makes the world feel assembled from parts.
20. **Treating the wobble as a bug.** Vertex snapping and affine warping are the signature. Do
    not "fix" them. Do keep quads small enough (≤ 4 m) that affine warping on the ground stays
    charming rather than seasick.

---

## 14. IMPLEMENTATION CHECKLIST FOR THE ARCHITECT

Ordered by dependency. Items marked **★** are the ones that produce the largest visual delta per
hour of work.

**Engine patches to Wobbleweed (small, all in `sdl.hml` / `geom.hml` / `scene_gpu.hml`):**
1. ★ Add `SDL_SetTextureBlendMode` / `SDL_SetRenderDrawBlendMode` externs; enable
   `SDL_BLENDMODE_BLEND` on the renderer and on `ATLAS_WORLD`/`ATLAS_HUD`, `SDL_BLENDMODE_ADD`
   on `ATLAS_FX`. (Rule T2/T3)
2. ★ `put_vert` writes `v.a` to byte offset 11 instead of a hard-coded 255. (Rule T2)
3. ★ Replace the single global batch with four ordered layers; sort within a layer only.
   (Rule T4)
4. Replace the scalar `face_light` with the full `light_rgb` model of §4.1 (colored ambient,
   colored sun, bounce, rim, up to 4 dynamic point lights).
5. Fold fog (§6.2) into the vertex emit path — both `vcolor` multiply and `valpha`.
6. `mat_perspective` far plane becomes `FOG_FAR * 1.06`, not 200.0. (Rule T6)
7. Extend `emit_sky` to offset V by pitch as well as U by yaw.
8. Add partial-rect `SDL_UpdateTexture` for incremental sky re-baking. (§7.5)
9. Consider replacing `tris.sort()` (comparison sort through a closure) with a 512-bucket radix
   sort on quantized depth — at 2500 triangles this is likely a measurable win and the depth
   quantization error is invisible.

**New Nightshade modules:**
10. ★ `src/palette.hml` — all of §3 as named constants. Nothing anywhere else hard-codes a color.
11. ★ `src/tod.hml` — the §5 keyframe table, interpolation, weather overrides, lightning.
12. ★ `src/texgen.hml` — §7.2 primitives + §7.3 generators + the §7.4 atlas packer.
13. ★ `src/skygen.hml` — §11, with incremental re-bake.
14. `src/fx.hml` — `ATLAS_FX` generation, glow cards, particle emitters.
15. ★ `src/hud.hml` — §9, including both bitfield fonts.
16. `src/postfx_geo.hml` — §10 items 2, 3, 4, 7, 8, 9.
17. `tools/palette_preview.hml` — dumps a PNG swatch sheet of §3 and the §5 keyframes applied to
    a test sphere. Build this *first*; it will catch palette errors before they're baked into
    fifty tiles.

**First milestone that proves the art direction (do this before anything else):**
> One 32 m chunk of undulating terrain with the new grass generator, per-vertex lighting, the
> full fog model, height mist, a re-baked sky, three trees, one contact-shadowed crate, and a
> `GOLDEN` time-of-day. Screenshot it. If it doesn't look better than everything in
> `wobbleweed/docs/*.png` by an enormous margin, stop and fix the art direction before writing
> gameplay.

---

*End of Art Bible v1.0.*
