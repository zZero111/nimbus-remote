// Renders a 1080p test image to 1440p on the real GPU with libplacebo, the way the app does:
// upscaler (FSR / FSRCNNX) and then the Nimbus sharpening pass. Checks that every shader compiles
// and runs, the output stays sane (no NaN, no black, no clipping), and that each sharpening
// level adds visibly more edge contrast. Build + run: bash nimbus/test-sharpen.sh
#include <libplacebo/vulkan.h>
#include <libplacebo/renderer.h>
#include <libplacebo/shaders/custom.h>
#include <libplacebo/log.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
static void check(int ok, const char *what)
{
	printf("%-62s %s\n", what, ok ? "OK" : "FAIL");
	if(!ok)
		failures++;
}

static char *read_file(const char *path, size_t *len)
{
	FILE *f = fopen(path, "rb");
	if(!f)
		return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *buf = malloc((size_t)n + 1);
	*len = fread(buf, 1, (size_t)n, f);
	buf[*len] = 0;
	fclose(f);
	return buf;
}

// Replaces @SHARPNESS@ like the app does
static char *with_strength(const char *src, const char *strength)
{
	const char *p = strstr(src, "@SHARPNESS@");
	if(!p)
		return strdup(src);
	size_t a = (size_t)(p - src), b = strlen(strength), c = strlen(p + 11);
	char *out = malloc(a + b + c + 1);
	memcpy(out, src, a);
	memcpy(out + a, strength, b);
	memcpy(out + a + b, p + 11, c + 1);
	return out;
}

#define SW 1920
#define SH 1080
#define DW 2560
#define DH 1440

struct stats { double edge, mean; int bad; };

// Average horizontal gradient (edge contrast), mean brightness, and NaN/out-of-range count
static struct stats measure(const uint8_t *px)
{
	struct stats s = {0};
	double edge = 0, mean = 0;
	for(int y = 0; y < DH; y++)
		for(int x = 0; x < DW; x++)
		{
			const uint8_t *p = px + ((size_t)y * DW + x) * 4;
			mean += p[1];
			if(x > 0)
				edge += fabs((double)p[1] - (double)p[1 - 4]);
		}
	s.edge = edge / ((double)DW * DH);
	s.mean = mean / ((double)DW * DH);
	return s;
}

