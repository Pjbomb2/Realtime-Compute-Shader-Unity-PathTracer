using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using CommonVars;
using System.Threading.Tasks;
using System.Threading;

[System.Serializable]
public class AssetManager : MonoBehaviour {
    public Texture2D AlbedoAtlas;
    public Texture2D NormalAtlas;
    public Texture2D EmissiveAtlas;
    public Texture2D MetallicAtlas;
    public Texture2D RoughnessAtlas;


    public List<MaterialData> _Materials;
    [HideInInspector] public ComputeBuffer BVH8AggregatedBuffer;
    [HideInInspector] public ComputeBuffer AggTriBuffer;
    public List<BVHNode8DataCompressed> VoxelTLAS;
    public List<MyMeshDataCompacted> MyMeshesCompacted;
     public List<CudaLightTriangle> AggLightTriangles;
    [HideInInspector] public List<LightData> UnityLights;
    public List<Light> Lights;

    public ComputeShader MeshFunctions;
    private int TriangleBufferKernel;
    private int NodeBufferKernel;

    public List<ParentObject> RenderQue;
    public List<ParentObject> BuildQue;
    public List<ParentObject> AddQue;
    public List<ParentObject> RemoveQue;
    public List<VoxelObject> VoxelBuildQue;
    public List<VoxelObject> VoxelRenderQue;
    public List<VoxelObject> VoxelAddQue;
    public List<VoxelObject> VoxelRemoveQue;

    [HideInInspector] public List<Transform> LightTransforms;
    [HideInInspector] public List<Task> CurrentlyActiveTasks;
    [HideInInspector] public List<Task> CurrentlyActiveVoxelTasks;

    public List<LightMeshData> LightMeshes;

    [HideInInspector] public AABB[] MeshAABBs;
    [HideInInspector] public AABB[] VoxelAABBs;

    [HideInInspector] public bool ParentCountHasChanged;    
    
    [HideInInspector] public int TLASSpace;
    [HideInInspector] public int LightTriCount;
    [HideInInspector] public int LightMeshCount;
    [HideInInspector] public int UnityLightCount;
    public List<GPUOctreeNode> GPUOctree;
    public int VoxOffset;
    private int PrevLightCount;

    [HideInInspector] public BVH2Builder BVH2;

    [HideInInspector] public bool UseSkinning = true;
    [HideInInspector] public bool HasStart = false;
    [HideInInspector] public bool didstart = false;
    public bool UseVoxels;
    public bool ChildrenUpdated;

    public void ClearAll() {//My attempt at clearing memory
        ParentObject[] ChildrenObjects = this.GetComponentsInChildren<ParentObject>();
        foreach(ParentObject obj in ChildrenObjects)
            obj.ClearAll();
        if(_Materials != null) {
            _Materials.Clear();
            _Materials.TrimExcess();
        }
        if(LightTransforms != null) {
            LightTransforms.Clear();
            LightTransforms.TrimExcess();
        }
        if(LightMeshes != null) {
            LightMeshes.Clear();
            LightMeshes.TrimExcess();
        }
        if(MyMeshesCompacted != null) {
            MyMeshesCompacted.Clear();
            MyMeshesCompacted.TrimExcess();
        }
        if(AggLightTriangles != null) {
            AggLightTriangles.Clear();
            AggLightTriangles.TrimExcess();
        }
        if(UnityLights != null) {
            UnityLights.Clear();
            UnityLights.TrimExcess();
        }
        DestroyImmediate(AlbedoAtlas);
        DestroyImmediate(NormalAtlas);
        DestroyImmediate(EmissiveAtlas);  
        if(BVH8AggregatedBuffer != null) {
            BVH8AggregatedBuffer.Release();
            BVH8AggregatedBuffer = null;    
            AggTriBuffer.Release();
            AggTriBuffer = null;    
        }

        Resources.UnloadUnusedAssets();
        System.GC.Collect();
    }



