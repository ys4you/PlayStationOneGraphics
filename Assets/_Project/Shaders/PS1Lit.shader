// PS1Lit.shader
// Combined PS1 shader applying all per-object effects together:
//   - Vertex snapping (PS1VertexSnap.hlsl)
//   - Affine texture mapping (PS1AffineMapping.hlsl)
//   - Vertex lighting (PS1VertexLighting.hlsl)
// Each effect can be toggled independently per material.
// Pair with the PS1RenderFeature for screen-space color quantization.

Shader "PS1/PS1Lit"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [Header(Vertex Snapping)]
        [Toggle(_VERTEX_SNAP)] _VertexSnap("Enable Vertex Snap", Float) = 1.0
        _VertexSnapGrid("Snap Resolution", Float) = 160.0

        [Header(Affine Texture Mapping)]
        [Toggle(_AFFINE_MAPPING)] _AffineMapping("Enable Affine Mapping", Float) = 1.0
        _AffineIntensity("Affine Intensity", Range(0.0, 1.0)) = 1.0

        [Header(Vertex Lighting)]
        [Toggle(_FLAT_SHADING)] _FlatShading("Flat Shading (vs Gouraud)", Float) = 0.0
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
            Name "PS1LitForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma shader_feature_local _VERTEX_SNAP
            #pragma shader_feature_local _AFFINE_MAPPING
            #pragma shader_feature_local _FLAT_SHADING
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Includes/PS1VertexSnap.hlsl"
            #include "Includes/PS1AffineMapping.hlsl"
            #include "Includes/PS1VertexLighting.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;

                #if defined(_AFFINE_MAPPING)
                    noperspective float2 uvAffine : TEXCOORD0;
                    float2 uvCorrect              : TEXCOORD1;
                #else
                    float2 uv                     : TEXCOORD0;
                #endif

                #if defined(_FLAT_SHADING)
                    nointerpolation half3 vertexLighting : TEXCOORD2;
                #else
                    half3 vertexLighting : TEXCOORD2;
                #endif
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _VertexSnapGrid;
                float  _AffineIntensity;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // Position with optional vertex snap
                float4 clipPos = TransformObjectToHClip(IN.positionOS.xyz);
                #if defined(_VERTEX_SNAP)
                    clipPos = PS1Snap(clipPos, _VertexSnapGrid);
                #endif
                OUT.positionCS = clipPos;

                // UVs - dual output for affine blending
                float2 baseUV = TRANSFORM_TEX(IN.uv, _BaseMap);
                #if defined(_AFFINE_MAPPING)
                    OUT.uvAffine  = baseUV;
                    OUT.uvCorrect = baseUV;
                #else
                    OUT.uv = baseUV;
                #endif

                // Lighting
                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);
                float3 worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.vertexLighting = PS1ComputeVertexLighting(worldPos, worldNormal);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // Resolve UVs
                #if defined(_AFFINE_MAPPING)
                    float2 finalUV = PS1ResolveAffineUV(IN.uvCorrect, IN.uvAffine, _AffineIntensity);
                #else
                    float2 finalUV = IN.uv;
                #endif

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, finalUV);
                half4 color = texColor * _BaseColor;
                color.rgb *= IN.vertexLighting;
                return color;
            }

            ENDHLSL
        }

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
