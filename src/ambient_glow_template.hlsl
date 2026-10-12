// Ambient Glow for PotPlayer - %%TITLE%%
//
// Fills the empty black bars beside the picture with a soft, blurred light
// taken from the picture's edges, fading out towards the edge of the screen,
// similar to YouTube's "ambient mode". Made for 16:9 movies on a 21:9 screen.
//
// HOW TO USE
%%USAGE%%
//   Made for PotPlayer's "Built-in Direct3D 11 Video Renderer". For the
//   Direct3D 9 renderer, set RENDERER_D3D9 to 1 and copy the first line of
//   PotPlayer's own "Adaptive sharpen.txt" to the top of this file.
//   (Never add that line for Direct3D 11: PotPlayer then can't load it, and
//   it looks for that profile name anywhere in the file, even in comments.)
//
// SETTINGS - change a number and save the file, then in PotPlayer choose
// Video > Pixel Shaders > Reload Pixel Shader list and untick/re-tick the shader.

#define RENDERER_D3D9    0      // 0 = Direct3D 11 renderer (default), 1 = Direct3D 9

#define ASPECT_MODE      %%ASPECT_MODE%%             // 0 = fixed CONTENT_AR, 1 = find the picture edge automatically
#define CONTENT_AR       %%CONTENT_AR%%  // shape of the video (fixed and stretch modes; fallback in auto mode)
#define STRETCHED_INPUT  %%STRETCHED%%             // 1 = PotPlayer is set to stretch the video to fill the screen

#define GLOW_STRENGTH    1.00   // brightness right next to the picture (0 - 1)
#define GLOW_FALLOFF     %%FALLOFF%%   // fade curve towards the screen edge (higher = fades sooner)
#define GLOW_REACH       %%REACH%%   // 1 = fades to black at the screen edge; higher keeps more glow out to the edge
#define GLOW_SATURATION  1.00   // colour intensity: 1 = same as the picture edge, higher = more vivid
#define GLOW_SOFTNESS    %%SOFTNESS%%   // blur size at the outer edge, as a share of screen height
#define GLOW_EDGE_SOURCE 0.015  // right next to the picture: colour comes from this thin edge strip (share of picture width)
#define GLOW_SOURCE      0.12   // at the screen edge: colour comes from this wider strip, for a softer spread

#define BLACK_LEVEL      0.004  // pixels darker than this count as empty bar
#define AUTO_MIN_AR      1.25   // auto mode: narrowest picture shape it looks for

// ---------------------------------------------------------------------------

sampler s0 : register(s0);
float4  p0 : register(c0);      // (width, height, counter, clock) of the surface

#define W (p0.x)
#define H (p0.y)

float peak(float3 c)
{
    return max(c.r, max(c.g, c.b));
}

// Read the surface at a position in pixels (pixel centres sit at n + 0.5).
// PotPlayer's Direct3D 11 renderer converts this file on the fly: it declares
// the video surface as Texture0 but only provides a replacement for plain
// tex2D, so reads inside loops go to Texture0 directly.
float3 fetch(float2 pos)
{
    pos = clamp(pos, float2(0.5, 0.5), float2(W - 0.5, H - 0.5));
#if RENDERER_D3D9
    return tex2Dlod(s0, float4(pos / float2(W, H), 0.0, 0.0)).rgb;
#else
    return Texture0.SampleLevel(s0, pos / float2(W, H), 0.0).rgb;
#endif
}

// Read a position given in on-screen picture coordinates. In stretch mode the
// picture is spread over the whole surface, so map it back first.
float3 fetchPicture(float2 pos, float L)
{
#if STRETCHED_INPUT
    pos.x = (pos.x - L) * W / (W - 2.0 * L);
#endif
    return fetch(pos);
}

// Brightest value in one column, checked at `rows` heights.
float columnPeak(float x, int rows)
{
    float m = 0.0;
    [loop] for (int i = 0; i < rows; i++)
        m = max(m, peak(fetch(float2(x, (i + 0.5) * H / rows))));
    return m;
}

// True when both side strips outside the picture edge L are empty bar
// (4 columns x 10 rows on each side). Checking both sides keeps the glow off
// in dark scenes of films that fill the screen.
bool barsAreEmpty(float L)
{
    float m = 0.0;
    [loop] for (int c = 0; c < 4; c++)
    {
        float x = 0.5 + c * (L - 3.0) / 3.0;
        m = max(m, columnPeak(x, 10));
        m = max(m, columnPeak(W - x, 10));
    }
    return m <= BLACK_LEVEL;
}

// Left edge of the picture in pixels (the right edge mirrors it),
// or -1 when there are no side bars to fill.
float findPictureEdge()
{
    float fixedL = floor(0.5 * (W - H * CONTENT_AR) + 0.5);
#if STRETCHED_INPUT
    return (fixedL >= 2.0) ? fixedL : -1.0;
#else
    float L = -1.0;
  #if ASPECT_MODE == 1
    // Binary search for the first column that isn't empty bar.
    float maxL = floor(0.5 * (W - H * AUTO_MIN_AR));
    if (maxL >= 4.0 && columnPeak(0.5, 8) <= BLACK_LEVEL)
    {
        float lo = 0.0;           // known bar column
        float hi = maxL + 1.0;    // first column known (or assumed) to be picture
        [loop] for (int i = 0; i < 12; i++)
        {
            if (hi - lo > 1.0)
            {
                float mid = floor(0.5 * (lo + hi));
                if (columnPeak(mid + 0.5, 8) <= BLACK_LEVEL) lo = mid;
                else hi = mid;
            }
        }
        if (hi <= maxL && hi >= 4.0 && barsAreEmpty(hi)) L = hi;
    }
  #endif
    // Fixed shape (also the fallback in auto mode, e.g. when the picture edge is dark).
    if (L < 0.0 && fixedL >= 4.0 && barsAreEmpty(fixedL)) L = fixedL;
    return L;
#endif
}

