using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using TMPro;

public class PS1ShowcaseController : MonoBehaviour
{
    [System.Serializable]
    public class CameraShot
    {
        [Tooltip("Display label for this step")]
        public string label = "Step";

        [Tooltip("How long to ease toward this shot (seconds)")]
        public float duration = 2f;

        [Header("Effects")]
        public bool vertexSnap;
        public bool affineMapping;
        public bool flatShading;
        public bool postProcess;

        [Header("Camera (optional)")]
        public bool animateCamera = true;
        public Vector3 cameraPosition = new Vector3(0f, 1.5f, -4f);
        public Vector3 cameraRotation = new Vector3(8f, 0f, 0f);

        [Header("Lighting (optional)")]
        public bool animateLighting = true;
        public Color pointLightColor = Color.white;
        [Range(0f, 3f)] public float directionalIntensity = 1f;
    }

    [Header("Hero Objects (light orbits around these)")]
    public Transform leftAnchor;
    public Transform centerAnchor;
    public Transform rightAnchor;

    [Header("PS1 Materials (using PS1Lit shader)")]
    public List<Material> ps1Materials = new List<Material>();

    [Header("URP Renderer Data")]
    public ScriptableRendererData rendererData;

    [Header("Lighting (optional)")]
    public Light pointLight;
    public Light directionalLight;

    [Header("Camera (optional - leave empty to skip camera moves)")]
    public Camera showcaseCamera;

    [Header("Optional Label")]
    public TMP_Text statusLabel;

    [Header("Light Path")]
    public float arcRadius = 2.8f;
    public float orbitSpeed = 1.2f;
    public float arcHeight = 1.0f;
    public float centerAvoidance = 1.0f;

    [Header("Loop")]
    public bool loop = true;

    [Header("Cinematic Shots (edit freely)")]
    public List<CameraShot> shots = new List<CameraShot>();

    // Shader keyword names (must match PS1Lit shader's [Toggle(...)] attributes)
    private const string KW_VERTEX_SNAP = "_VERTEX_SNAP";
    private const string KW_AFFINE      = "_AFFINE_MAPPING";
    private const string KW_FLAT        = "_FLAT_SHADING";

    // Float property names (must match PS1Lit shader's [Toggle] property names).
    // The [Toggle] attribute in shaderlab creates BOTH a float property and a
    // shader keyword. To toggle the effect at runtime properly, we need to set
    // both the float property AND enable/disable the keyword.
    private const string PROP_VERTEX_SNAP = "_VertexSnap";
    private const string PROP_AFFINE      = "_AffineMapping";
    private const string PROP_FLAT        = "_FlatShading";

    private PS1RenderFeature ps1Feature;
    private float orbitAngle;

    [ContextMenu("Reset to Default 15-Second Intro")]
    public void ResetToDefaultTimeline()
    {
        shots = new List<CameraShot>
        {
            new CameraShot {
                label = "Modern Rendering", duration = 2.5f,
                vertexSnap = false, affineMapping = false, flatShading = false, postProcess = false,
                animateCamera = true, cameraPosition = new Vector3(0f, 2.2f, -5.5f), cameraRotation = new Vector3(12f, 0f, 0f),
                animateLighting = true, pointLightColor = Color.white, directionalIntensity = 1.0f
            },
            new CameraShot {
                label = "+ Vertex Snapping", duration = 2.0f,
                vertexSnap = true, affineMapping = false, flatShading = false, postProcess = false,
                animateCamera = true, cameraPosition = new Vector3(0f, 1.4f, -3.0f), cameraRotation = new Vector3(5f, 0f, 0f),
                animateLighting = true, pointLightColor = Color.white, directionalIntensity = 1.0f
            },
            new CameraShot {
                label = "+ Affine Texture Mapping", duration = 2.0f,
                vertexSnap = true, affineMapping = true, flatShading = false, postProcess = false,
                animateCamera = true, cameraPosition = new Vector3(-1.5f, 0.6f, -2.8f), cameraRotation = new Vector3(-2f, 25f, 0f),
                animateLighting = true, pointLightColor = Color.white, directionalIntensity = 1.0f
            },
            new CameraShot {
                label = "+ Flat Shading", duration = 2.0f,
                vertexSnap = true, affineMapping = true, flatShading = true, postProcess = false,
                animateCamera = true, cameraPosition = new Vector3(2.5f, 1.5f, -2.5f), cameraRotation = new Vector3(8f, -35f, 0f),
                animateLighting = true, pointLightColor = new Color(1f, 0.85f, 0.55f), directionalIntensity = 0.9f
            },
            new CameraShot {
                label = "+ Color Quantization & Dither", duration = 2.5f,
                vertexSnap = true, affineMapping = true, flatShading = true, postProcess = true,
                animateCamera = true, cameraPosition = new Vector3(0f, 1.8f, -4.5f), cameraRotation = new Vector3(8f, 0f, 0f),
                animateLighting = true, pointLightColor = new Color(1f, 0.85f, 0.55f), directionalIntensity = 0.9f
            },
            new CameraShot {
                label = "Full PS1 Look", duration = 4.0f,
                vertexSnap = true, affineMapping = true, flatShading = true, postProcess = true,
                animateCamera = true, cameraPosition = new Vector3(0f, 1.6f, -3.8f), cameraRotation = new Vector3(6f, 0f, 0f),
                animateLighting = true, pointLightColor = new Color(0.6f, 0.7f, 1f), directionalIntensity = 0.8f
            }
        };
    }

