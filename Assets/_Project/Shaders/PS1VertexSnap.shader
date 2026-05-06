// PS1VertexSnap.shader
// Recreates PS1 vertex jitter by snapping vertex positions in NDC space.
// Uses PS1VertexSnap.hlsl for the snap function.

Shader "PS1/PS1VertexSnap"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [Header(Vertex Snapping)]
        _VertexSnapGrid("Snap Resolution", Float) = 160.0
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
            Name "PS1VertexSnapForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Includes/PS1VertexSnap.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                half3  lighting     : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _VertexSnapGrid;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float4 clipPos = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionCS = PS1Snap(clipPos, _VertexSnapGrid);

                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(worldNormal, mainLight.direction));
                OUT.lighting = SampleSH(worldNormal) + mainLight.color * NdotL;

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 color = texColor * _BaseColor;
                color.rgb *= IN.lighting;
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
