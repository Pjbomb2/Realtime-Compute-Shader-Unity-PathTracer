using System.Collections.Generic;
using UnityEngine;

public class RayTracingMaster : MonoBehaviour {
    private ComputeShader RayTracingShader;
    private ComputeShader AtmosphereGeneratorShader;
    public Texture SkyboxTexture;
    
    private Camera _camera;
    private float _lastFieldOfView;
    public RenderTexture _target;
    private RenderTexture _converged;
    private RenderTexture _PosTex;
    private RenderTexture _Albedo;
    private RenderTexture _NormTex;
    private RenderTexture _IntermediateTex;
    private RenderTexture _DebugTex;
    private RenderTexture _FinalTex;

    public Denoiser Denoisers;
    private AtmosphereGenerator Atmo;

    private AssetManager Assets;

    private Material _addMaterial;
    private int _currentSample = 0;
    private List<Transform> _transformsToWatch = new List<Transform>();
    private static bool _meshObjectsNeedRebuilding = false;
    public static List<RayTracingLights> _rayTracingLights = new List<RayTracingLights>();
    private ComputeBuffer _meshObjectBuffer;
    private ComputeBuffer _MaterialDataBuffer;
    private ComputeBuffer _CompactedMeshData;
    private ComputeBuffer _RayBuffer1;
    private ComputeBuffer _RayBuffer2;
    private ComputeBuffer _ColorBuffer;
    private ComputeBuffer _BufferSizes;
    private ComputeBuffer _ShadowBuffer;
    private ComputeBuffer _LightTriangles;
    private ComputeBuffer _UnityLights;
    private ComputeBuffer _LightMeshes;
    private ComputeBuffer _OctreeBuffer;
    private ComputeBuffer _VoxelTLAS;
    private ComputeBuffer _CurrentReservoir;
    private ComputeBuffer _PreviousReservoir;
    private ComputeBuffer _IntermediateReservoir;
    private int FramesSinceStart2;
    [HideInInspector] public BufferSizeData[] BufferSizes;
    public int SampleCount;

    public float SunZOff;

    private int uFirstFrame = 1;
    [HideInInspector] public int bouncecount = 24;
    [HideInInspector] public float c_phiGlob = 0.1f;
    [HideInInspector] public float n_phiGlob = 0.1f;
    [HideInInspector] public float p_phiGlob = 0.1f;
    [HideInInspector] public bool UseSVGF = false;
    [HideInInspector] public bool UseAtrous = false;
    [HideInInspector] public bool UseRussianRoulette = true;
    [HideInInspector] public bool UseNEE = true;
    [HideInInspector] public bool AllowVolumetrics = false;
    [HideInInspector] public bool DoTLASUpdates = true;
    [HideInInspector] public bool AllowConverge = true;
    [HideInInspector] public bool AllowBloom = false;
    [HideInInspector] public bool AllowDoF = false;
    [HideInInspector] public bool AllowAutoExpose = false;
    [HideInInspector] public bool AllowTAA = false;
    [HideInInspector] public float DoFAperature = 0.2f;
    [HideInInspector] public float DoFFocal = 0.2f;
    public bool DoVoxels = false;

    [HideInInspector] public int SVGFAtrousKernelSizes = 6;
    [HideInInspector] public int AtrousKernelSizes = 6;
    [HideInInspector] public int LightTrianglesCount;
    [HideInInspector] public float SunDirFloat = 0.0f;
    [HideInInspector] public float VolumeDensity = 0.0001f;
    private int threadGroupsX;
    private int threadGroupsY;
    private int threadGroupsX2;
    private int threadGroupsY2;
    private int threadGroupsX3;
    private int threadGroupsY3;
    private int GenKernel;
    private int TraceKernel;
    private int ShadeKernel;
    private int ShadowKernel;
    private int FinalizeKernel;
    private int OctreeKernel;
    private int OctreeShadowKernel;
    private int ReservoirKernel;
    private int ReservoirSpatialKernel;
    private int ReservoirCopyKernel;
    private int FramesSinceStart;
    private Matrix4x4 PrevViewProjection;
    private int TargetWidth;
    private int TargetHeight;
    private int SourceWidth;
    private int SourceHeight;