    private Vector4 ResizeRect(Vector4 In, Rect InRect) {
        Vector2 Difference = new Vector2(InRect.xMax - InRect.xMin, InRect.yMax - InRect.yMin);
        Vector2 Max = new Vector2(In.x, In.y) * Difference + new Vector2(InRect.xMin, InRect.yMin);
        Vector2 Min = new Vector2(In.z, In.w) * Difference + new Vector2(InRect.xMin, InRect.yMin);
        return new Vector4(Max.x, Max.y, Min.x, Min.y);
    }
   private void CreateAtlas() {//Creates texture atlas

        _Materials = new List<MaterialData>();
        List<Texture2D> AlbedoTexs = new List<Texture2D>();
        List<Texture2D> NormalTexs = new List<Texture2D>();
        List<Texture2D> EmissiveTexs = new List<Texture2D>();
        List<Texture2D> MetallicTexs = new List<Texture2D>();
        List<Texture2D> RoughnessTexs = new List<Texture2D>();
        AlbedoAtlas = new Texture2D(1,1);
        NormalAtlas = new Texture2D(1, 1);
        EmissiveAtlas = new Texture2D(1, 1);
        MetallicAtlas = new Texture2D(1, 1);
        RoughnessAtlas = new Texture2D(1, 1);
        int AlbedoCount, NormalCount, EmissiveCount, MetallicCount, RoughnessCount = 0;
        foreach(ParentObject Obj in RenderQue) {
            if(Obj.HasAlbedoAtlas) {
                AlbedoTexs.Add((Texture2D)Obj.AlbedoAtlas);
            }
            if(Obj.HasNormalAtlas) {
                NormalTexs.Add((Texture2D)Obj.NormalAtlas);
            }
            if(Obj.HasEmissiveAtlas) {
                EmissiveTexs.Add((Texture2D)Obj.EmissiveAtlas);
            }
            if(Obj.HasMetallicAtlas) {
                MetallicTexs.Add((Texture2D)Obj.MetallicAtlas);
            }
            if(Obj.HasRoughnessAtlas) {
                RoughnessTexs.Add((Texture2D)Obj.RoughnessAtlas);
            }
        }
        Rect[] AlbedoRects, NormalRects, EmmissiveRects, MetallicRects, RoughnessRects;
        if(AlbedoTexs.Count != 0) {
            AlbedoRects = AlbedoAtlas.PackTextures(AlbedoTexs.ToArray(), 1, Mathf.Min((int)Mathf.Ceil(Mathf.Sqrt(RenderQue.Count)) * RenderQue[0].AtlasSize, 16392));//4096);
        } else {
            AlbedoRects = new Rect[0];
        }
        if(NormalTexs.Count != 0) {
            NormalRects = NormalAtlas.PackTextures(NormalTexs.ToArray(), 1, Mathf.Min((int)Mathf.Ceil(Mathf.Sqrt(RenderQue.Count)) * RenderQue[0].AtlasSize, 16392));//4096);
        } else {
            NormalRects = new Rect[0];
        }
        if(EmissiveTexs.Count != 0) {
            EmmissiveRects = EmissiveAtlas.PackTextures(EmissiveTexs.ToArray(), 1, Mathf.Min((int)Mathf.Ceil(Mathf.Sqrt(RenderQue.Count)) * RenderQue[0].AtlasSize, 16392));//4096);
        } else {
            EmmissiveRects = new Rect[0];
        }
        if(MetallicTexs.Count != 0) {
            MetallicRects = MetallicAtlas.PackTextures(MetallicTexs.ToArray(), 1, Mathf.Min((int)Mathf.Ceil(Mathf.Sqrt(RenderQue.Count)) * RenderQue[0].AtlasSize, 16392));//4096);
        } else {
            MetallicRects = new Rect[0];
        }
        if(RoughnessTexs.Count != 0) {
            RoughnessRects = RoughnessAtlas.PackTextures(RoughnessTexs.ToArray(), 1, Mathf.Min((int)Mathf.Ceil(Mathf.Sqrt(RenderQue.Count)) * RenderQue[0].AtlasSize, 16392));//4096);
        } else {
            RoughnessRects = new Rect[0];
        }
        AlbedoCount = NormalCount = EmissiveCount = MetallicCount = RoughnessCount =  0;
         int MatCount = 0;
        foreach(ParentObject Obj in RenderQue) {
            foreach(RayTracingObject Obj2 in Obj.ChildObjects) {
                for(int i = 0; i < Obj2.MaterialIndex.Length; i++) {
                    Obj2.MaterialIndex[i] = Obj2.LocalMaterialIndex[i] + MatCount;
                }
            }
            foreach(MaterialData Mat in Obj._Materials) {
                MaterialData TempMat = Mat;
                if(TempMat.MatType == 1) {
                    TempMat.Roughness = Mathf.Max(TempMat.Roughness, 0.000001f);
                }
                if(TempMat.HasAlbedoTex == 1) {
                    TempMat.AlbedoTex = ResizeRect(TempMat.AlbedoTex, AlbedoRects[AlbedoCount]);
                }
                if(TempMat.HasNormalTex == 1) {
                    TempMat.NormalTex = ResizeRect(TempMat.NormalTex, NormalRects[NormalCount]);
                }
                if(TempMat.HasEmissiveTex == 1) {
                    TempMat.EmissiveTex = ResizeRect(TempMat.EmissiveTex, EmmissiveRects[EmissiveCount]);
                }
                if(TempMat.HasMetallicTex == 1) {
                    TempMat.MetallicTex = ResizeRect(TempMat.MetallicTex, MetallicRects[MetallicCount]);
                }
                if(TempMat.HasRoughnessTex == 1) {
                    TempMat.RoughnessTex = ResizeRect(TempMat.RoughnessTex, RoughnessRects[RoughnessCount]);
                }
                _Materials.Add(TempMat);
                MatCount++;
            }
            if(Obj.HasAlbedoAtlas) AlbedoCount++;
            if(Obj.HasNormalAtlas) NormalCount++;
            if(Obj.HasEmissiveAtlas) EmissiveCount++;
            if(Obj.HasMetallicAtlas) MetallicCount++;
            if(Obj.HasRoughnessAtlas) RoughnessCount++;

        }
        AlbedoTexs.Clear();
        AlbedoTexs.TrimExcess();
        NormalTexs.Clear();
        NormalTexs.TrimExcess();
        EmissiveTexs.Clear();
        EmissiveTexs.TrimExcess(); 
        MetallicTexs.Clear();
        MetallicTexs.TrimExcess(); 
        RoughnessTexs.Clear();
        RoughnessTexs.TrimExcess(); 
        foreach(VoxelObject Vox in VoxelRenderQue) {
            foreach(MaterialData Mat in Vox._Materials) {
                _Materials.Add(Mat);
            }
        } 

    }


