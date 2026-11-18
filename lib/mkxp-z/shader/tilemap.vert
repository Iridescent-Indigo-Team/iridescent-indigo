uniform mat4 projMat;

uniform vec2 texSizeInv;
uniform vec2 translation;

uniform highp int aniIndex;

attribute vec2 position;
attribute vec2 texCoord;

varying vec2 v_texCoord;

const int nAutotiles = 7;
const float tileW = 32.0;
const float tileH = 32.0;
const float autotileW = 3.0*tileW;
const float autotileH = 4.0*tileW;
const float atAreaW = autotileW;
const float atAreaH = autotileH*float(nAutotiles);
const float atAniOffsetX = 3.0*tileW;
const float atAniOffsetY = tileH;

uniform mediump int atFrames[nAutotiles];

void main()
{
    vec2 tex = texCoord;
    mediump int atIndex = int(tex.y / autotileH);
    if (atIndex >= nAutotiles)
        atIndex = nAutotiles - 1;

    mediump int pred = int(tex.x <= atAreaW && tex.y <= atAreaH);
    mediump int frame = aniIndex - atFrames[atIndex] * (aniIndex / atFrames[atIndex]);
    mediump int row = frame / 8;
    mediump int col = frame - 8 * row;
    tex.x += atAniOffsetX * float(col * pred);
    tex.y += atAniOffsetY * float(row * pred);

    gl_Position = projMat * vec4(position + translation, 0, 1);

    v_texCoord = tex * texSizeInv;
}
