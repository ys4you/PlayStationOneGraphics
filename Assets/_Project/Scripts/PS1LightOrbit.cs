using UnityEngine;

public class PS1LightOrbit : MonoBehaviour
{
    [Header("Orbit Settings")]
    public float orbitSpeed = 1f;
    public float verticalBob = 0.3f;
    public float verticalBobSpeed = 2f;

    private Vector3 orbitCenter;
    private float angle;

    // Sphere positions relative to center:
    // Gouraud: (-1, 0, 0)
    // Lit:     ( 0, 0, +1)
    // Flat:    ( 1, 0, 0)
    // Light starts at center: (0, 0, -3.22)
    // The path needs to weave between them.

    void Start()
    {
        orbitCenter = transform.position;
    }

    void Update()
    {
        angle += orbitSpeed * Time.deltaTime;

        // Figure-8 path that passes between and around the spheres.
        float sinT = Mathf.Sin(angle);
        float cosT = Mathf.Cos(angle);
        float denom = 1f + sinT * sinT;

        float scale = 1.8f;
        float x = orbitCenter.x + (cosT / denom) * scale;
        float z = orbitCenter.z + (sinT * cosT / denom) * scale;

        // Gentle vertical bob so the light moves in 3D
        float y = orbitCenter.y + Mathf.Sin(angle * verticalBobSpeed) * verticalBob;

        transform.position = new Vector3(x, y, z);
    }
}