    private void init() {
        AddQue = new List<ParentObject>();
        RemoveQue = new List<ParentObject>();
        RenderQue = new List<ParentObject>();
        VoxelAddQue = new List<VoxelObject>();
        VoxelRemoveQue = new List<VoxelObject>();
        VoxelRenderQue = new List<VoxelObject>();
        VoxelBuildQue = new List<VoxelObject>();
        CurrentlyActiveTasks = new List<Task>();
        CurrentlyActiveVoxelTasks = new List<Task>();
        BuildQue = new List<ParentObject>();
        MyMeshesCompacted = new List<MyMeshDataCompacted>();
        AggLightTriangles = new List<CudaLightTriangle>();
        CurrentlyActiveTasks = new List<Task>();
        UnityLights = new List<LightData>();
        LightMeshes = new List<LightMeshData>();
        LightTransforms = new List<Transform>();
        Lights = new List<Light>();
        LightMeshCount = 0;
        UnityLightCount = 0;
        LightTriCount = 0;
        if(BVH8AggregatedBuffer != null) {
            BVH8AggregatedBuffer.Release();
            BVH8AggregatedBuffer = null;    
            AggTriBuffer.Release();
            AggTriBuffer = null;    
        }
        MeshFunctions = Resources.Load<ComputeShader>("Utility/GeneralMeshFunctions");
        TriangleBufferKernel = MeshFunctions.FindKernel("CombineTriBuffers");
        NodeBufferKernel = MeshFunctions.FindKernel("CombineNodeBuffers");
    }

