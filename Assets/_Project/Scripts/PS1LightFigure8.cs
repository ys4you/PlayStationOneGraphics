using UnityEngine;

// Adaptive figure-8 light path.
// Reads the positions of the showcase objects (cube, capsule, sphere)
// and shapes the lemniscate so it weaves AROUND them without clipping.
//
// The figure-8 is centered between leftAnchor and rightAnchor.
// Width is automatically scaled so the loops sweep just past those
// anchors with a configurable buffer (so the light doesn't touch them).
//
// Setup:
// - Place the light at any starting position.
// - Drag the left object (cube), center object (capsule, optional),
//   and right object (sphere) into the inspector.
// - Adjust SafetyBuffer if the light gets too close to the objects.

public class PS1LightFigure8 : MonoBehaviour
{
    [Header("Anchors (the figure-8 wraps around these)")]
    public Transform leftAnchor;
    public Transform centerAnchor;
    public Transform rightAnchor;

    [Header("Path Settings")]
    public float orbitSpeed = 1f;
    [Tooltip("Distance the light keeps from the anchors. Increase if it clips into objects.")]
    public float safetyBuffer = 0.8f;
    public float verticalBob = 0.3f;
    public float verticalBobSpeed = 2f;

    private float angle;

    void Update()
    {
        if (leftAnchor == null || rightAnchor == null) return;

        angle += orbitSpeed * Time.deltaTime;

        // The orbit center is the midpoint between left and right anchors.
        Vector3 center = (leftAnchor.position + rightAnchor.position) * 0.5f;

        // The center anchor (capsule) sets the vertical reference height
        // so the light orbits at a sensible Y level.
        if (centerAnchor != null)
        {
            center.y = centerAnchor.position.y;
        }

        // Each loop's outer reach is the distance to the side anchor
        // plus the safety buffer. This ensures the light passes just
        // past each object instead of clipping into them.
        float halfDistance = Vector3.Distance(leftAnchor.position, rightAnchor.position) * 0.5f;
        float horizontalScale = halfDistance + safetyBuffer;

        // Lemniscate of Bernoulli (figure-8):
        //   x = cos(t) / (1 + sin(t)^2)
        //   z = sin(t) * cos(t) / (1 + sin(t)^2)
        float sinT = Mathf.Sin(angle);
        float cosT = Mathf.Cos(angle);
        float denom = 1f + sinT * sinT;

        float x = center.x + (cosT / denom) * horizontalScale;
        float z = center.z + (sinT * cosT / denom) * horizontalScale;
        float y = center.y + Mathf.Sin(angle * verticalBobSpeed) * verticalBob;

        transform.position = new Vector3(x, y, z);
    }
}