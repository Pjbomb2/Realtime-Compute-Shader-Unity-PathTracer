using System.Collections;
using System.Collections.Generic;
using UnityEngine;


[ExecuteInEditMode][System.Serializable]
public class RayTracingLights : MonoBehaviour {
    public Vector3 Emission;
    public Vector3 Direction;
    public Vector3 Position;
    public int Type;
    [HideInInspector]
    public Light ThisLight;
    public Vector2 SpotAngle;
    public float Energy;

    private float luminance(float r, float g, float b) {
        return 0.299f * r + 0.587f * g + 0.114f * b;
    }
    public void UpdateLight() {
        if(ThisLight == null) {ThisLight = this.GetComponent<Light>();}
        Position = this.transform.position;
        Color col = ThisLight.color; 
        Emission = new Vector3(col[0], col[1], col[2]) * ThisLight.intensity / 1000.0f;
        Direction = (ThisLight.type == LightType.Directional) ? -RayTracingMaster.SunDirection : (ThisLight.type == LightType.Spot) ? Vector3.Normalize(this.transform.TransformDirection(Vector3.forward)) : new Vector3(0.0f, 0.0f, 0.0f);
        Type = (ThisLight.type == LightType.Point) ? 0 : (ThisLight.type == LightType.Directional) ? 1 : 2; //this.transform.TransformDirection(Vector3.forward)
        SpotAngle = (ThisLight.type == LightType.Spot) ? (new Vector2(ThisLight.spotAngle, ThisLight.innerSpotAngle) * (3.14159f / 180.0f) * 0.15f) : new Vector2(0.0f, 0.0f);
        Energy = luminance(Emission.x, Emission.y, Emission.z);
    }

    private void OnEnable() { 
        UpdateLight();           
        RayTracingMaster.RegisterObject(this);
    }

    private void OnDisable() {
        RayTracingMaster.UnregisterObject(this);
    }
}