    private void UpdateRenderAndBuildQues() {
        ChildrenUpdated = false;

        int AddQueCount = AddQue.Count - 1;
        int RemoveQueCount = RemoveQue.Count - 1;
        for(int i = AddQueCount; i >= 0; i--) {
            var CurrentRep = BuildQue.Count;
            BuildQue.Add(AddQue[i]);
            AddQue.RemoveAt(i);
            BuildQue[CurrentRep].LoadData();
            CurrentlyActiveTasks.Add(Task.Run(() => BuildQue[CurrentRep].BuildTotal()));
            ChildrenUpdated = true;
        }
        for(int i = RemoveQueCount; i >= 0; i--) {
            if(RenderQue.Contains(RemoveQue[i]))
                RenderQue.Remove(RemoveQue[i]);
            else if(BuildQue.Contains(RemoveQue[i])) {
                CurrentlyActiveTasks.RemoveAt(BuildQue.IndexOf(RemoveQue[i]));
                BuildQue.Remove(RemoveQue[i]);
            } else
                Debug.Log("REMOVE QUE NOT FOUND");
            ChildrenUpdated = true;
            RemoveQue.RemoveAt(i); 
        }
        int RenderQueCount = RenderQue.Count - 1;
        for(int i = RenderQueCount; i >= 0; i--) {//Demotes from Render Que to Build Que in case mesh has changed
            if(RenderQue[i].NeedsToUpdate) {
                RenderQue[i].ClearAll();
                RenderQue[i].LoadData();
                BuildQue.Add(RenderQue[i]);
                RenderQue.RemoveAt(i);
                var TempBuildQueCount = BuildQue.Count - 1;
                CurrentlyActiveTasks.Add(Task.Run(() => BuildQue[TempBuildQueCount].BuildTotal()));
                ChildrenUpdated = true;
            }
        }
        int BuildQueCount = BuildQue.Count - 1;
        for(int i = BuildQueCount; i >= 0; i--) {//Promotes from Build Que to Render Que
            if(CurrentlyActiveTasks[i].IsFaulted) Debug.Log(CurrentlyActiveTasks[i].Exception);//Fuck, something fucked up
            if(CurrentlyActiveTasks[i].Status == TaskStatus.RanToCompletion) {
                BuildQue[i].SetUpBuffers();
                RenderQue.Add(BuildQue[i]);
                BuildQue.RemoveAt(i);
                CurrentlyActiveTasks.RemoveAt(i);
                ChildrenUpdated = true;
            }
        }

        AddQueCount = VoxelAddQue.Count - 1;
        RemoveQueCount = VoxelRemoveQue.Count - 1;
        for(int i = AddQueCount; i >= 0; i--) {
            var CurrentRep = VoxelBuildQue.Count;
            VoxelBuildQue.Add(VoxelAddQue[i]);
            VoxelAddQue.RemoveAt(i);
            VoxelBuildQue[CurrentRep].LoadData();
            CurrentlyActiveVoxelTasks.Add(Task.Run(() => VoxelBuildQue[CurrentRep].BuildOctree()));
            ChildrenUpdated = true;
        }
        for(int i = RemoveQueCount; i >= 0; i--) {
            if(VoxelRenderQue.Contains(VoxelRemoveQue[i]))
                VoxelRenderQue.Remove(VoxelRemoveQue[i]);
            else if(VoxelBuildQue.Contains(VoxelRemoveQue[i])) {
                CurrentlyActiveVoxelTasks.RemoveAt(VoxelBuildQue.IndexOf(VoxelRemoveQue[i]));
                VoxelBuildQue.Remove(VoxelRemoveQue[i]);
            } else
                Debug.Log("REMOVE QUE NOT FOUND");
            ChildrenUpdated = true;
            VoxelRemoveQue.RemoveAt(i); 
        }



        BuildQueCount = VoxelBuildQue.Count - 1;
        for(int i = BuildQueCount; i >= 0; i--) {//Promotes from Build Que to Render Que
            if(CurrentlyActiveVoxelTasks[i].IsFaulted) Debug.Log(CurrentlyActiveVoxelTasks[i].Exception);//Fuck, something fucked up
            if(CurrentlyActiveVoxelTasks[i].Status == TaskStatus.RanToCompletion) {
                VoxelRenderQue.Add(VoxelBuildQue[i]);
                VoxelBuildQue.RemoveAt(i);
                CurrentlyActiveVoxelTasks.RemoveAt(i);
                ChildrenUpdated = true;
            }
        }
        if(ChildrenUpdated || ParentCountHasChanged) MeshAABBs = new AABB[RenderQue.Count];
        if(ChildrenUpdated || ParentCountHasChanged) VoxelAABBs = new AABB[VoxelRenderQue.Count];
    }
    public void EditorBuild() {
        ClearAll();
        init();
        AddQue = new List<ParentObject>();
        RemoveQue = new List<ParentObject>();
        RenderQue = new List<ParentObject>();
        CurrentlyActiveTasks = new List<Task>();
        CurrentlyActiveVoxelTasks = new List<Task>();
        BuildQue = new List<ParentObject>(GetComponentsInChildren<ParentObject>());
        VoxelBuildQue = new List<VoxelObject>(GetComponentsInChildren<VoxelObject>());
        for(int i = 0; i < BuildQue.Count; i++) {
            var CurrentRep = i;
            BuildQue[CurrentRep].LoadData();
            Task t1 = Task.Run(() => BuildQue[CurrentRep].BuildTotal());
            CurrentlyActiveTasks.Add(t1);
        }
        for(int i = 0; i < VoxelBuildQue.Count; i++) {
            var CurrentRep = i;
            VoxelBuildQue[CurrentRep].LoadData();
            Task t1 = Task.Run(() => VoxelBuildQue[CurrentRep].BuildOctree());
            CurrentlyActiveVoxelTasks.Add(t1);
        }
        if(AggLightTriangles.Count == 0) {AggLightTriangles.Add(new CudaLightTriangle() {});}
        didstart = false;
    }
    int Counter;
    public void BuildCombined() {
        Counter = 0;
        HasToDo = false;
        init();
        CurrentlyActiveVoxelTasks = new List<Task>();
        List<ParentObject> TempQue = new List<ParentObject>(GetComponentsInChildren<ParentObject>());
        List<VoxelObject> TempVoxelQue = new List<VoxelObject>(GetComponentsInChildren<VoxelObject>());
        for(int i = 0; i < TempQue.Count; i++) {
            if(TempQue[i].HasCompleted && !TempQue[i].NeedsToUpdate)
                RenderQue.Add(TempQue[i]);
            else
                BuildQue.Add(TempQue[i]);
        }
        for(int i = 0; i < TempVoxelQue.Count; i++) {
            if(TempVoxelQue[i].HasCompleted)
                VoxelRenderQue.Add(TempVoxelQue[i]);
            else
                VoxelBuildQue.Add(TempVoxelQue[i]);
        }
        for(int i = 0; i < BuildQue.Count; i++) {
            var CurrentRep = i;
            BuildQue[CurrentRep].LoadData();
            CurrentlyActiveTasks.Add(Task.Run(() => BuildQue[CurrentRep].BuildTotal()));
        }
        for(int i = 0; i < VoxelBuildQue.Count; i++) {
            var CurrentRep = i;
            VoxelBuildQue[CurrentRep].LoadData();
            CurrentlyActiveVoxelTasks.Add(Task.Run(() => VoxelBuildQue[CurrentRep].BuildOctree()));
        }
        MeshAABBs = new AABB[RenderQue.Count];
        VoxelAABBs = new AABB[VoxelRenderQue.Count];
        ParentCountHasChanged = true;
        if(AggLightTriangles.Count == 0) {AggLightTriangles.Add(new CudaLightTriangle() {});}
        if(RenderQue.Count != 0) {bool throwaway = UpdateTLAS();}
    }
    public bool HasToDo;

