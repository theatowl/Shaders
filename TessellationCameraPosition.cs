using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class TessellationCameraPosition : MonoBehaviour
{
    public Material tessellation;
    public Camera mainCamera;
    // Update is called once per frame
    void Update()
    {
        var cameraPosition = mainCamera.transform.position;
        tessellation.SetVector("_MainCameraPosition", cameraPosition);
        
    }
}
