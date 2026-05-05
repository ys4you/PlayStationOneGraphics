using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;

public class PS1RenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        [Tooltip("Color levels per channel. 32 = authentic PS1 (5-bit), 16 = harsher banding, 64 = subtle.")]
        [Range(2f, 256f)]
        public float colorDepth = 32f;

        [Tooltip("Strength of the Bayer matrix dithering. 1.0 = full PS1, 0.0 = no dithering (visible banding).")]
        [Range(0f, 1f)]
        public float ditherStrength = 1f;

        [Tooltip("When in the render pipeline this effect runs.")]
        public RenderPassEvent injectionPoint = RenderPassEvent.AfterRenderingPostProcessing;
    }

    public Settings settings = new Settings();
    public Shader quantizeShader;

    private Material quantizeMaterial;
    private PS1ColorQuantizePass renderPass;

    public override void Create()
    {
        if (quantizeShader == null)
        {
            quantizeShader = Shader.Find("PS1/PS1ColorQuantize");
        }

        if (quantizeShader != null)
        {
            quantizeMaterial = CoreUtils.CreateEngineMaterial(quantizeShader);
        }

        renderPass = new PS1ColorQuantizePass(quantizeMaterial, settings);
        renderPass.renderPassEvent = settings.injectionPoint;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (quantizeMaterial == null) return;

        // Don't run on previews or reflection probes
        if (renderingData.cameraData.cameraType != CameraType.Game &&
            renderingData.cameraData.cameraType != CameraType.SceneView) return;

        renderPass.UpdateSettings(settings);
        renderer.EnqueuePass(renderPass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(quantizeMaterial);
    }
}

// The actual render pass. Reads the camera color buffer, applies the
// PS1ColorQuantize shader, and writes the result back.
public class PS1ColorQuantizePass : ScriptableRenderPass
{
    private const string PassName = "PS1ColorQuantizePass";

    private Material material;
    private PS1RenderFeature.Settings settings;

    private static readonly int ColorDepthID = Shader.PropertyToID("_ColorDepth");
    private static readonly int DitherStrengthID = Shader.PropertyToID("_DitherStrength");

    public PS1ColorQuantizePass(Material material, PS1RenderFeature.Settings settings)
    {
        this.material = material;
        this.settings = settings;
        requiresIntermediateTexture = true;
    }

    public void UpdateSettings(PS1RenderFeature.Settings settings)
    {
        this.settings = settings;
    }

    // RenderGraph entry point (Unity 6+ API)
    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        if (material == null) return;

        // Push current settings into the material
        material.SetFloat(ColorDepthID, settings.colorDepth);
        material.SetFloat(DitherStrengthID, settings.ditherStrength);

        // Get the active camera color texture
        var resourceData = frameData.Get<UniversalResourceData>();
        var source = resourceData.activeColorTexture;

        // Create a temporary destination texture
        var descriptor = renderGraph.GetTextureDesc(source);
        descriptor.name = "PS1QuantizeTemp";
        descriptor.clearBuffer = false;
        var destination = renderGraph.CreateTexture(descriptor);

        // Blit source -> temp using our material
        RenderGraphUtils.BlitMaterialParameters blitParams =
            new RenderGraphUtils.BlitMaterialParameters(source, destination, material, 0);
        renderGraph.AddBlitPass(blitParams, passName: PassName);

        // Blit temp back to camera color
        renderGraph.AddCopyPass(destination, source, passName: PassName + "_CopyBack");
    }
}