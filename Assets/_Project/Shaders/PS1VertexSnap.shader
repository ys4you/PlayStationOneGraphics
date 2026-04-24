// PS1VertexSnap.shader
//
// PURPOSE:
// Recreates the PS1's vertex jitter / polygon wobble effect.
//
// RESEARCH CONTEXT:
// The PS1's polygon jitter comes from TWO hardware limitations:
//
// 1. NO SUBPIXEL RASTERIZATION (primary cause)
//    The PS1 GPU rasterizer only accepted integer screen coordinates.
//    Vertices could not exist "between" pixels. When a vertex's true
//    position was at, say, pixel 100.7, it would snap to pixel 101.
//    On the next frame, if it moved to 100.3, it snaps to 100.
//    This causes vertices to visibly jump between pixel positions
//    rather than sliding smoothly.
//
//    Modern GPUs use subpixel rasterization (typically 8x8 or 16x16
//    sub-grid within each pixel) to handle this smoothly. The PS1
//    had none of this.
//
//    Source: David Colson - "Building a PS1 style retro 3D renderer"
//    Source: Pikuma - "How PlayStation Graphics & Visual Artefacts Work"
//
// 2. GTE FIXED-POINT PRECISION (secondary cause)
//    The Geometry Transformation Engine used 16-bit fixed-point math
//    for all coordinate transformations. The RTPS (Rotate, Translate,
//    Perspective Single) instruction outputs screen X/Y as integers
//    in the range -400h to +3FFh (-1024 to +1023).
//
//    When multiple rotations and translations stack, precision errors
//    accumulate. This adds a subtle additional wobble on top of the
//    rasterizer snapping.
//
//    Source: psx-spx.consoledev.net/geometrytransformationenginegte/
//
// HOW THIS SHADER RECREATES IT:
// We snap vertex positions to a low-resolution grid AFTER projection
// (in NDC space), simulating what the PS1 rasterizer did to incoming
// vertex coordinates. The grid resolution maps to the PS1's output
// resolution (typically 320x240, so 160x120 in NDC half-units).
//
// WHAT TO LOOK FOR WHEN TESTING:
// - Place a textured cube in the scene and slowly rotate the camera.
//   Vertices should visibly "pop" between positions.
// - The effect is stronger on distant objects (more vertices compressed
//   into fewer pixels) and weaker on close objects.
// - Lower _VertexSnapGrid values = more aggressive snapping.
//   Try 80 for extreme PS1, 160 for standard 320x240, 320 for subtle.