    [System.Serializable]
    public struct BufferSizeData {
        public int tracerays;
        public int rays_retired;
        public int octree_rays_retired;
        public int shade_rays;
        public int shadow_rays;
        public int retired_shadow_rays;
        public int retired_octree_shadow_rays;
    }
    public bool HasStarted = false;
    void Start() {
        if(RayTracingShader == null) {RayTracingShader = Resources.Load<ComputeShader>("RayTracingShader");}
        if(AtmosphereGeneratorShader == null) {AtmosphereGeneratorShader = Resources.Load<ComputeShader>("Utility/AtmosphereLUTGenerator");}
        SourceWidth = Screen.width;
        SourceHeight = Screen.height;
        TargetWidth = Screen.width;
        TargetHeight = Screen.height;
        
        _meshObjectsNeedRebuilding = true;
        Assets = GameObject.Find("Scene").GetComponent<AssetManager>();
        Assets.BuildCombined();
        LightTrianglesCount = Assets.AggLightTriangles.Count;
        uFirstFrame = 1;
        FramesSinceStart = 0;
        threadGroupsX = Mathf.CeilToInt(SourceWidth / 256.0f);
        threadGroupsY = Mathf.CeilToInt(SourceHeight / 1.0f);
        threadGroupsX2 = Mathf.CeilToInt(SourceWidth / 8.0f);
        threadGroupsY2 = Mathf.CeilToInt(SourceHeight / 8.0f);
        threadGroupsX3 = Mathf.CeilToInt(SourceWidth / 16.0f);
        threadGroupsY3 = Mathf.CeilToInt(SourceHeight / 16.0f);
        GenKernel = RayTracingShader.FindKernel("Generate");
        TraceKernel = RayTracingShader.FindKernel("kernel_trace");
        ShadowKernel = RayTracingShader.FindKernel("kernel_shadow");
        ShadeKernel = RayTracingShader.FindKernel("kernel_shade");
        FinalizeKernel = RayTracingShader.FindKernel("kernel_finalize");
        OctreeKernel = RayTracingShader.FindKernel("kernel_octree_trace");
        OctreeShadowKernel = RayTracingShader.FindKernel("kernel_shadow_octree");
        ReservoirKernel = RayTracingShader.FindKernel("kernel_reservoir");
        ReservoirSpatialKernel = RayTracingShader.FindKernel("kernel_reservoir_spatial");
        ReservoirCopyKernel = RayTracingShader.FindKernel("kernel_reservoir_copy");

        Atmo = new AtmosphereGenerator(AtmosphereGeneratorShader, 6371.0f, 6403.0f);
        FramesSinceStart2 = 0;

        Denoisers = new Denoiser(_camera, SourceWidth, SourceHeight);
        HasStarted = true;
    }

    private void Awake() {
        _camera = GetComponent<Camera>();
        _transformsToWatch.Add(transform);
    }

    private void OnEnable() {
        _currentSample = 0;
    }

    private void OnDisable() {
        _meshObjectBuffer?.Release();
        _MaterialDataBuffer?.Release();
        _CompactedMeshData?.Release();
        _RayBuffer1?.Release();
        _RayBuffer2?.Release();
        _ColorBuffer?.Release();
        _BufferSizes?.Release();
        _ShadowBuffer?.Release();
        _LightTriangles?.Release();
        _UnityLights?.Release();
        _LightMeshes?.Release();
        _OctreeBuffer?.Release();
        _VoxelTLAS?.Release();
        _CurrentReservoir?.Release();
        _PreviousReservoir?.Release();
    }
    public static Vector3 SunDirection;
    private void Update() {
        SunDirection = new Vector3(Mathf.Cos(SunDirFloat), Mathf.Sin(SunDirFloat), SunZOff);

        RayTracingShader.SetVector("SunDir", SunDirection);
        if(!AllowConverge) {
            SampleCount = 0;
            FramesSinceStart = 0;
        }

        if (_camera.fieldOfView != _lastFieldOfView) {
            FramesSinceStart = 0;
            _lastFieldOfView = _camera.fieldOfView;
        }

        foreach (Transform t in _transformsToWatch) {
            if (t.hasChanged) {
                SampleCount = 0;
                FramesSinceStart = 0;
                t.hasChanged = false;
            }
        }
    }

