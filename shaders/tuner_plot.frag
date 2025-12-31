#version 460
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLabelWidth;
uniform float uPlotRightPadding;
uniform float uLineWidth;
uniform float uRowHeight;
uniform float uBlockWidth;
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
  vec4 data = texture(uData, vec2(plotX, 0.5));

  float valid = data.a;
  float y = data.r * height;
  float dist = abs(fragCoord.y - y);
  float lineAlpha = valid * smoothstep(uLineWidth, 0.0, dist);
  vec4 color = uLineColor * lineAlpha;

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
