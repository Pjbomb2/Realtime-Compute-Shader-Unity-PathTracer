using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace CommonVars {

    [System.Serializable]
    public struct LightData {
        public Vector3 Radiance;
        public Vector3 Position;
        public Vector3 Direction;
        public float energy;
        public float TotalEnergy;
        public int Type;
        public Vector2 SpotAngle;
    }



    [System.Serializable]
    public struct TriNodePairData {
        public int TriIndex;
        public int NodeIndex;
    }

    [System.Serializable]
    public struct Voxel {
        public int Index;
        public int Material;
        public int InArrayIndex;
    }

    [System.Serializable][System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Explicit)]
    public unsafe struct OctreeNode {
        [System.Runtime.InteropServices.FieldOffset(0)] public fixed int ChildNode[8];
        [System.Runtime.InteropServices.FieldOffset(32)] public fixed bool IsChild[8];
        [System.Runtime.InteropServices.FieldOffset(40)] public Vector3 BBMax;
        [System.Runtime.InteropServices.FieldOffset(52)]public Vector3 BBMin;
        [System.Runtime.InteropServices.FieldOffset(64)]public Vector3 Center;
        [System.Runtime.InteropServices.FieldOffset(76)]public Vector3 Extent;
        [System.Runtime.InteropServices.FieldOffset(88)]public int InArrayIndex;
    }

    [System.Serializable][System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Explicit)]
    unsafe public struct CompressedOctreeNode {
        [System.Runtime.InteropServices.FieldOffset(0)]public uint imask;    
        [System.Runtime.InteropServices.FieldOffset(4)]public uint base_index_child;
        [System.Runtime.InteropServices.FieldOffset(8)]public uint base_index_triangle;
        [System.Runtime.InteropServices.FieldOffset(12)]public uint Max;
        [System.Runtime.InteropServices.FieldOffset(16)]public uint Min;
        [System.Runtime.InteropServices.FieldOffset(20)]public fixed byte meta[8];//might be able to pack in material data as well so I could have it ignore glass!

    }

    [System.Serializable]
    unsafe public struct GPUOctreeNode {
        public uint node_1x;
        public uint node_1y;
        public uint Meta1;
        public uint Meta2;
        public Vector3 Center;
    }

    [System.Serializable]
    public struct GPUVoxel {
        public int Index;
        public int Material;
    }


    [System.Serializable]
    public struct MeshDat {
        public List<int> Indices;
        public List<Vector3> Verticies;
        public List<Vector3> Normals;
        public List<Vector4> Tangents;
        public List<Vector2> UVs;
        public List<int> MatDat;

        public void SetUvZero(int Count) {
            for(int i = 0; i < Count; i++) {
                UVs.Add(new Vector2(0.0f, 0.0f));
            }
        }
        public void init() {
            this.Tangents = new List<Vector4>();
            this.MatDat = new List<int>();
            this.UVs = new List<Vector2>();
            this.Verticies = new List<Vector3>();
            this.Normals = new List<Vector3>();
            this.Indices = new List<int>();
        }
        public void Clear() {
            if(Tangents != null) {
            this.Tangents.Clear();
            this.MatDat.Clear();
            this.UVs.Clear();
            this.Verticies.Clear();
            this.Normals.Clear();
            this.Indices.Clear();
        }
        }
    }


    [System.Serializable]
    public struct MaterialData {
        public Vector4 AlbedoTex;
        public Vector4 NormalTex;
        public Vector4 EmissiveTex;
        public Vector4 MetallicTex;
        public Vector4 RoughnessTex;
        public int HasAlbedoTex;
        public int HasNormalTex;
        public int HasEmissiveTex;
        public int HasMetallicTex;
        public int HasRoughnessTex;
        public Vector3 BaseColor;
        public float emmissive;
        public float Roughness;
        public int MatType;
        public Vector3 eta;
    }

    [System.Serializable]
    public struct BVHNode2Data {
        public AABB aabb;
        public int left;    
        public int first;
        public uint count;
        public uint axis;
    }
    
    [System.Serializable][System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Explicit)]
    unsafe public struct BVHNode8Data {
        [System.Runtime.InteropServices.FieldOffset(0)]public fixed uint e[3];
        [System.Runtime.InteropServices.FieldOffset(12)]public uint imask;    
        [System.Runtime.InteropServices.FieldOffset(16)]public uint base_index_child;
        [System.Runtime.InteropServices.FieldOffset(20)]public uint base_index_triangle;
        [System.Runtime.InteropServices.FieldOffset(24)]public fixed byte meta[8];
        [System.Runtime.InteropServices.FieldOffset(32)]public fixed byte quantized_min_x[8];
        [System.Runtime.InteropServices.FieldOffset(40)]public fixed byte quantized_max_x[8];
        [System.Runtime.InteropServices.FieldOffset(48)]public fixed byte quantized_min_y[8];
        [System.Runtime.InteropServices.FieldOffset(56)]public fixed byte quantized_max_y[8];
        [System.Runtime.InteropServices.FieldOffset(64)]public fixed byte quantized_min_z[8];
        [System.Runtime.InteropServices.FieldOffset(72)]public fixed byte quantized_max_z[8];
        [System.Runtime.InteropServices.FieldOffset(84)]public Vector3 p;
    }

    [System.Serializable]
    public struct BVHNode8DataFixed {
        public Vector3 p;
        public uint e1;
        public uint e2;
        public uint e3;
        public uint imask;    
        public uint base_index_child;
        public uint base_index_triangle;
        public uint meta1;
        public uint meta2;
        public uint meta3;
        public uint meta4;
        public uint meta5;
        public uint meta6;
        public uint meta7;
        public uint meta8;
        public uint quantized_min_x1;
        public uint quantized_min_x2;
        public uint quantized_min_x3;
        public uint quantized_min_x4;
        public uint quantized_min_x5;
        public uint quantized_min_x6;
        public uint quantized_min_x7;
        public uint quantized_min_x8;
        public uint quantized_max_x1;
        public uint quantized_max_x2;
        public uint quantized_max_x3;
        public uint quantized_max_x4;
        public uint quantized_max_x5;
        public uint quantized_max_x6;
        public uint quantized_max_x7;
        public uint quantized_max_x8;
        public uint quantized_min_y1;
        public uint quantized_min_y2;
        public uint quantized_min_y3;
        public uint quantized_min_y4;
        public uint quantized_min_y5;
        public uint quantized_min_y6;
        public uint quantized_min_y7;
        public uint quantized_min_y8;
        public uint quantized_max_y1;
        public uint quantized_max_y2;
        public uint quantized_max_y3;
        public uint quantized_max_y4;
        public uint quantized_max_y5;
        public uint quantized_max_y6;
        public uint quantized_max_y7;
        public uint quantized_max_y8;
        public uint quantized_min_z1;
        public uint quantized_min_z2;
        public uint quantized_min_z3;
        public uint quantized_min_z4;
        public uint quantized_min_z5;
        public uint quantized_min_z6;
        public uint quantized_min_z7;
        public uint quantized_min_z8;
        public uint quantized_max_z1;
        public uint quantized_max_z2;
        public uint quantized_max_z3;
        public uint quantized_max_z4;
        public uint quantized_max_z5;
        public uint quantized_max_z6;
        public uint quantized_max_z7;
        public uint quantized_max_z8;
    }



    [System.Serializable]
    public struct PrimitiveData {
        public AABB aabb;
        public Vector3 Center;
        public Vector3 V1;
        public Vector3 V2;
        public Vector3 V3;
        public Vector3 Norm1;
        public Vector3 Norm2;
        public Vector3 Norm3;
        public Vector3 Tan1;
        public Vector3 Tan2;
        public Vector3 Tan3;
        public Vector2 tex1;
        public Vector2 tex2;
        public Vector2 tex3;
        public int MatDat;

        public void Reconstruct() {
            Vector3 BBMin = Vector3.Min(Vector3.Min(V1,V2),V3);
            Vector3 BBMax = Vector3.Max(Vector3.Max(V1,V2),V3);
            for(int i2 = 0; i2 < 3; i2++) {
                if(BBMax[i2] - BBMin[i2] < 0.001f) {
                    BBMin[i2] -= 0.001f;
                    BBMax[i2] += 0.001f;
                }
            }
            Center = (V1 + V2 + V3) / 3.0f;
            aabb.BBMax = BBMax;
            aabb.BBMin = BBMin;
        }
    }

    public struct ProgReportData {
        public int Id;
        public string Name;
        public int TriCount;
        public void init(int Id, string Name, int TriCount) {
            this.Id = Id;
            this.Name = Name;
            this.TriCount = TriCount;
        }
    }
    
    [System.Serializable]
    public struct MyMeshDataCompacted {
        public Matrix4x4 Transform;
        public Matrix4x4 Inverse;
        public Vector3 Center;
        public int AggIndexCount;
        public int AggNodeCount;
        public int MaterialOffset;
        public int mesh_data_bvh_offsets;
        public uint IsVoxel;
        public int SizeX;
        public int SizeY;
        public int SizeZ;
        public int MaxAxis;
        //I do have the space to store 1 more int and 1 more other value to align to 128 bits
    }

    [System.Serializable]
    public struct AABB {
        public Vector3 BBMax;
        public Vector3 BBMin;

        public void Extend(ref AABB aabb) {
            this.BBMax = new Vector3(Mathf.Max(BBMax.x, aabb.BBMax.x), Mathf.Max(BBMax.y, aabb.BBMax.y), Mathf.Max(BBMax.z, aabb.BBMax.z));
            this.BBMin = new Vector3(Mathf.Min(BBMin.x, aabb.BBMin.x), Mathf.Min(BBMin.y, aabb.BBMin.y), Mathf.Min(BBMin.z, aabb.BBMin.z));
        }
        public void init() {
            BBMax = new Vector3(float.MinValue, float.MinValue, float.MinValue);
            BBMin = new Vector3(float.MaxValue, float.MaxValue, float.MaxValue);
        }
    }

        [System.Serializable]
    public struct NodeIndexPairData {
        public int PreviousNode;
        public int BVHNode;
        public int Node;
        public CommonVars.AABB AABB;
        public int InNodeOffset;
        public int IsLeaf;
        public int RecursionCount;
    }

    [System.Serializable]
    public struct BVHNode8DataCompressed {
        public Vector3 node_0xyz;
        public uint node_0w;
        public uint node_1x;
        public uint node_1y;
        public uint node_1z;
        public uint node_1w;
        public uint node_2x;
        public uint node_2y;
        public uint node_2z;
        public uint node_2w;
        public uint node_3x;
        public uint node_3y;
        public uint node_3z;
        public uint node_3w;
        public uint node_4x;
        public uint node_4y;
        public uint node_4z;
        public uint node_4w;
    }




    [System.Serializable]
    public struct CudaTriangle {
        public Vector3 pos0;
        public Vector3 posedge1;
        public Vector3 posedge2;

        public Vector3 norm0;
        public Vector3 normedge1;
        public Vector3 normedge2;

        public Vector3 tan0;
        public Vector3 tanedge1;
        public Vector3 tanedge2;

        public Vector2 tex0;
        public Vector2 texedge1;
        public Vector2 texedge2;

        public uint MatDat;
    }

    [System.Serializable]
    public struct CudaLightTriangle {
        public Vector3 pos0;
        public Vector3 posedge1;
        public Vector3 posedge2;
        public Vector3 Norm;

        public Vector3 radiance;
        public float sumEnergy;
        public float energy;
        public float area;
    }

    [System.Serializable]
    public struct LightMeshData {
        public Matrix4x4 Inverse;
        public Vector3 Center;
        public float energy;
        public float TotalEnergy;
        public int StartIndex;
        public int IndexEnd;
    }

    [System.Serializable]
    public struct Layer {
        unsafe public fixed int Children[8];
        unsafe public fixed int Leaf[8];

    }


    [System.Serializable]
    public struct SplitLayer {
        public int Child1;
        public int Child2;
        public int Child3;
        public int Child4;
        public int Child5;
        public int Child6;
        public int Child7;
        public int Child8;


        public int Leaf1;
        public int Leaf2;
        public int Leaf3;
        public int Leaf4;
        public int Leaf5;
        public int Leaf6;
        public int Leaf7;
        public int Leaf8;
    }

    [System.Serializable]
    public struct Layer2 {
        public List<int> Slab;
    }
    
}