    public static void RegisterObject(RayTracingLights obj) {//Adds meshes to list
        _rayTracingLights.Add(obj);
        _meshObjectsNeedRebuilding = true;
    }
    public static void UnregisterObject(RayTracingLights obj) {//Removes meshes from list
        _rayTracingLights.Remove(obj);
        _meshObjectsNeedRebuilding = true;
    }   

    private void CreateDynamicBuffer(ref ComputeBuffer TargetBuffer, int Stride) {
        if(TargetBuffer == null) TargetBuffer = new ComputeBuffer(SourceWidth * SourceHeight, Stride);
    }
    public float[] TempData;
    public void RebuildMeshObjectBuffers() {
        if(uFirstFrame != 1) {
            if(DoTLASUpdates) {
                if(Assets.UpdateTLAS()) {
                    CreateComputeBuffer(ref _CompactedMeshData, Assets.MyMeshesCompacted, 176);
                    CreateComputeBuffer(ref _LightTriangles, Assets.AggLightTriangles, 72);
                    CreateComputeBuffer(ref _MaterialDataBuffer, Assets._Materials, 136);
                    CreateComputeBuffer(ref _UnityLights, Assets.UnityLights, 56);
                    CreateComputeBuffer(ref _LightMeshes, Assets.LightMeshes, 92);
                    CreateComputeBuffer(ref _OctreeBuffer, Assets.GPUOctree, 28);
                    CreateComputeBuffer(ref _VoxelTLAS, Assets.VoxelTLAS, 80);
                    uFirstFrame = 1;
                } else {
                    _CompactedMeshData.SetData(Assets.MyMeshesCompacted);
                    if(Assets.LightMeshCount != 0) _LightMeshes.SetData(Assets.LightMeshes);
                    if(Assets.UnityLightCount != 0) _UnityLights.SetData(Assets.UnityLights);
                    Assets.UpdateMaterials();
                    _MaterialDataBuffer.SetData(Assets._Materials);
                    if(Assets.UseVoxels) _VoxelTLAS.SetData(Assets.VoxelTLAS);
                }
            }
        }

        if (!_meshObjectsNeedRebuilding) return;

        _meshObjectsNeedRebuilding = false;
        FramesSinceStart = 0;
        CreateComputeBuffer(ref _OctreeBuffer, Assets.GPUOctree, 28);
        CreateComputeBuffer(ref _UnityLights, Assets.UnityLights, 56);
        CreateComputeBuffer(ref _VoxelTLAS, Assets.VoxelTLAS, 80);
        CreateComputeBuffer(ref _LightMeshes, Assets.LightMeshes, 92);
        
        CreateComputeBuffer(ref _MaterialDataBuffer, Assets._Materials, 136);
        CreateComputeBuffer(ref _CompactedMeshData, Assets.MyMeshesCompacted, 176);
        CreateComputeBuffer(ref _LightTriangles, Assets.AggLightTriangles, 72);

        CreateDynamicBuffer(ref _RayBuffer1, 48);
//        CreateDynamicBuffer(ref _ShadowBuffer, 44);
        if(_ShadowBuffer == null) _ShadowBuffer = new ComputeBuffer(SourceWidth * SourceHeight * 2, 54);
        CreateDynamicBuffer(ref _RayBuffer2, 48);
        CreateDynamicBuffer(ref _ColorBuffer, 48);
        CreateDynamicBuffer(ref _BufferSizes, 28);
        CreateDynamicBuffer(ref _CurrentReservoir, 48);
        CreateDynamicBuffer(ref _PreviousReservoir, 48);
    }


