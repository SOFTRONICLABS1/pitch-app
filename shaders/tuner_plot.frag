#version 460
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLabelWidth;
uniform float uPlotRightPadding;
uniform float uLineWidth;
uniform float uRowHeight;
uniform float uBlockWidth;
uniform float uSampleCount;
uniform vec4 uLineColor;
uniform vec4 uBlockColor;
uniform sampler2D uData;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  float width = uSize.x;
  float height = uSize.y;

  if (fragCoord.x < uLabelWidth || fragCoord.x > width - uPlotRightPadding) {
    fragColor = vec4(0.0);
    return;
  }

  float plotWidth = width - uLabelWidth - uPlotRightPadding;
  float plotX = (fragCoord.x - uLabelWidth) / plotWidth;
  float texel = 1.0 / max(uSampleCount - 1.0, 1.0);
  float prevX = max(0.0, plotX - texel);
  vec4 data = texture(uData, vec2(plotX, 0.5));
  vec4 prev = texture(uData, vec2(prevX, 0.5));

  vec4 color = vec4(0.0);

  if (data.a > 0.0 && prev.a > 0.0) {
    float y1 = data.r * height;
    float y0 = prev.r * height;
    float x1 = uLabelWidth + plotX * plotWidth;
    float x0 = uLabelWidth + prevX * plotWidth;

    vec2 a = vec2(x0, y0);
    vec2 b = vec2(x1, y1);
    vec2 ab = b - a;
    float denom = dot(ab, ab);
    float t = denom > 0.0 ? clamp(dot(fragCoord - a, ab) / denom, 0.0, 1.0)
                          : 0.0;
    vec2 closest = a + ab * t;
    float dist = length(fragCoord - closest);
    float lineAlpha = smoothstep(uLineWidth, 0.0, dist);
    color = uLineColor * lineAlpha;
  }

  float blockAlpha = data.b;
  if (blockAlpha > 0.0) {
    float blockY = data.g * height;
    float halfH = uRowHeight * 0.5;
    float halfW = uBlockWidth * 0.5;
    if (abs(fragCoord.y - blockY) <= halfH &&
        abs(fragCoord.x - (uLabelWidth + plotX * plotWidth)) <= halfW) {
      color = max(color, uBlockColor * blockAlpha);
    }
  }

  fragColor = color;
}
