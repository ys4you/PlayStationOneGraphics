using UnityEngine;

public class SimpleRotator : MonoBehaviour
{
    [Header("Normalized Rotation Axis (0 = off, 1 = max speed)")]
    [Range(0f, 1f)] public float x = 0f;
    [Range(0f, 1f)] public float y = 0f;
    [Range(0f, 1f)] public float z = 0f;

    [Header("Max Rotation Speed")]
    public float rotationSpeed = 180f; // degrees per second

    void Update()
    {
        Vector3 rotation = new Vector3(x, y, z) * rotationSpeed * Time.deltaTime;
        transform.Rotate(rotation);
    }
}