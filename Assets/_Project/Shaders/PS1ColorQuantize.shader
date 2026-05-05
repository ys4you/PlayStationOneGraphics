// PS1ColorQuantize.shader
// Fullscreen post-process shader that recreates PS1 color output:
// - 15-bit color (5 bits per channel = 32 levels)
// - 4x4 Bayer matrix ordered dithering to hide banding
// Used by PS1RenderFeature as a fullscreen pass in URP.

Shader "PS1/PS1ColorQuantize"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        // No culling, no depth read/write - this is a fullscreen blit
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "PS1ColorQuantize"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            // URP's Blit.hlsl provides Vert (the fullscreen vertex shader)
            // and the _BlitTexture sampler we read the source image from.
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _ColorDepth;
            float _DitherStrength;

            // 4x4 Bayer matrix used by the PS1 for ordered dithering.
            // Values 0-15, divided by 16 to get a 0..1 threshold per pixel.
            // Each (x, y) screen position picks one of these 16 thresholds
            // based on (x mod 4, y mod 4).
            static const float bayer4x4[16] = {
                 0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
                12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
                 3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
                15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
            };

            // Sample the Bayer matrix at a given pixel coordinate.
            // The threshold is centered around 0 (range -0.5..+0.5)
            // so it nudges colors both up and down evenly.
            float GetBayerThreshold(float2 pixelCoord)
            {
                int x = int(pixelCoord.x) & 3;  // x mod 4
                int y = int(pixelCoord.y) & 3;  // y mod 4
                int index = y * 4 + x;
                return bayer4x4[index] - 0.5;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                // Sample the source image (the rendered scene)
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);

                // Get the pixel coordinate on screen for the dither lookup
                float2 pixelCoord = IN.texcoord * _ScreenParams.xy;
                float threshold = GetBayerThreshold(pixelCoord);

                // Apply dithering: nudge the color by a fraction of one
                // quantization step before rounding. This breaks up the
                // hard banding that pure quantization would create.
                // _DitherStrength = 1.0 means full dither, 0.0 means none.
                float ditherAmount = (threshold * _DitherStrength) / _ColorDepth;
                color.rgb += ditherAmount;

                // Quantize each color channel to _ColorDepth steps.
                // 32 = PS1's 15-bit color (5 bits per channel).
                // floor(c * 32) / 32 maps any value to the nearest level.
                color.rgb = floor(color.rgb * _ColorDepth) / _ColorDepth;

                return color;
            }

            ENDHLSL
        }
    }
}