    private void TempBuild() {
        UpdateRenderAndBuildQues();
        int ParentsLength = RenderQue.Count;
        TLASSpace = 2 * ParentsLength;
        int nodes = TLASSpace;
        int BVHOffset = 0;
        int MaterialOffset = 0;
        if(ChildrenUpdated || ParentCountHasChanged) {
            HasToDo = false;
            int CurNodeOffset = TLASSpace;
            int CurTriOffset = 0;
            LightMeshCount = 0;
            LightMeshes.Clear();
            AggLightTriangles.Clear();
            LightTransforms.Clear();
            float TotalEnergy = 0;
            int AggTriCount = 0;
            int AggNodeCount = TLASSpace;
            if(BVH8AggregatedBuffer != null) {
                BVH8AggregatedBuffer.Release();    
                AggTriBuffer.Release();  
            }
            for(int i = 0; i < ParentsLength; i++) {
                AggNodeCount += RenderQue[i].AggNodes.Length;
                AggTriCount += RenderQue[i].AggTriangles.Length;
            }
            if(AggNodeCount != 0) {
                BVH8AggregatedBuffer = new ComputeBuffer(AggNodeCount, 80);
                AggTriBuffer = new ComputeBuffer(AggTriCount, 136);
                MeshFunctions.SetBuffer(TriangleBufferKernel, "OutCudaTriArray", AggTriBuffer);
                MeshFunctions.SetBuffer(NodeBufferKernel, "OutAggNodes", BVH8AggregatedBuffer);
                for(int i = 0; i < ParentsLength; i++) {
                    RenderQue[i].UpdateData(ref BVHOffset, ref MaterialOffset);
                    RenderQue[i].SetUpBuffers();
                    MeshFunctions.SetInt("Offset", CurTriOffset);
                    MeshFunctions.SetInt("Count", RenderQue[i].TriBuffer.count);
                    MeshFunctions.SetBuffer(TriangleBufferKernel, "InCudaTriArray", RenderQue[i].TriBuffer);
                    MeshFunctions.Dispatch(TriangleBufferKernel, (int)Mathf.Ceil(RenderQue[i].TriBuffer.count / 248.0f), 1, 1);

                    MeshFunctions.SetInt("Offset", CurNodeOffset);
                    MeshFunctions.SetInt("Count", RenderQue[i].BVHBuffer.count);
                    MeshFunctions.SetBuffer(NodeBufferKernel, "InAggNodes", RenderQue[i].BVHBuffer);
                    MeshFunctions.Dispatch(NodeBufferKernel, (int)Mathf.Ceil(RenderQue[i].BVHBuffer.count / 248.0f), 1, 1);
                    if(!RenderQue[i].IsSkinnedGroup) RenderQue[i].Release();

                    RenderQue[i].NodeOffset = CurNodeOffset;
                    RenderQue[i].TriOffset = CurTriOffset;
                    CurNodeOffset += RenderQue[i].AggNodes.Length;
                    CurTriOffset += RenderQue[i].AggTriangles.Length;

                    if(RenderQue[i].LightCount != 0) {
                        LightMeshCount++;
                        TotalEnergy += RenderQue[i].TotEnergy;
                        LightTransforms.Add(RenderQue[i].transform);
                        LightMeshes.Add(new LightMeshData() {
                            energy = RenderQue[i].TotEnergy,
                            TotalEnergy = TotalEnergy,
                            StartIndex = AggLightTriangles.Count,
                            IndexEnd = RenderQue[i].LightCount + AggLightTriangles.Count     
                          });
                        AggLightTriangles.AddRange(RenderQue[i].LightTriangles);
                    }
                }
            }
            GPUOctree = new List<GPUOctreeNode>();
            for(int i = 0; i < VoxelRenderQue.Count; i++) {
                GPUOctree.AddRange(VoxelRenderQue[i].GPUOctree);
            }
            if(GPUOctree.Count == 0) {
                UseVoxels = false;
                GPUOctree.Add(new GPUOctreeNode());
            } else {
                UseVoxels = true;
            }
            if(LightMeshCount == 0) {LightMeshes.Add(new LightMeshData() {});}
            if(AggLightTriangles.Count == 0) {AggLightTriangles.Add(new CudaLightTriangle() {}); LightTriCount = 0;} else {LightTriCount = AggLightTriangles.Count;}


           CreateAtlas();
        }
        ParentCountHasChanged = false;
        if(UseSkinning && didstart) { 
            for(int i = 0; i < ParentsLength; i++) {
                if(RenderQue[i].IsSkinnedGroup) {
                    RenderQue[i].RefitMesh(ref BVH8AggregatedBuffer);
                    MeshFunctions.SetInt("Offset", RenderQue[i].TriOffset);
                    MeshFunctions.SetInt("Count", RenderQue[i].TriBuffer.count);
                    MeshFunctions.SetBuffer(TriangleBufferKernel, "InCudaTriArray", RenderQue[i].TriBuffer);
                    MeshFunctions.Dispatch(TriangleBufferKernel, (int)Mathf.Ceil(RenderQue[i].TriBuffer.count / 248.0f), 1, 1);
                }
            }
        }
    }