    private void CreateComputeBuffer<T>(ref ComputeBuffer buffer, List<T> data, int stride)
        where T : struct
    {
        // Do we already have a compute buffer?
        if (buffer != null) {
            // If no data or buffer doesn't match the given criteria, release it
            if (data.Count == 0 || buffer.count != data.Count || buffer.stride != stride) {
                buffer.Release();
                buffer = null;
            }
        }

        if (data.Count != 0) {
            // If the buffer has been released or wasn't there to
            // begin with, create it
            if (buffer == null) {
                buffer = new ComputeBuffer(data.Count, stride);
            }
            // Set data on the buffer
            buffer.SetData(data);
        }
    }
    private void CreateComputeBuffer<T>(ref ComputeBuffer buffer, T[] data, int stride)
        where T : struct
    {
        // Do we already have a compute buffer?
        if (buffer != null) {
            // If no data or buffer doesn't match the given criteria, release it
            if (data.Length == 0 || buffer.count != data.Length || buffer.stride != stride) {
                buffer.Release();
                buffer = null;
            }
        }

        if (data.Length != 0) {
            // If the buffer has been released or wasn't there to
            // begin with, create it
            if (buffer == null) {
                buffer = new ComputeBuffer(data.Length, stride);
            }
            // Set data on the buffer
            buffer.SetData(data);
        }
    }

    private void SetComputeBuffer(int kernel, string name, ComputeBuffer buffer) {
        if (buffer != null) RayTracingShader.SetBuffer(kernel, name, buffer);
    }

