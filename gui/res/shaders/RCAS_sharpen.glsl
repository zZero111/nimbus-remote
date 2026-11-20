// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// FidelityFX FSR v1.0.2 by AMD
// ported to mpv by agyild

// Changelog
// Made it compatible with pre-OpenGL 4.0 renderers
// Made it directly operate on LUMA plane, since the original shader was operating on LUMA by deriving it from RGB. This should cause a major increase in performance, especially on OpenGL 4.0+ renderers (4+2 texture lookups vs. 12+5)
// Removed transparency preservation mechanism since the alpha channel is a separate source plane than LUMA
// Added optional performance-saving lossy optimizations to EASU (Credit: atyuwen, https://atyuwen.github.io/posts/optimizing-fsr/)
// 
// Notes
// Per AMD's guidelines only upscales content up to 4x (e.g., 1080p -> 2160p, 720p -> 1440p etc.) and everything else in between,
// that means FSR will scale up to 4x at maximum, and any further scaling will be processed by mpv's scalers

// Nimbus Remote: AMD FidelityFX RCAS (from FSR 1.0.2 above) as a standalone sharpening pass on
// the final scaled RGB image, so it works with any upscaler (or none). The strength is filled in
// when the app loads the shader (0.0 = strongest, 2.0 = weakest).

//!HOOK SCALED
//!BIND HOOKED
//!DESC Nimbus sharpening (AMD FidelityFX RCAS)

#define SHARPNESS @SHARPNESS@
#define FSR_RCAS_DENOISE 1
#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

float APrxMedRcpF1(float a) {
	float b = uintBitsToFloat(uint(0x7ef19fff) - floatBitsToUint(a));
	return b * (-b * a + 2.0);
}
float AMax3F1(float x, float y, float z) { return max(x, max(y, z)); }
float AMin3F1(float x, float y, float z) { return min(x, min(y, z)); }
float Luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 hook() {
	//    b
	//  d e f
	//    h
	vec4 ce = HOOKED_tex(HOOKED_pos);
	vec3 b = HOOKED_texOff(vec2( 0.0, -1.0)).rgb;
	vec3 d = HOOKED_texOff(vec2(-1.0,  0.0)).rgb;
	vec3 e = ce.rgb;
	vec3 f = HOOKED_texOff(vec2( 1.0,  0.0)).rgb;
	vec3 h = HOOKED_texOff(vec2( 0.0,  1.0)).rgb;

	// Ring min/max per channel; one lobe for all channels (as AMD's RCAS does)
	vec3 mn = min(min(b, d), min(f, h));
	vec3 mx = max(max(b, d), max(f, h));
	vec3 hitMin = min(mn, e) / (4.0 * mx + 1e-5);
	vec3 hitMax = (1.0 - max(mx, e)) / (4.0 * mn - 4.0 - 1e-5);
	vec3 lobeRGB = max(-hitMin, hitMax);
	float lobe = max(float(-FSR_RCAS_LIMIT), min(max(lobeRGB.r, max(lobeRGB.g, lobeRGB.b)), 0.0)) * exp2(-clamp(float(SHARPNESS), 0.0, 2.0));

#if (FSR_RCAS_DENOISE == 1)
	// Less sharpening on noisy areas (compression noise)
	float lb = Luma(b), ld = Luma(d), le = Luma(e), lf = Luma(f), lh = Luma(h);
	float nz = 0.25 * (lb + ld + lf + lh) - le;
	nz = clamp(abs(nz) * APrxMedRcpF1(AMax3F1(AMax3F1(lb, ld, le), lf, lh) - AMin3F1(AMin3F1(lb, ld, le), lf, lh)), 0.0, 1.0);
	lobe *= -0.5 * nz + 1.0;
#endif

	float rcpL = APrxMedRcpF1(4.0 * lobe + 1.0);
	vec3 pix = (lobe * (b + d + f + h) + e) * rcpL;
	// Only stop it going negative: HDR frames can be brighter than 1.0 here
	return vec4(max(pix, vec3(0.0)), ce.a);
}
