// PS1AffineMapping.shader
//
// PURPOSE:
// Recreates the PS1's affine texture mapping artifact.
//
// RESEARCH CONTEXT:
// The PS1's GPU is fundamentally a 2D rasterizer. It does not understand
// depth. When rasterizing a triangle, it interpolates vertex data (like
// texture coordinates) linearly in 2D screen space. This is called
// "affine" interpolation.
//
// Modern GPUs perform perspective-correct interpolation: they account
// for the fact that a surface receding into depth covers less screen
// space per unit of texture at the far end than the near end. The GPU
// divides each interpolant by W (the depth component from the projection
// matrix) before interpolating, then multiplies W back in per-pixel.
// This keeps textures looking correct in 3D.
//
// The PS1 skipped this entirely. Sony's engineers designed the GPU to
// be cheap and fast, and per-pixel division was expensive in 1994
// hardware. The result: textures appear to "swim" and warp across
// surfaces, especially on large polygons viewed at steep angles.
//
// PS1 developers knew about this and worked around it by:
// - Subdividing large polygons into smaller triangles (reduces the
//   error because affine is more accurate on small screen-space areas)
// - Using fixed camera angles to hide the worst distortion (Silent Hill,
//   Resident Evil)
// - Keeping textures small and repetitive so warping is less noticeable
//
// Source: Yesse Seijnaeve, "PlayStation One Graphics Research" (2026)
//         Section 1.1.2 - How did affine texture mapping work technically
// Source: David Colson, "Building a PS1 style retro 3D renderer" (2021)
// Source: Pikuma, "How PlayStation Graphics & Visual Artefacts Work"
//
// IMPLEMENTATION:
// There are two ways to recreate affine mapping in a modern shader:
//
// Method A - Manual W multiply/divide:
//   Vertex shader:  uvOut = uv * clipPos.w
//   Fragment shader: finalUV = uvIn / clipW
//   This manually undoes the perspective correction the GPU applies.
//   More educational, closer to what the PS1 hardware actually did.
//
// Method B - noperspective qualifier:
//   Mark the UV interpolant as `noperspective` in the Varyings struct.
//   This tells the GPU to skip perspective correction for that variable
//   and interpolate it linearly in screen space instead.
//   Same result, cleaner code, no extra data passed between stages.
//
// This shader uses Method B because it is cleaner for a reusable plugin.
// The `noperspective` keyword achieves the exact same hardware behavior
// with less code and no risk of floating point edge cases from the
// manual W division.
//
// WHAT TO LOOK FOR WHEN TESTING:
// - Apply to a large floor plane with a checkerboard texture.
//   Look at the plane from a low angle. The checkerboard lines
//   should visibly bend and warp instead of converging smoothly
//   toward the horizon.
// - Rotate the camera around a textured cube. The texture should
//   appear to "swim" across the faces, especially on faces at
//   steep angles to the camera.
// - Compare with _AffineIntensity at 0 (modern, correct) vs 1
//   (full PS1 distortion) to see the difference clearly.
// - The distortion is worst on LARGE triangles. If you subdivide
//   a mesh into tiny triangles, the effect almost disappears.
//   This is exactly why PS1 developers subdivided their geometry.

Shader "PS1/PS1AffineMapping"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [Header(Affine Texture Mapping)]
        _AffineIntensity("Affine Intensity", Range(0.0, 1.0)) = 1.0
        // 0.0 = fully perspective-correct (modern rendering)
        // 1.0 = fully affine (PS1 rendering)
        // Values in between blend the two, which is useful for
        // tuning the effect per-asset in your plugin.
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "PS1AffineMappingForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ---------------------------------------------------------------
            // INPUT STRUCT
            // ---------------------------------------------------------------
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
            };

            // ---------------------------------------------------------------
            // OUTPUT STRUCT
            // ---------------------------------------------------------------
            // This is where the affine mapping happens. We output TWO sets
            // of UVs:
            //
            // uvAffine:  marked `noperspective`, which tells the GPU to
            //            interpolate this linearly in screen space. This
            //            produces the PS1's affine texture warping.
            //
            // uvCorrect: normal interpolation with perspective correction.
            //            This is what a modern GPU does by default.
            //
            // Both receive the same UV values in the vertex shader. The
            // difference is entirely in HOW the GPU interpolates them
            // across the triangle during rasterization. The fragment shader
            // then blends between the two based on _AffineIntensity.
            //
            // WHY TWO UVs INSTEAD OF JUST noperspective?
            // Having both allows the _AffineIntensity slider to work.
            // At 0.0, we use the correct UVs (modern look).
            // At 1.0, we use the affine UVs (PS1 look).
            // This gives artists importing the plugin a way to dial in
            // exactly how much distortion they want per material.
            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                noperspective float2 uvAffine   : TEXCOORD0;
                float2 uvCorrect               : TEXCOORD1;
                half3  lighting                : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _AffineIntensity;
            CBUFFER_END

            // ---------------------------------------------------------------
            // VERTEX SHADER
            // ---------------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);

                // Both UV outputs get the same value here.
                // The difference happens during rasterization:
                // - uvAffine is interpolated WITHOUT perspective correction
                //   (noperspective qualifier)
                // - uvCorrect is interpolated WITH perspective correction
                //   (default behavior)
                float2 baseUV = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.uvAffine  = baseUV;
                OUT.uvCorrect = baseUV;

                // Basic lighting so we can see the geometry.
                // Not PS1-specific, just functional.
                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(worldNormal, mainLight.direction));
                OUT.lighting = SampleSH(worldNormal) + mainLight.color * NdotL;

                return OUT;
            }

            // ---------------------------------------------------------------
            // FRAGMENT SHADER
            // ---------------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                // Blend between perspective-correct and affine UVs.
                // lerp(a, b, t) returns a when t=0, b when t=1.
                // So at _AffineIntensity = 0, we get modern rendering.
                // At _AffineIntensity = 1, we get full PS1 distortion.
                float2 finalUV = lerp(IN.uvCorrect, IN.uvAffine, _AffineIntensity);

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, finalUV);
                half4 color = texColor * _BaseColor;
                color.rgb *= IN.lighting;
                return color;
            }

            ENDHLSL
        }

        // Self-contained ShadowCaster (avoids URP LerpWhiteTo bug)
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex shadowVert
            #pragma fragment shadowFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float3 _LightDirection;
            float4 _ShadowBias;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            float4 GetShadowPositionHClip(ShadowAttributes IN)
            {
                float3 worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);
                worldPos = worldPos + _LightDirection * _ShadowBias.x;
                worldPos = worldPos + worldNormal * _ShadowBias.y;
                float4 clipPos = TransformWorldToHClip(worldPos);

                #if UNITY_REVERSED_Z
                    clipPos.z = min(clipPos.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    clipPos.z = max(clipPos.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return clipPos;
            }

            ShadowVaryings shadowVert(ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                OUT.positionCS = GetShadowPositionHClip(IN);
                return OUT;
            }

            half4 shadowFrag(ShadowVaryings IN) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