Shader "PS1/PS1VertexSnap"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [Header(Vertex Snapping)]
        _VertexSnapGrid("Snap Resolution", Float) = 160.0
        // 160 = half of 320 (PS1 horizontal res)
        // because NDC ranges from -1 to +1 (total width of 2)
        // so 320 pixels / 2 = 160 grid cells per NDC unit
        //
        // Common values:
        //   80  = very aggressive, like a 160x120 display
        //  160  = standard PS1 (320x240)
        //  320  = subtle, like a 640x480 display
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

            // URP core includes:
            // - Core.hlsl gives us TransformObjectToHClip, TRANSFORM_TEX, etc.
            // - Lighting.hlsl gives us GetMainLight, SampleSH, etc.
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ---------------------------------------------------------------
            // INPUT STRUCT (vertex data from the mesh)
            // ---------------------------------------------------------------
            // These come directly from the mesh asset.
            // POSITION  = object-space vertex position (x,y,z,w)
            // NORMAL    = object-space vertex normal (for lighting)
            // TEXCOORD0 = first UV channel
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
            };

            // ---------------------------------------------------------------
            // OUTPUT STRUCT (data passed from vertex to fragment shader)
            // ---------------------------------------------------------------
            // SV_POSITION = clip-space position (GPU uses this for rasterization)
            // TEXCOORD0   = texture coordinates
            // TEXCOORD1   = pre-computed lighting value
            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                half3  lighting     : TEXCOORD1;
            };

            // ---------------------------------------------------------------
            // MATERIAL PROPERTIES
            // ---------------------------------------------------------------
            // TEXTURE2D + SAMPLER declare the texture and its sampling state.
            // CBUFFER_START/END wraps uniforms for SRP Batcher compatibility.
            // Without the CBUFFER, every draw call with this material would
            // break batching and hurt performance.
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;     // Tiling (xy) and Offset (zw) from material
                half4  _BaseColor;      // Color tint
                float  _VertexSnapGrid; // Grid resolution for snapping
            CBUFFER_END

            // ---------------------------------------------------------------
            // PS1Snap FUNCTION
            // ---------------------------------------------------------------
            // This is the core of the entire shader. Everything else is just
            // standard URP boilerplate.
            //
            // INPUT:  clipPos  = vertex position in clip space (after projection)
            //         gridSize = snapping resolution (160 for 320x240)
            //
            // OUTPUT: clipPos with XY snapped to the nearest grid position
            //
            // THE MATH:
            //
            // Step A: clipPos.xy / clipPos.w
            //   Clip space is "pre-division" space. The GPU normally divides
            //   by W during rasterization to get NDC (screen-mapped coords).
            //   We do it early here so we can work in screen-aligned space.
            //   NDC X and Y both range from -1.0 to +1.0.
            //
            // Step B: floor(ndcPos * gridSize + 0.5) / gridSize
            //   This is a "round to nearest" operation on a grid.
            //   - Multiply by gridSize: scales NDC into pixel-sized units
            //     e.g. 0.507 * 160 = 81.12
            //   - Add 0.5: shifts so that floor() rounds to nearest instead
            //     of always rounding down
            //     81.12 + 0.5 = 81.62, floor = 81
            //   - floor(): drops the fractional part, snapping to integer
            //   - Divide by gridSize: scales back to NDC range
            //     81 / 160 = 0.50625
            //   The vertex just jumped from 0.507 to 0.50625.
            //   On a 320px wide screen, that is a 1-pixel jump.
            //
            // Step C: ndcPos * clipPos.w
            //   The GPU expects clip-space output (it will do its own /W).
            //   So we multiply W back in to undo our early division.
            //
            // WHY CLIP SPACE AND NOT WORLD SPACE?
            //   The PS1's snapping happened at the rasterizer level, which
            //   operates on screen coordinates (post-projection). If we
            //   snapped in world space, the grid would be fixed in the world
            //   and objects would wobble differently at different distances.
            //   By snapping in NDC (screen space), distant vertices snap
            //   more aggressively (more world-space movement per pixel),
            //   which matches the real PS1 behavior.
            //
            float4 PS1Snap(float4 clipPos, float gridSize)
            {
                // A: Perspective divide to get NDC
                float2 ndcPos = clipPos.xy / clipPos.w;

                // B: Snap to nearest grid position
                ndcPos = floor(ndcPos * gridSize + 0.5) / gridSize;

                // C: Undo perspective divide (back to clip space)
                clipPos.xy = ndcPos * clipPos.w;

                return clipPos;
            }

            // ---------------------------------------------------------------
            // VERTEX SHADER
            // ---------------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // Transform from object space to clip space.
                // TransformObjectToHClip does: Model -> World -> View -> Projection
                // This is equivalent to what the PS1's GTE RTPS instruction did,
                // but with full 32-bit float precision instead of 16-bit fixed-point.
                float4 clipPos = TransformObjectToHClip(IN.positionOS.xyz);

                // Apply the PS1 vertex snap.
                // After this, clipPos.xy is locked to the nearest grid position.
                OUT.positionCS = PS1Snap(clipPos, _VertexSnapGrid);

                // Pass UVs through (no modification here, affine mapping is a
                // separate effect for a separate shader).
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                // Basic per-vertex lighting so we can see the geometry.
                // This is standard URP Lambert, nothing PS1-specific here.
                // We will replace this with proper PS1 vertex lighting in
                // a later shader.
                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(worldNormal, mainLight.direction));
                OUT.lighting = SampleSH(worldNormal) + mainLight.color * NdotL;

                return OUT;
            }

            // ---------------------------------------------------------------
            // FRAGMENT SHADER
            // ---------------------------------------------------------------
            // Intentionally simple. This shader is about the vertex stage.
            // Just sample the texture and apply lighting.
            half4 frag(Varyings IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 color = texColor * _BaseColor;
                color.rgb *= IN.lighting;
                return color;
            }

            ENDHLSL
        }

        // ShadowCaster pass: lets objects using this shader cast shadows.
        // Without this pass, any mesh using PS1VertexSnap would be invisible
        // to the shadow system and would not cast shadows on other objects.
        //
        // NOTE: We write our own minimal ShadowCaster instead of including
        // URP's ShadowCasterPass.hlsl because certain URP versions have a
        // bug where Shadows.hlsl references LerpWhiteTo without including
        // the file that defines it (known issue, fixed in Unity 6000.1.0a9).
        // This self-contained version avoids that dependency entirely.
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

            // These uniforms are set by URP each time it renders a
            // shadow-casting light. Normally they come from Shadows.hlsl,
            // but since we skip that include (LerpWhiteTo bug), we
            // declare them ourselves.
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

            // Apply shadow depth bias to avoid shadow acne.
            // Pushes the vertex along the light direction and normal.
            float4 GetShadowPositionHClip(ShadowAttributes IN)
            {
                float3 worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                float3 worldNormal = TransformObjectToWorldNormal(IN.normalOS);

                // Offset along light direction (depth bias) and normal (normal bias)
                // _ShadowBias.x = depth bias, _ShadowBias.y = normal bias
                // These are set by URP per shadow-casting light.
                worldPos = worldPos + _LightDirection * _ShadowBias.x;
                worldPos = worldPos + worldNormal * _ShadowBias.y;

                float4 clipPos = TransformWorldToHClip(worldPos);

                // Clamp depth to near plane (DirectX/Vulkan clip space)
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
