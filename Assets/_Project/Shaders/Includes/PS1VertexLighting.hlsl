#ifndef PS1_VERTEX_LIGHTING_INCLUDED
#define PS1_VERTEX_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// PS1VertexLighting.hlsl
// PS1-style per-vertex lighting calculation.
// Includes main directional light, ambient SH, and additional lights.
// All computed per-vertex, no per-pixel lighting (matches PS1 GTE).
//
// USAGE:
// In the vertex shader:
//   half3 lighting = PS1ComputeVertexLighting(worldPos, worldNormal);
//   OUT.vertexLighting = lighting;
//
// In the fragment shader:
//   color.rgb *= IN.vertexLighting;
//
// FLAT vs GOURAUD shading is controlled in the Varyings struct:
//   #if defined(_FLAT_SHADING)
//       nointerpolation half3 vertexLighting : TEXCOORDn;
//   #else
//       half3 vertexLighting : TEXCOORDn;
//   #endif
//
// REQUIRES: Forward rendering path (not Forward+).
// Forward+ doesn't support GetAdditionalLightsCount in the vertex stage.

half3 PS1ComputeVertexLighting(float3 worldPos, float3 worldNormal)
{
    // Main directional light
    Light mainLight = GetMainLight();
    half NdotL = saturate(dot(worldNormal, mainLight.direction));
    half3 diffuse = mainLight.color * NdotL;

    // Ambient from spherical harmonics
    half3 ambient = SampleSH(worldNormal);

    // Additional lights (point, spot) - all per-vertex
    uint additionalLightsCount = GetAdditionalLightsCount();
    for (uint i = 0u; i < additionalLightsCount; ++i)
    {
        Light additionalLight = GetAdditionalLight(i, worldPos);
        half addNdotL = saturate(dot(worldNormal, additionalLight.direction));
        diffuse += additionalLight.color * addNdotL * additionalLight.distanceAttenuation;
    }

    return ambient + diffuse;
}

#endif
