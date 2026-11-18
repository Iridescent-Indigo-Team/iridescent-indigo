#ifdef GLSLES

#ifdef FRAGMENT_SHADER
/* Only the fragment shader has no default float precision.
 * Prefer highp when the GPU supports it: Adreno implements mediump as fp16,
 * which is not precise enough for interpolated texture coordinates on large
 * tile/sprites atlases and causes tile seams, texture bleeding and wrong
 * tiles. Vertex shaders already default to highp, so this also keeps the
 * varying precision consistent between the two stages. */
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#endif

#else

/* Desktop GLSL doesn't know about these */
#define highp
#define mediump
#define lowp

#endif