    unsafe void Aggregate(ref BVH8Builder BVH8) {//BVH aggregation/BVH compression
        List<BVHNode8DataCompressed> TempBVHArray = new List<BVHNode8DataCompressed>();
        for(int i = 0; i < BVH8.BVH8Nodes.Length; ++i) {
            BVHNode8Data TempNode = BVH8.BVH8Nodes[i];

            TempBVHArray.Add(new BVHNode8DataCompressed() {
                node_0xyz = new Vector3(TempNode.p.x, TempNode.p.y, TempNode.p.z),
                node_0w = (TempNode.e[0] | (TempNode.e[1] << 8) | (TempNode.e[2] << 16) | (TempNode.imask << 24)),
                node_1x = TempNode.base_index_child,
                node_1y = TempNode.base_index_triangle,
                node_1z = (uint)(TempNode.meta[0] | (TempNode.meta[1] << 8) | (TempNode.meta[2] << 16) | (TempNode.meta[3] << 24)),
                node_1w = (uint)(TempNode.meta[4] | (TempNode.meta[5] << 8) | (TempNode.meta[6] << 16) | (TempNode.meta[7] << 24)),
                node_2x = (uint)(TempNode.quantized_min_x[0] | (TempNode.quantized_min_x[1] << 8) | (TempNode.quantized_min_x[2] << 16) | (TempNode.quantized_min_x[3] << 24)),
                node_2y = (uint)(TempNode.quantized_min_x[4] | (TempNode.quantized_min_x[5] << 8) | (TempNode.quantized_min_x[6] << 16) | (TempNode.quantized_min_x[7] << 24)),
                node_2z = (uint)(TempNode.quantized_max_x[0] | (TempNode.quantized_max_x[1] << 8) | (TempNode.quantized_max_x[2] << 16) | (TempNode.quantized_max_x[3] << 24)),
                node_2w = (uint)(TempNode.quantized_max_x[4] | (TempNode.quantized_max_x[5] << 8) | (TempNode.quantized_max_x[6] << 16) | (TempNode.quantized_max_x[7] << 24)),
                node_3x = (uint)(TempNode.quantized_min_y[0] | (TempNode.quantized_min_y[1] << 8) | (TempNode.quantized_min_y[2] << 16) | (TempNode.quantized_min_y[3] << 24)),
                node_3y = (uint)(TempNode.quantized_min_y[4] | (TempNode.quantized_min_y[5] << 8) | (TempNode.quantized_min_y[6] << 16) | (TempNode.quantized_min_y[7] << 24)),
                node_3z = (uint)(TempNode.quantized_max_y[0] | (TempNode.quantized_max_y[1] << 8) | (TempNode.quantized_max_y[2] << 16) | (TempNode.quantized_max_y[3] << 24)),
                node_3w = (uint)(TempNode.quantized_max_y[4] | (TempNode.quantized_max_y[5] << 8) | (TempNode.quantized_max_y[6] << 16) | (TempNode.quantized_max_y[7] << 24)),
                node_4x = (uint)(TempNode.quantized_min_z[0] | (TempNode.quantized_min_z[1] << 8) | (TempNode.quantized_min_z[2] << 16) | (TempNode.quantized_min_z[3] << 24)),
                node_4y = (uint)(TempNode.quantized_min_z[4] | (TempNode.quantized_min_z[5] << 8) | (TempNode.quantized_min_z[6] << 16) | (TempNode.quantized_min_z[7] << 24)),
                node_4z = (uint)(TempNode.quantized_max_z[0] | (TempNode.quantized_max_z[1] << 8) | (TempNode.quantized_max_z[2] << 16) | (TempNode.quantized_max_z[3] << 24)),
                node_4w = (uint)(TempNode.quantized_max_z[4] | (TempNode.quantized_max_z[5] << 8) | (TempNode.quantized_max_z[6] << 16) | (TempNode.quantized_max_z[7] << 24))

            });
        }
        BVH8AggregatedBuffer.SetData(TempBVHArray,0,0,TempBVHArray.Count);
    }

