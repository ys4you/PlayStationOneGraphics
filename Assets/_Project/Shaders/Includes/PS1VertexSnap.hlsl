#ifndef PS1_VERTEX_SNAP_INCLUDED
#define PS1_VERTEX_SNAP_INCLUDED

// PS1VertexSnap.hlsl
// Reusable vertex snapping function for PS1-style rendering.
// Recreates the PS1's lack of subpixel rasterization by snapping
// vertex positions to a low-resolution grid in NDC space.
//
// Usage:
//   float4 clipPos = TransformObjectToHClip(IN.positionOS.xyz);
//   clipPos = PS1Snap(clipPos, 160.0);
//   OUT.positionCS = clipPos;

float4 PS1Snap(float4 clipPos, float gridSize)
{
    float2 ndcPos = clipPos.xy / clipPos.w;
    ndcPos = floor(ndcPos * gridSize + 0.5) / gridSize;
    clipPos.xy = ndcPos * clipPos.w;
    return clipPos;
}

#endif
