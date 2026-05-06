#ifndef PS1_AFFINE_MAPPING_INCLUDED
#define PS1_AFFINE_MAPPING_INCLUDED

// PS1AffineMapping.hlsl
// Helper for PS1-style affine texture mapping using noperspective.
//
// HOW TO USE:
// 1. In your Varyings struct, declare:
//        noperspective float2 uvAffine : TEXCOORDn;
//        float2 uvCorrect              : TEXCOORDn;
// 2. In the vertex shader, write the same UV to both:
//        OUT.uvAffine  = baseUV;
//        OUT.uvCorrect = baseUV;
// 3. In the fragment shader, blend between them:
//        float2 finalUV = PS1ResolveAffineUV(IN.uvCorrect, IN.uvAffine, _AffineIntensity);
//
// _AffineIntensity = 0 -> modern (perspective-correct)
// _AffineIntensity = 1 -> full PS1 (affine)

float2 PS1ResolveAffineUV(float2 uvCorrect, float2 uvAffine, float intensity)
{
    return lerp(uvCorrect, uvAffine, intensity);
}

#endif