    unsafe void AggregateTLAS(ref BVH8Builder BVH8) {//BVH aggregation/BVH compression
        VoxelTLAS = new List<BVHNode8DataCompressed>();
        for(int i = 0; i < BVH8.BVH8Nodes.Length; ++i) {
            BVHNode8Data TempNode = BVH8.BVH8Nodes[i];

            VoxelTLAS.Add(new BVHNode8DataCompressed() {
                node_0xyz = new Vector3(TempNode.p.x, TempNode.p.y, TempNode.p.z),
                node_0w = (TempNode.e[0] | (TempNode.e[1] << 8) | (TempNode.e[2] << 16) | (TempNode.imask << 24)),
                node_1x = TempNode.base_index_child,
                node_1y = TempNode.base_index_triangle,
                node_1z = (uint)(TempNode.meta[0] | (TempNode.meta[1] << 8) | (TempNode.meta[2] << 16) | (TempNode.meta[3] << 24)),
                node_1w = (uint)(TempNode.meta[4] | (TempNode.meta[5] << 8) | (TempNode.meta[6] << 16) | (TempNode.meta[7] << 24)),
                node_2x = (uint)(TempNode.quantized_min_x[0] | (TempNode.quantized_min_x[1] << 8) | (TempNode.quantized_min_x[2] << 16) | (TempNode.quantized_min_x[3] << 24)),
                node_2y = (uint)(TempNode.quantized_min_x[4] | (TempNode.quantized_min_x[5] << 8) | (TempNode.quantized_min_x[6] << 16) | (TempNode.quantized_min_x[7] << 24)),
                node_2z = (uint)(TempNode.quantized_max_x[0] | (TempNode.quantized_max_x[1] << 8) | (TempNode.quantized_max_x[2] << 16) | (TempNode.quantized_max_x[3] << 24)),
                node_2w = (uint)(TempNode.quantized_max_x[4] | (TempNode.quantized_max_x[5] << 8) | (TempNode.quantized_max_x[6] << 16) | (TempNode.quantized_max_x[7] << 24)),
                node_3x = (uint)(TempNode.quantized_min_y[0] | (TempNode.quantized_min_y[1] << 8) | (TempNode.quantized_min_y[2] << 16) | (TempNode.quantized_min_y[3] << 24)),
                node_3y = (uint)(TempNode.quantized_min_y[4] | (TempNode.quantized_min_y[5] << 8) | (TempNode.quantized_min_y[6] << 16) | (TempNode.quantized_min_y[7] << 24)),
                node_3z = (uint)(TempNode.quantized_max_y[0] | (TempNode.quantized_max_y[1] << 8) | (TempNode.quantized_max_y[2] << 16) | (TempNode.quantized_max_y[3] << 24)),
                node_3w = (uint)(TempNode.quantized_max_y[4] | (TempNode.quantized_max_y[5] << 8) | (TempNode.quantized_max_y[6] << 16) | (TempNode.quantized_max_y[7] << 24)),
                node_4x = (uint)(TempNode.quantized_min_z[0] | (TempNode.quantized_min_z[1] << 8) | (TempNode.quantized_min_z[2] << 16) | (TempNode.quantized_min_z[3] << 24)),
                node_4y = (uint)(TempNode.quantized_min_z[4] | (TempNode.quantized_min_z[5] << 8) | (TempNode.quantized_min_z[6] << 16) | (TempNode.quantized_min_z[7] << 24)),
                node_4z = (uint)(TempNode.quantized_max_z[0] | (TempNode.quantized_max_z[1] << 8) | (TempNode.quantized_max_z[2] << 16) | (TempNode.quantized_max_z[3] << 24)),
                node_4w = (uint)(TempNode.quantized_max_z[4] | (TempNode.quantized_max_z[5] << 8) | (TempNode.quantized_max_z[6] << 16) | (TempNode.quantized_max_z[7] << 24))

            });
        }

    }