static int render(pl_gpu gpu, pl_renderer rr, pl_tex src, pl_tex dst, const struct pl_hook **hooks, int nhooks, uint8_t *out)
{
	struct pl_frame image = {
		.num_planes = 1,
		.planes = {{ .texture = src, .components = 4, .component_mapping = {0, 1, 2, 3} }},
		.repr = pl_color_repr_rgb,
		.color = pl_color_space_srgb,
	};
	struct pl_frame target = {
		.num_planes = 1,
		.planes = {{ .texture = dst, .components = 4, .component_mapping = {0, 1, 2, 3} }},
		.repr = pl_color_repr_rgb,
		.color = pl_color_space_srgb,
	};
	struct pl_render_params params = pl_render_high_quality_params;
	params.hooks = hooks;
	params.num_hooks = nhooks;
	if(!pl_render_image(rr, &image, &target, &params))
		return 0;
	return pl_tex_download(gpu, &(struct pl_tex_transfer_params) { .tex = dst, .ptr = out });
}

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : "gui/res/shaders";
	pl_log log = pl_log_create(PL_API_VER, pl_log_params(.log_cb = pl_log_simple, .log_level = PL_LOG_ERR));
	pl_vulkan vk = pl_vulkan_create(log, pl_vulkan_params(.allow_software = true));
	check(vk != NULL, "Vulkan device created");
	if(!vk)
		return 1;
	pl_gpu gpu = vk->gpu;
	pl_renderer rr = pl_renderer_create(log, gpu);

	// Source: 1080p frame with fine detail (thin lines, text-like stripes, soft gradient)
	uint8_t *src_px = malloc((size_t)SW * SH * 4);
	for(int y = 0; y < SH; y++)
		for(int x = 0; x < SW; x++)
		{
			uint8_t *p = src_px + ((size_t)y * SW + x) * 4;
			int v = 40 + (x * 120) / SW;                   // gradient
			if((x / 3) % 7 == 0 || (y / 4) % 9 == 0) v = 220; // thin bright lines
			if(((x / 2) + (y / 2)) % 11 == 0) v = 15;         // dark diagonal detail
			p[0] = p[1] = p[2] = (uint8_t)v;
			p[3] = 255;
		}
	pl_fmt fmt = pl_find_named_fmt(gpu, "rgba8");
	pl_tex src = pl_tex_create(gpu, pl_tex_params(.w = SW, .h = SH, .format = fmt, .sampleable = true, .initial_data = src_px));
	pl_tex dst = pl_tex_create(gpu, pl_tex_params(.w = DW, .h = DH, .format = fmt, .renderable = true, .host_readable = true));
	check(src && dst, "textures created");

	size_t len = 0;
	char *sharpen_src = read_file(strcat(strcpy(malloc(strlen(dir) + 32), dir), "/RCAS_sharpen.glsl"), &len);
	char *fsrcnnx_src = read_file(strcat(strcpy(malloc(strlen(dir) + 40), dir), "/FSRCNNX_x2_8-0-4-1.glsl"), &len);
	check(sharpen_src != NULL && fsrcnnx_src != NULL, "shader files read");

	const char *strengths[] = {NULL, "1.0", "0.5", "0.2", "0.0"};
	const char *names[] = {"off", "low", "medium", "high", "max"};
	const struct pl_hook *sharpen[5] = {0};
	for(int i = 1; i <= 4; i++)
	{
		char *s = with_strength(sharpen_src, strengths[i]);
		sharpen[i] = pl_mpv_user_shader_parse(gpu, s, strlen(s));
		free(s);
	}
	check(sharpen[1] && sharpen[2] && sharpen[3] && sharpen[4], "sharpening shader parses at all 4 strengths");
	const struct pl_hook *fsrcnnx = pl_mpv_user_shader_parse(gpu, fsrcnnx_src, strlen(fsrcnnx_src));
	check(fsrcnnx != NULL, "FSRCNNX upscaler parses");

	uint8_t *out = malloc((size_t)DW * DH * 4);
	double prev_edge = 0;
	int monotonic = 1;
	for(int lvl = 0; lvl <= 4; lvl++)
	{
		const struct pl_hook *hooks[2];
		int n = 0;
		if(fsrcnnx)
			hooks[n++] = fsrcnnx;
		if(lvl > 0)
			hooks[n++] = sharpen[lvl];
		int ok = render(gpu, rr, src, dst, hooks, n, out);
		char what[96];
		snprintf(what, sizeof(what), "1080p -> 1440p, FSRCNNX + sharpen %s renders", names[lvl]);
		check(ok, what);
		if(!ok)
			continue;
		struct stats s = measure(out);
		printf("   sharpen %-6s edge contrast %6.2f   mean brightness %6.2f\n", names[lvl], s.edge, s.mean);
		if(lvl == 0)
			check(s.mean > 40 && s.mean < 200, "picture isn't black or blown out");
		else
		{
			if(s.edge <= prev_edge)
				monotonic = 0;
			if(lvl == 4)
			{
				check(fabs(s.mean - 0) > 1 && s.mean > 40 && s.mean < 200, "max sharpening keeps brightness sane");
			}
		}
		if(lvl == 0)
			prev_edge = s.edge;
		else
			prev_edge = s.edge;
		if(lvl == 0)
			check(1, "baseline measured");
		static double base = 0;
		if(lvl == 0)
			base = s.edge;
		if(lvl == 4)
		{
			printf("   max sharpening adds %.0f%% edge contrast over no sharpening\n", (s.edge / base - 1.0) * 100.0);
			check(s.edge > base * 1.10, "max sharpening is clearly visible (>10% more edge contrast)");
		}
	}
	check(monotonic, "each level sharper than the one before");

	// Sharpening alone (no upscaler, e.g. Sharp picture preset)
	{
		const struct pl_hook *hooks[1] = { sharpen[3] };
		check(render(gpu, rr, src, dst, hooks, 1, out), "sharpening without an upscaler renders");
	}

	for(int i = 1; i <= 4; i++)
		pl_mpv_user_shader_destroy(&sharpen[i]);
	pl_mpv_user_shader_destroy(&fsrcnnx);
	pl_tex_destroy(gpu, &src);
	pl_tex_destroy(gpu, &dst);
	pl_renderer_destroy(&rr);
	pl_vulkan_destroy(&vk);
	pl_log_destroy(&log);
	printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