    private void SetShaderParameters() {
        BufferSizes = new BufferSizeData[bouncecount];
        BufferSizes[0].tracerays = SourceWidth * SourceHeight;
        _BufferSizes.SetData(BufferSizes);
        RayTracingShader.SetMatrix("_CameraToWorld", _camera.cameraToWorldMatrix);
        RayTracingShader.SetMatrix("_CameraInverseProjection", _camera.projectionMatrix.inverse);
        
        RayTracingShader.SetVector("Up", _camera.transform.up);
        RayTracingShader.SetVector("Right", _camera.transform.right);
        RayTracingShader.SetVector("Forward", _camera.transform.forward);

        RayTracingShader.SetVector("camPos", _camera.transform.position);
        Matrix4x4 viewprojmatrix = _camera.projectionMatrix * _camera.worldToCameraMatrix;
        var PrevMatrix = PrevViewProjection;
        RayTracingShader.SetMatrix("viewprojection", viewprojmatrix);
        RayTracingShader.SetMatrix("prevviewprojection", PrevMatrix);
        PrevViewProjection = viewprojmatrix;

        RayTracingShader.SetFloat("VolumeDensity", VolumeDensity * VolumeDensity);

        RayTracingShader.SetMatrix("ViewMatrix", _camera.worldToCameraMatrix);
        RayTracingShader.SetMatrix("InverseViewMatrix", _camera.worldToCameraMatrix.inverse);
        RayTracingShader.SetInt("MaxBounce", bouncecount - 1);
        RayTracingShader.SetInt("frames_accumulated", _currentSample);
        RayTracingShader.SetInt("VoxelOffset", Assets.VoxOffset);
        SetComputeBuffer(GenKernel, "BufferSizes", _BufferSizes);
        SetComputeBuffer(TraceKernel, "BufferSizes", _BufferSizes);
        SetComputeBuffer(ShadowKernel, "BufferSizes", _BufferSizes); 
        SetComputeBuffer(ShadeKernel, "BufferSizes", _BufferSizes);  
        SetComputeBuffer(OctreeKernel, "BufferSizes", _BufferSizes);
        SetComputeBuffer(OctreeShadowKernel, "BufferSizes", _BufferSizes);
        RayTracingShader.SetBool("UseRussianRoulette", UseRussianRoulette);  
        RayTracingShader.SetBool("UseNEE", UseNEE);  
        RayTracingShader.SetBool("DoVoxels", Assets.UseVoxels);  
        RayTracingShader.SetBool("AllowVolumetrics", AllowVolumetrics); 
        RayTracingShader.SetBool("UseDoF", AllowDoF); 
        RayTracingShader.SetFloat("VolumeDensity", VolumeDensity * VolumeDensity);
        RayTracingShader.SetFloat("focal_distance", DoFFocal);
        RayTracingShader.SetFloat("AperatureRadius", DoFAperature);
        if(uFirstFrame == 1) {
            if(SkyboxTexture != null) {
                RayTracingShader.SetTexture(ShadeKernel, "_SkyboxTexture", SkyboxTexture);
            }
            SetComputeBuffer(OctreeKernel, "VoxelTLAS", _VoxelTLAS); 
            SetComputeBuffer(OctreeShadowKernel, "VoxelTLAS", _VoxelTLAS); 
            SetComputeBuffer(OctreeKernel, "Octree", _OctreeBuffer); 
            SetComputeBuffer(OctreeShadowKernel, "Octree", _OctreeBuffer); 
            SetComputeBuffer(ShadeKernel, "Octree", _OctreeBuffer); 
            RayTracingShader.SetInt("LightMeshCount", Assets.LightMeshCount);
            RayTracingShader.SetInt("unitylightcount", Assets.UnityLightCount);
            RayTracingShader.SetTexture(ShadeKernel, "_TextureAtlas", Assets.AlbedoAtlas);
            RayTracingShader.SetTexture(ShadeKernel, "_EmissiveAtlas", Assets.EmissiveAtlas);
            RayTracingShader.SetTexture(ShadeKernel, "_NormalAtlas", Assets.NormalAtlas);
            RayTracingShader.SetTexture(ShadeKernel, "_MetallicAtlas", Assets.MetallicAtlas);
            RayTracingShader.SetTexture(ShadeKernel, "_RoughnessAtlas", Assets.RoughnessAtlas);
            RayTracingShader.SetInt("lighttricount", Assets.LightTriCount);
            RayTracingShader.SetInt("screen_width", SourceWidth);
            RayTracingShader.SetInt("screen_height", SourceHeight);

            SetComputeBuffer(ReservoirKernel, "CurrentReservoir", _CurrentReservoir);
            SetComputeBuffer(ReservoirKernel, "PreviousReservoir", _PreviousReservoir);
            SetComputeBuffer(ShadeKernel, "CurrentReservoir", _CurrentReservoir);
            SetComputeBuffer(ShadeKernel, "PreviousReservoir", _PreviousReservoir);

            SetComputeBuffer(ShadeKernel, "_LightMeshes", _LightMeshes);
            SetComputeBuffer(ReservoirKernel, "_LightMeshes", _LightMeshes);
            SetComputeBuffer(ShadeKernel, "_Materials", _MaterialDataBuffer); 
            SetComputeBuffer(GenKernel, "GlobalRays1", _RayBuffer1);
            SetComputeBuffer(TraceKernel, "GlobalRays1", _RayBuffer1);
            SetComputeBuffer(ShadeKernel, "GlobalRays1", _RayBuffer1);

            SetComputeBuffer(ShadeKernel, "LightTriangles", _LightTriangles);  
            SetComputeBuffer(ReservoirKernel, "LightTriangles", _LightTriangles);  
            SetComputeBuffer(ReservoirSpatialKernel, "LightTriangles", _LightTriangles);  

            SetComputeBuffer(ShadowKernel, "ShadowRaysBuffer", _ShadowBuffer);
            SetComputeBuffer(ShadeKernel, "ShadowRaysBuffer", _ShadowBuffer);
            SetComputeBuffer(OctreeShadowKernel, "ShadowRaysBuffer", _ShadowBuffer);
            SetComputeBuffer(ReservoirCopyKernel, "ShadowRaysBuffer", _ShadowBuffer);

            SetComputeBuffer(GenKernel, "GlobalRays2", _RayBuffer2);
            SetComputeBuffer(TraceKernel, "GlobalRays2", _RayBuffer2);
            SetComputeBuffer(ShadeKernel, "GlobalRays2", _RayBuffer2);
            SetComputeBuffer(OctreeKernel, "GlobalRays2", _RayBuffer2);

            SetComputeBuffer(GenKernel, "GlobalColors", _ColorBuffer);
            SetComputeBuffer(OctreeShadowKernel, "GlobalColors", _ColorBuffer);
            SetComputeBuffer(ShadeKernel, "GlobalColors", _ColorBuffer);

            SetComputeBuffer(TraceKernel, "AggTris", Assets.AggTriBuffer);
            SetComputeBuffer(ShadowKernel, "AggTris", Assets.AggTriBuffer);
            SetComputeBuffer(ShadeKernel, "AggTris", Assets.AggTriBuffer);

            SetComputeBuffer(TraceKernel, "cwbvh_nodes", Assets.BVH8AggregatedBuffer);
            SetComputeBuffer(ShadowKernel, "cwbvh_nodes", Assets.BVH8AggregatedBuffer);
            
            SetComputeBuffer(ShadowKernel, "_MeshData", _CompactedMeshData);
            SetComputeBuffer(TraceKernel, "_MeshData", _CompactedMeshData);
            SetComputeBuffer(ShadeKernel, "_MeshData", _CompactedMeshData);
            SetComputeBuffer(OctreeKernel, "_MeshData", _CompactedMeshData);
            SetComputeBuffer(OctreeShadowKernel, "_MeshData", _CompactedMeshData);

            SetComputeBuffer(ShadeKernel, "_UnityLights", _UnityLights);
            SetComputeBuffer(ReservoirKernel, "_UnityLights", _UnityLights);
            SetComputeBuffer(ReservoirSpatialKernel, "_UnityLights", _UnityLights);

            RayTracingShader.SetFloat("sun_angular_radius", 0.05f);
            RayTracingShader.SetTexture(ShadeKernel, "ScatterTex", Atmo._RayleighTex);
            RayTracingShader.SetTexture(ShadeKernel, "MieTex", Atmo._MieTex);
        }

    }