    [ContextMenu("Add Shot From Current Camera")]
    void AddShotFromCamera()
    {
        if (showcaseCamera == null)
        {
            Debug.LogWarning("[PS1 Showcase] Cannot capture: no camera assigned.");
            return;
        }

        shots.Add(new CameraShot
        {
            label = "New Shot",
            duration = 2f,
            cameraPosition = showcaseCamera.transform.position,
            cameraRotation = showcaseCamera.transform.rotation.eulerAngles,
            animateCamera = true,
            animateLighting = false,
            pointLightColor = Color.white,
            directionalIntensity = 1f
        });
    }

    void OnValidate()
    {
        if (shots == null || shots.Count == 0) ResetToDefaultTimeline();
    }

    void Start()
    {
        if (rendererData != null)
        {
            foreach (var feature in rendererData.rendererFeatures)
            {
                if (feature is PS1RenderFeature found)
                {
                    ps1Feature = found;
                    break;
                }
            }
        }

        StartCoroutine(RunCinematic());
    }

    void Update()
    {
        DriveLightOrbit();
    }

    void DriveLightOrbit()
    {
        if (pointLight == null || leftAnchor == null || rightAnchor == null) return;

        orbitAngle += orbitSpeed * Time.deltaTime;

        Vector3 center = (leftAnchor.position + rightAnchor.position) * 0.5f;
        if (centerAnchor != null) center.y = centerAnchor.position.y;

        float halfWidth = Vector3.Distance(leftAnchor.position, rightAnchor.position) * 0.5f;
        float effectiveRadius = halfWidth + (arcRadius - halfWidth);

        float x = center.x + Mathf.Cos(orbitAngle) * effectiveRadius;
        float z = center.z + Mathf.Sin(orbitAngle) * effectiveRadius;

        float distFromCenter = Mathf.Sqrt(
            (x - center.x) * (x - center.x) +
            (z - center.z) * (z - center.z)
        );

        float closeness = Mathf.Clamp01(1f - distFromCenter / centerAvoidance);
        float y = center.y + closeness * arcHeight;

        pointLight.transform.position = new Vector3(x, y, z);
    }

    IEnumerator RunCinematic()
    {
        if (shots == null || shots.Count == 0) yield break;

        do
        {
            ApplyShotState(shots[0]);
            ApplyCameraInstant(shots[0]);
            ApplyLightingInstant(shots[0]);
            SetLabelText(shots[0].label);

            yield return new WaitForSeconds(shots[0].duration);

            for (int i = 1; i < shots.Count; i++)
            {
                CameraShot from = shots[i - 1];
                CameraShot to = shots[i];

                ApplyShotState(to);
                SetLabelText(to.label);

                yield return EaseShot(from, to, to.duration);
            }

        } while (loop);
    }

    IEnumerator EaseShot(CameraShot from, CameraShot to, float duration)
    {
        float t = 0f;

        Vector3 fromPos = from.cameraPosition;
        Quaternion fromRot = Quaternion.Euler(from.cameraRotation);
        Vector3 toPos = to.cameraPosition;
        Quaternion toRot = Quaternion.Euler(to.cameraRotation);

        while (t < duration)
        {
            t += Time.deltaTime;
            float eased = SmoothStep(Mathf.Clamp01(t / duration));

            if (showcaseCamera != null && to.animateCamera)
            {
                showcaseCamera.transform.position = Vector3.Lerp(fromPos, toPos, eased);
                showcaseCamera.transform.rotation = Quaternion.Slerp(fromRot, toRot, eased);
            }

            if (to.animateLighting)
            {
                if (pointLight != null)
                    pointLight.color = Color.Lerp(from.pointLightColor, to.pointLightColor, eased);

                if (directionalLight != null)
                    directionalLight.intensity = Mathf.Lerp(from.directionalIntensity, to.directionalIntensity, eased);
            }

            yield return null;
        }

        ApplyCameraInstant(to);
        ApplyLightingInstant(to);
    }

    void ApplyCameraInstant(CameraShot shot)
    {
        if (showcaseCamera == null || !shot.animateCamera) return;
        showcaseCamera.transform.position = shot.cameraPosition;
        showcaseCamera.transform.rotation = Quaternion.Euler(shot.cameraRotation);
    }

    void ApplyLightingInstant(CameraShot shot)
    {
        if (!shot.animateLighting) return;
        if (pointLight != null) pointLight.color = shot.pointLightColor;
        if (directionalLight != null) directionalLight.intensity = shot.directionalIntensity;
    }

    // Sets BOTH the float property and the shader keyword.
    // Shader's [Toggle(KEYWORD)] attribute creates both, and the inspector
    // syncs them. Setting only the keyword leaves the float out of sync,
    // which can cause Unity to "fix" it later by disabling the keyword.
    void SetToggle(Material mat, string propertyName, string keyword, bool enabled)
    {
        mat.SetFloat(propertyName, enabled ? 1f : 0f);
        if (enabled) mat.EnableKeyword(keyword);
        else mat.DisableKeyword(keyword);
    }

    void ApplyShotState(CameraShot shot)
    {
        foreach (var mat in ps1Materials)
        {
            if (mat == null) continue;
            SetToggle(mat, PROP_VERTEX_SNAP, KW_VERTEX_SNAP, shot.vertexSnap);
            SetToggle(mat, PROP_AFFINE, KW_AFFINE, shot.affineMapping);
            SetToggle(mat, PROP_FLAT, KW_FLAT, shot.flatShading);
        }

        if (ps1Feature != null) ps1Feature.SetActive(shot.postProcess);
    }

    void SetLabelText(string text)
    {
        if (statusLabel != null) statusLabel.text = text;
        Debug.Log("[PS1 Showcase] " + text);
    }

    float SmoothStep(float t) => t * t * (3f - 2f * t);
}