    public bool UpdateTLAS() {  //Allows for objects to be moved in the scene or animated while playing 
        
        bool LightsHaveUpdated = false;
        TempBuild();
        if(!didstart) {
            didstart = true;

        }

        UnityLights.Clear();
        float TotalEnergy = 0.0f;//(LightMeshes.Count != 0) ? LightMeshes[LightMeshes.Count - 1].TotalEnergy : 0.0f;
        UnityLightCount = 0;
        foreach(RayTracingLights RayLight in RayTracingMaster._rayTracingLights) {
            UnityLightCount++;
            RayLight.UpdateLight();
            TotalEnergy += RayLight.Energy;
            UnityLights.Add(new LightData() {
                Radiance = RayLight.Emission,
                Position = RayLight.Position,
                Direction = RayLight.Direction,
                energy = RayLight.Energy,
                TotalEnergy = TotalEnergy,
                Type = RayLight.Type,
                SpotAngle = RayLight.SpotAngle
                });
        }
        if(UnityLights.Count == 0) {UnityLights.Add(new LightData() {});}
        if(PrevLightCount != RayTracingMaster._rayTracingLights.Count) LightsHaveUpdated = true;
        PrevLightCount = RayTracingMaster._rayTracingLights.Count;
       
        MyMeshesCompacted.Clear();     
        int MeshDataCount =  RenderQue.Count;
        int aggregated_bvh_node_count = 2 * MeshDataCount;
        int AggNodeCount = aggregated_bvh_node_count;
        int AggTriCount = 0;
        int MatOffset = 0;
        for(int i = 0; i < MeshDataCount; i++) {
            if(!RenderQue[i].IsSkinnedGroup) RenderQue[i].UpdateAABB();
             MyMeshesCompacted.Add(new MyMeshDataCompacted() {
                mesh_data_bvh_offsets = aggregated_bvh_node_count,
                Transform = RenderQue[i].transform.worldToLocalMatrix,
                Inverse = RenderQue[i].transform.worldToLocalMatrix.inverse,
                Center = RenderQue[i].transform.position,
                AggIndexCount = AggTriCount,
                AggNodeCount = AggNodeCount,
                MaterialOffset = MatOffset,
                IsVoxel = 0,
                SizeX = 0,
                SizeY = 0,
                SizeZ = 0,
              });
             MatOffset += RenderQue[i].MatOffset;
            MeshAABBs[i] = RenderQue[i].aabb;
            AggNodeCount += RenderQue[i].AggBVHNodeCount;//Can I replace this with just using aggregated_bvh_node_count below?
            AggTriCount += RenderQue[i].AggIndexCount;
            aggregated_bvh_node_count += RenderQue[i].BVH.cwbvhnode_count;
        }
        LightMeshData CurLightMesh;
        for(int i = 0; i < LightMeshCount; i++) {
            CurLightMesh = LightMeshes[i];
            CurLightMesh.Inverse = LightTransforms[i].worldToLocalMatrix.inverse;
            CurLightMesh.Center = LightTransforms[i].position;
            LightMeshes[i] = CurLightMesh;
        }
        BVH2 = new BVH2Builder(MeshAABBs);
        BVH8Builder TLASBVH8 = new BVH8Builder(BVH2, ref MyMeshesCompacted);
        Aggregate(ref TLASBVH8);
        VoxOffset = MyMeshesCompacted.Count;
        AggNodeCount = 0;
        if(VoxelRenderQue.Count != 0) UseVoxels = true;
        else {
            UseVoxels = false;
        } 
        List<MyMeshDataCompacted> TempMeshCompacted = new List<MyMeshDataCompacted>();
        for(int i = 0; i < VoxelRenderQue.Count; i++) {
             TempMeshCompacted.Add(new MyMeshDataCompacted() {
                mesh_data_bvh_offsets = 0,
                Transform = VoxelRenderQue[i].transform.worldToLocalMatrix,
                Inverse = VoxelRenderQue[i].transform.worldToLocalMatrix.inverse,
                Center = VoxelRenderQue[i].transform.position,
                AggIndexCount = AggTriCount,
                AggNodeCount = AggNodeCount,
                MaterialOffset = MatOffset,
                IsVoxel = 1,
                SizeX = (int)VoxelRenderQue[i].Size.x,
                SizeY = (int)VoxelRenderQue[i].Size.y,
                SizeZ = (int)VoxelRenderQue[i].Size.z,
                MaxAxis = (int)VoxelRenderQue[i].LargestAxis
              });
             AggTriCount += VoxelRenderQue[i].GPUOctree.Length;
             AggNodeCount += VoxelRenderQue[i].GPUOctree.Length;
             MatOffset += VoxelRenderQue[i]._Materials.Count;
             VoxelRenderQue[i].UpdateAABB();
             VoxelAABBs[i] = VoxelRenderQue[i].aabb;

        }
        if(VoxelRenderQue.Count != 0) {
            BVH2 = new BVH2Builder(VoxelAABBs);
            TLASBVH8 = new BVH8Builder(BVH2, ref TempMeshCompacted);
            MyMeshesCompacted.AddRange(TempMeshCompacted);
            AggregateTLAS(ref TLASBVH8);
        } else {
            VoxelTLAS = new List<BVHNode8DataCompressed>();
            VoxelTLAS.Add(new BVHNode8DataCompressed());
        }

        return (LightsHaveUpdated || ChildrenUpdated);//The issue is that all light triangle indices start at 0, and thus might not get correctly sorted for indices
    }

    public void UpdateMaterials() {//Allows for live updating of material properties of any object
        int ParentCount = RenderQue.Count;
        RayTracingObject CurrentMaterial;
        for(int i = 0; i < ParentCount; i++) {
            int ChildCount = RenderQue[i].ChildObjects.Length;
            for(int i2 = 0; i2 < ChildCount; i2++) {
                CurrentMaterial = RenderQue[i].ChildObjects[i2];
                int MaterialCount = CurrentMaterial.MaterialIndex.Length;
                for(int i3 = 0; i3 < MaterialCount; i3++) {
                    MaterialData TempMat = _Materials[CurrentMaterial.MaterialIndex[i3]];
                    if(TempMat.HasAlbedoTex != 1) {
                        TempMat.BaseColor = CurrentMaterial.BaseColor[i3];
                    }
                    TempMat.emmissive = CurrentMaterial.emmission[i3];
                    TempMat.Roughness = (CurrentMaterial.MatType[i3] != 1) ? CurrentMaterial.Roughness[i3] : Mathf.Max(CurrentMaterial.Roughness[i3], 0.000001f);
                    TempMat.eta = CurrentMaterial.eta[i3];
                    TempMat.MatType = CurrentMaterial.MatType[i3];
                    _Materials[CurrentMaterial.MaterialIndex[i3]] = TempMat;
                }
            }
        }
    }

    /*
        public void OnDrawGizmos() {
        for(int i = 0; i < TempData.Length; i++) {
            Vector3 V1 = TempData[i].pos0;
            Vector3 V2 = V1 + TempData[i].posedge1;
            Vector3 V3 = V1 + TempData[i].posedge2;
            
            Gizmos.DrawLine(V1, V2);
            Gizmos.DrawLine(V1, V3);
            Gizmos.DrawLine(V3, V2);
        }
    }
*/

}