    private void CreateRenderTexture(ref RenderTexture ThisTex, bool SRGB, bool Res) {
        if(SRGB) {
        ThisTex = new RenderTexture((Res) ? TargetWidth : SourceWidth, (Res) ? TargetHeight : SourceHeight, 0,
            RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.sRGB);
        } else {
        ThisTex = new RenderTexture((Res) ? TargetWidth : SourceWidth, (Res) ? TargetHeight : SourceHeight, 0,
            RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        }
        ThisTex.enableRandomWrite = true;
        ThisTex.Create();
    }
    private void CreateRenderTexture(ref RenderTexture ThisTex, bool SRGB, bool istarget, bool Res) {
        if(SRGB) {
        ThisTex = new RenderTexture((Res) ? TargetWidth : SourceWidth, (Res) ? TargetHeight : SourceHeight, 0,
            RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.sRGB);
        } else {
        ThisTex = new RenderTexture((Res) ? TargetWidth : SourceWidth, (Res) ? TargetHeight : SourceHeight, 0,
            RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        }
        if(istarget) {
            ThisTex.useMipMap = true;
            ThisTex.autoGenerateMips = false;
        }
        ThisTex.enableRandomWrite = true;
        ThisTex.Create();
    }

    private void InitRenderTexture() {
        if (_target == null || _target.width != SourceWidth || _target.height != SourceHeight) {
            // Release render texture if we already have one
            if (_target != null) {
                _target.Release();
                _converged.Release();
                _PosTex.Release();
                _Albedo.Release();
                _NormTex.Release();
                _IntermediateTex.Release();
                _DebugTex.Release();
            }

         CreateRenderTexture(ref _DebugTex, true, false);
         CreateRenderTexture(ref _FinalTex, true, true);
         CreateRenderTexture(ref _IntermediateTex, true, true, false);
         CreateRenderTexture(ref _target, true, false);
         CreateRenderTexture(ref _NormTex, false, false);
         CreateRenderTexture(ref _converged, true, false);
         CreateRenderTexture(ref _PosTex, false, false);
         CreateRenderTexture(ref _Albedo, true, false);
            // Reset sampling
            _currentSample = 0;
        }
    }
 public void ClearOutRenderTexture(RenderTexture renderTexture)
     {
         RenderTexture rt = RenderTexture.active;
         RenderTexture.active = renderTexture;
         GL.Clear(true, true, Color.clear);
         RenderTexture.active = rt;
     }
    private void Render(RenderTexture destination) {
        float CurrentSample;
        InitRenderTexture();      
        RayTracingShader.SetInt("curframe", FramesSinceStart2); 
        RayTracingShader.SetTexture(ShadeKernel, "TempPosTex", _PosTex);
        RayTracingShader.SetTexture(ShadeKernel, "TempNormTex", _NormTex);
        RayTracingShader.SetTexture(ShadeKernel, "TempAlbedoTex", _Albedo);
        RayTracingShader.SetTexture(OctreeKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(ShadeKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(TraceKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(OctreeShadowKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(ReservoirKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(ReservoirSpatialKernel, "_DebugTex", _DebugTex);
        RayTracingShader.SetTexture(ReservoirCopyKernel, "_DebugTex", _DebugTex);
        RayTracingShader.Dispatch(GenKernel, threadGroupsX, threadGroupsY, 1);
        SetComputeBuffer(ShadeKernel, "CurrentReservoir", _CurrentReservoir);
        SetComputeBuffer(ShadeKernel, "PreviousReservoir", _PreviousReservoir);
        SetComputeBuffer(ShadowKernel, "CurrentReservoir", _CurrentReservoir);
        SetComputeBuffer(ShadowKernel, "PreviousReservoir", _PreviousReservoir);

        SetComputeBuffer(OctreeShadowKernel, "PreviousReservoir", _PreviousReservoir);
        for(int i = 0; i < bouncecount; i++) {
            var bouncebounce = i;
            RayTracingShader.SetInt("CurBounce", bouncebounce);
            RayTracingShader.Dispatch(TraceKernel, 768, 1, 1);
            if(Assets.UseVoxels) RayTracingShader.Dispatch(OctreeKernel, 768, 1, 1);
            RayTracingShader.Dispatch(ShadeKernel, threadGroupsX2, threadGroupsY2, 1);
            if(UseNEE || AllowVolumetrics) RayTracingShader.Dispatch(ShadowKernel, 768, 1, 1);
            if(UseNEE || AllowVolumetrics) RayTracingShader.Dispatch(OctreeShadowKernel, 768, 1, 1);

        }
        
 UnityEngine.Profiling.Profiler.BeginSample("ReSTIR Reproject");
         SetComputeBuffer(ReservoirKernel, "CurrentReservoir", _CurrentReservoir);
         SetComputeBuffer(ReservoirKernel, "PreviousReservoir", _PreviousReservoir);
         SetComputeBuffer(ReservoirKernel, "_LightMeshes", _LightMeshes);

         RayTracingShader.SetTexture(ReservoirKernel, "TempAlbedoTex", _Albedo);
         RayTracingShader.SetTexture(ReservoirKernel, "TempNormTex", _NormTex);
         RayTracingShader.SetTexture(ReservoirKernel, "TempPosTex", _PosTex);
         if(UseNEE || AllowVolumetrics)RayTracingShader.Dispatch(ReservoirKernel, Mathf.CeilToInt(SourceWidth / 3.0f), Mathf.CeilToInt(SourceWidth / 3.0f), 1);
         UnityEngine.Profiling.Profiler.EndSample();
        
         SetComputeBuffer(ReservoirSpatialKernel, "CurrentReservoir", _CurrentReservoir);
         SetComputeBuffer(ReservoirSpatialKernel, "PreviousReservoir", _PreviousReservoir);
         UnityEngine.Profiling.Profiler.BeginSample("ReSTIR Spatial");
         RayTracingShader.SetTexture(ReservoirSpatialKernel, "TempAlbedoTex", _Albedo);
         RayTracingShader.SetTexture(ReservoirSpatialKernel, "TempNormTex", _NormTex);
         RayTracingShader.SetTexture(ReservoirSpatialKernel, "TempPosTex", _PosTex);
         if(UseNEE || AllowVolumetrics)RayTracingShader.Dispatch(ReservoirSpatialKernel, threadGroupsX3, threadGroupsY3, 1);
         UnityEngine.Profiling.Profiler.EndSample();


        SetComputeBuffer(ReservoirCopyKernel, "CurrentReservoir", _CurrentReservoir);
        SetComputeBuffer(ReservoirCopyKernel, "PreviousReservoir", _PreviousReservoir);
        RayTracingShader.Dispatch(ReservoirCopyKernel, threadGroupsX3, threadGroupsY3, 1);
        //I could try to optimize it by using a structured buffer that contains normals, colors, and positions, making it float3, float3, float2(compressed normal) to conserve a single float
        if(!UseSVGF) {
            RayTracingShader.SetTexture(FinalizeKernel, "Result", _target);
            RayTracingShader.SetTexture(FinalizeKernel, "TempAlbedoTex", _Albedo);
            RayTracingShader.SetBuffer(FinalizeKernel, "GlobalColors", _ColorBuffer);
            RayTracingShader.Dispatch(FinalizeKernel, Mathf.CeilToInt(SourceWidth / 16.0f), Mathf.CeilToInt(SourceHeight / 16.0f), 1);
            CurrentSample = 1.0f / (FramesSinceStart + 1.0f);
            SampleCount++;
        } else {
            SampleCount = 0;
            Denoisers.ExecuteSVGF(_currentSample, SVGFAtrousKernelSizes, ref _ColorBuffer, ref _PosTex, ref _target, ref _Albedo, ref _NormTex);
            CurrentSample = 1;
        }




        if (_addMaterial == null)
            _addMaterial = new Material(Shader.Find("Hidden/Accumulate"));
        _addMaterial.SetFloat("_Sample", CurrentSample);
        Graphics.Blit(_target, _converged, _addMaterial);
        Graphics.CopyTexture(_converged, 0, 0, _IntermediateTex, 0, 0);
        _IntermediateTex.GenerateMips();
        if(UseAtrous) {
            Denoisers.ExecuteAtrous(AtrousKernelSizes, n_phiGlob, p_phiGlob, c_phiGlob, ref _PosTex, ref _target, ref _Albedo, ref _IntermediateTex, ref _NormTex);
            Graphics.CopyTexture(_target, 0, 0, _IntermediateTex, 0, 0);
        }
        if(AllowAutoExpose) {
            Denoisers.ExecuteAutoExpose(ref _target, ref _IntermediateTex);
            Graphics.CopyTexture(_target, 0, 0, _IntermediateTex, 0, 0);
        }
        if(AllowBloom) {
            Denoisers.ExecuteBloom(ref _target, ref _IntermediateTex);
            Graphics.CopyTexture(_target, 0, 0, _IntermediateTex, 0, 0);
        }
        if(_IntermediateTex.width == _FinalTex.width) Graphics.CopyTexture(_IntermediateTex, 0, 0, _FinalTex, 0, 0);
        if(AllowTAA || (SourceHeight != TargetHeight)) {
            Graphics.CopyTexture(_IntermediateTex, 0, 0, _target, 0, 0);
            Denoisers.ExecuteTAA(ref _target, ref _IntermediateTex, ref _PosTex, ref _FinalTex, _currentSample);
        }

        Graphics.Blit(_FinalTex, destination);
        ClearOutRenderTexture(_DebugTex);
        _currentSample++; 
        FramesSinceStart++;  
        FramesSinceStart2++;
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        if(Assets.RenderQue.Count > 0) {
            RebuildMeshObjectBuffers();
            SetShaderParameters();
            Render(destination);
            uFirstFrame = 0;
        } else {
            try {bool throwawayBool = Assets.UpdateTLAS();} catch(System.IndexOutOfRangeException){}
        }
    }

}