// Glow colour for a bar pixel. d = distance from the picture edge in pixels,
// side = +1 for the left bar, -1 for the right bar.
float3 glowColour(float2 pos, float L, float d, float side)
{
    float t     = saturate(d / L);                            // 0 at the picture, 1 at the screen edge
    float R     = lerp(0.035, GLOW_SOFTNESS, t) * H;           // vertical blur radius
    // Like real light spill: next to the picture the colour matches its very
    // edge, and the source widens (with the blur) further out.
    float depth = lerp(GLOW_EDGE_SOURCE, GLOW_SOURCE, t) * (W - 2.0 * L);
    float edge  = (side > 0.0) ? L : (W - L);

    float3 acc  = 0.0;
    float  wsum = 0.0;
    // 96 taps over a strip of the picture next to the edge: heights evenly
    // spaced, depths scattered by the golden ratio so no source column is read
    // at a regular spacing (that would turn fine stripes into visible banding).
    // A per-pixel shift of the pattern turns what's left of fine detail into
    // invisible grain instead of faint ripples. Taps nearer the edge count more.
    float j1 = frac(52.9829189 * frac(dot(pos, float2(0.06711056, 0.00583715))));
    float j2 = frac(j1 * 1.6180339887 + 0.37);
    [loop] for (int n = 0; n < 96; n++)
    {
        float o  = (n + j1) / 48.0 - 1.0;                       // -1 .. 1
        float u  = frac(n * 0.6180339887 + j2);                 //  0 .. 1
        float sx = edge + side * (1.5 + u * depth);
        float w  = (1.0 - 0.6 * u) * exp(-2.5 * o * o);
        acc  += w * fetchPicture(float2(sx, pos.y + o * R), L);
        wsum += w;
    }
    float3 c = acc / wsum;
    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = max(lerp(float3(luma, luma, luma), c, GLOW_SATURATION), 0.0);

    float fade = saturate(1.0 - t / GLOW_REACH);
    // Ease the last stretch smoothly down to true black at the screen edge.
    float ease = smoothstep(0.0, 0.18, fade);
    return c * (GLOW_STRENGTH * pow(max(fade, 0.0001), GLOW_FALLOFF) * ease);
}

#if STRETCHED_INPUT
float lanczos2(float x)
{
    x = abs(x);
    float px = 3.14159265 * x;
    float w  = 2.0 * sin(px) * sin(0.5 * px) / max(px * px, 1e-8);
    return (x < 1e-4) ? 1.0 : ((x < 2.0) ? w : 0.0);
}

// Undo the horizontal stretch for the picture area (Lanczos2, widened for downscaling).
float3 restoreAspect(float2 pos, float L)
{
    float scale = W / (W - 2.0 * L);
    float sx    = (pos.x - L) * scale;
    float base  = floor(sx);
    float3 acc  = 0.0;
    float  wsum = 0.0;
    [loop] for (int i = -4; i <= 4; i++)
    {
        float xi = base + i + 0.5;
        float w  = lanczos2((xi - sx) / scale);
        acc  += w * fetch(float2(xi, pos.y));
        wsum += w;
    }
    return max(acc / wsum, 0.0);
}
#endif

float4 main(float2 tex : TEXCOORD0) : COLOR
{
    float4 src  = tex2D(s0, tex);
    float2 pos  = tex * float2(W, H);
    float  midX = 0.5 * W;

#if STRETCHED_INPUT
    float L = findPictureEdge();
    if (L < 0.0) return src;
    if (pos.x >= L && pos.x <= W - L) return float4(restoreAspect(pos, L), 1.0);
#else
    // Picture pixels, and anything too close to the centre to be bar, pass through.
    float innerHalf = 0.5 * H * ((ASPECT_MODE == 1) ? min(AUTO_MIN_AR, CONTENT_AR) : CONTENT_AR);
    if (peak(src.rgb) > BLACK_LEVEL || abs(pos.x - midX) < innerHalf - 1.0) return src;
    float L = findPictureEdge();
    if (L < 0.0 || (pos.x > L + 1.0 && pos.x < W - L - 1.0)) return src;
#endif

    float side = (pos.x < midX) ? 1.0 : -1.0;
    float d    = max((side > 0.0) ? (L - pos.x) : (pos.x - (W - L)), 0.0);
    float3 g   = glowColour(pos, L, d, side);

    // Tiny dither so the dark gradient doesn't band on 8-bit output. It fades
    // out with the glow, so the bar stays truly black where the glow ends.
    float n = frac(52.9829189 * frac(dot(pos.yx, float2(0.06711056, 0.00583715))));
    g += (n - 0.5) * (0.98 / 255.0) * saturate(peak(g) * 64.0);
    return float4(max(g, 0.0), 1.0);
}
