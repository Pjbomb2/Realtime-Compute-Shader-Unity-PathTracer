// Upgrade NOTE: commented out 'float4x4 _CameraToWorld', a built-in variable
// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

//#define UseSkyBox//Comment out to have no skybox and use precomputed atmosphere

// float4x4 _CameraToWorld;
float4x4 _CameraInverseProjection;
float4x4 ViewMatrix;
int frames_accumulated;
uniform int CurBounce;
uniform int MaxBounce;

uint screen_width;
uint screen_height;

int pixel_index;

int lighttricount;

int unitylightcount;

bool UseRussianRoulette;
bool UseNEE;
bool AllowVolumetrics;
bool UseDoF;

float VolumeDensity;

bool DoVoxels;
int VoxelOffset;


float3 Up;
float3 Right;
float3 Forward;
float focal_distance;
float AperatureRadius;

struct BufferSizeData {   
    int tracerays;
    int rays_retired;
    int octree_rays_retired;
    int shade_rays;
    int shadow_rays;
    int shadow_rays_retired;
    int octree_shadow_rays_retired;
};


struct RayData {//128 bit aligned
    float3 origin;
    float3 direction;

    uint4 hits;
    uint PixelIndex;//need to bump this back down to uint1
    bool HitVoxel;//need to shave off 4 bits
};

struct ShadowRayData {
    float3 origin;
    float3 direction;
    float3 illumination;
    uint PixelIndex;
    float t;
    bool IsNotFog;
    bool HitMesh;
};

struct LightTriangleData {
    float3 pos0;
    float3 posedge1;
    float3 posedge2;
    float3 Norm;

    float3 radiance;
    float sumEnergy;
    float energy;
    float area;
};

StructuredBuffer<LightTriangleData> LightTriangles;

struct CudaTriangle {
    float3 pos0;
    float3 posedge1;
    float3 posedge2;

    float3 norm0;
    float3 normedge1;
    float3 normedge2;

    float3 tan0;
    float3 tanedge1;
    float3 tanedge2;

    float2 tex0;
    float2 texedge1;
    float2 texedge2;

    uint MatDat;
};

struct Ray {
    float3 origin;
    float3 direction;
    float3 direction_inv;
};

struct RayHit {
    float t;
    float u, v;
    int mesh_id;
    int triangle_id;
};

struct ColData {
    float3 throughput;
    float3 Direct;
    float3 Indirect;
    float3 Fog;
};

int curframe;
RWTexture2D<float4> Result;

RWStructuredBuffer<ShadowRayData> ShadowRaysBuffer;
RWStructuredBuffer<RayData> GlobalRays1;
RWStructuredBuffer<RayData> GlobalRays2;
RWStructuredBuffer<ColData> GlobalColors;
RWStructuredBuffer<BufferSizeData> BufferSizes;

StructuredBuffer<CudaTriangle> AggTris;

Ray CreateRay(float3 origin, float3 direction) {
    Ray ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}

RayHit CreateRayHit() {
    RayHit hit;
    hit.t = 100000000;
    hit.u = 0;
    hit.v = 0;
    hit.mesh_id = 0;
    hit.triangle_id = 0;
    return hit;
}

void set(int index, const RayHit ray_hit) {
    uint uv = (int)(ray_hit.u * 65535.0f) | ((int)(ray_hit.v * 65535.0f) << 16);

    GlobalRays1[index].hits = uint4(ray_hit.mesh_id, ray_hit.triangle_id, asuint(ray_hit.t), uv);
}

RayHit get(int index) {
    const uint4 hit = GlobalRays1[index].hits;

    RayHit ray_hit;

    ray_hit.mesh_id = hit.x;
    ray_hit.triangle_id = hit.y;

    ray_hit.t = asfloat(hit.z);

    ray_hit.u = (float)(hit.w & 0xffff) / 65535.0f;
    ray_hit.v = (float)(hit.w >> 16) / 65535.0f;

    return ray_hit;
}

inline void set2(int index, const RayHit ray_hit) {
    uint uv = (uint)(ray_hit.u * 65535.0f) | ((int)(ray_hit.v * 65535.0f) << 16);

    GlobalRays2[index].hits = uint4(ray_hit.mesh_id, ray_hit.triangle_id, asuint(ray_hit.t), uv);
}

inline RayHit get2(int index) {
    const uint4 hit = GlobalRays2[index].hits;

    RayHit ray_hit;

    ray_hit.mesh_id = hit.x;
    ray_hit.triangle_id = hit.y;

    ray_hit.t = asfloat(hit.z);

    ray_hit.u = (float)(hit.w & 0xffff) / 65535.0f;
    ray_hit.v = (float)(hit.w >> 16) / 65535.0f;

    return ray_hit;
}


uint hash_with(uint seed, uint hash) {
    // Wang hash
    seed = (seed ^ 61) ^ hash;
    seed += seed << 3;
    seed ^= seed >> 4;
    seed *= 0x27d4eb2d;
    return seed;
}
uint pcg_hash(uint seed) {
    uint state = seed * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
float2 random(uint samdim) {
    uint hash = pcg_hash((pixel_index * (uint)112 + samdim) * (MaxBounce + 1) + CurBounce);

    const static float one_over_max_unsigned = asfloat(0x2f7fffff);

    float x = hash_with(frames_accumulated, hash) * one_over_max_unsigned;
    float y = hash_with(frames_accumulated + 0xdeadbeef, hash) * one_over_max_unsigned;

    return float2(x,y);
}

uint rng_state;

uint rand_lcg()
{
    // LCG values from Numerical Recipes
    rng_state = 1664525 * rng_state + 1013904223;
    return rng_state;
}

uint rand_xorshift()
{
    // Xorshift algorithm from George Marsaglia's paper
    rng_state ^= (rng_state << 13);
    rng_state ^= (rng_state >> 17);
    rng_state ^= (rng_state << 5);
    return rng_state;
}



#pragma kernel Generate 
    static const float PI = 3.14159265f;

Ray CreateCameraRay(float2 uv) {
    // Transform the camera origin to world space
    float3 origin = mul(unity_CameraToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;
    
    // Invert the perspective projection of the view-space position
    float3 direction = mul(_CameraInverseProjection, float4(uv, 0.0f, 1.0f)).xyz;
    // Transform the direction from camera to world space and normalize
    direction = mul(unity_CameraToWorld, float4(direction, 0.0f)).xyz;
    direction = normalize(direction);   
    [branch]if(UseDoF) {
        float3 cameraForward = mul(_CameraInverseProjection, float4(0,0, 0.0f, 1.0f)).xyz;
        // Transform the direction from camera to world space and normalize
        float4 sensorPlane;
        sensorPlane.xyz = cameraForward;
        sensorPlane.w = -dot(cameraForward, (origin - cameraForward));
            
        float t = -(dot(origin, sensorPlane.xyz) + sensorPlane.w) / dot(direction, sensorPlane.xyz);
        float3 sensorPos = origin + direction  * t;

        float3 cameraSpaceSensorPos = mul(ViewMatrix, float4(sensorPos, 1.0f)).xyz;
         
        // elongate z by the focal length
        cameraSpaceSensorPos.z *= focal_distance;
         
        // convert back into world space
        sensorPos = mul(unity_CameraToWorld, float4(cameraSpaceSensorPos, 1.0f)).xyz;

        float angle = random(6).x * 2.0f * PI;
        float radius = sqrt(random(6).y);
        float2 offset = float2(cos(angle), sin(angle)) * radius * AperatureRadius;

        float3 p = origin + direction * (focal_distance);

        float3 aperturePos = origin + Right * offset.x + Up * offset.y;

        origin = aperturePos;
        direction = normalize(p - origin);
    }


    return CreateRay(origin, direction);
}


[numthreads(256,1,1)]
void Generate (uint3 id : SV_DispatchThreadID) {
    
    if(id.x >= screen_width || id.y >= screen_height) return;
    pixel_index = id.y * screen_width + id.x;
    float2 jitter = random(1) - 0.5f;
    float2 uv = float2((id.xy + jitter) / float2(screen_width, screen_height) * 2.0f - 1.0f);
    Ray ray = CreateCameraRay(uv);

    const static RayHit tempray = CreateRayHit();

    set(pixel_index, tempray);
    GlobalRays1[pixel_index].origin = ray.origin;
    GlobalRays1[pixel_index].direction = ray.direction;
    GlobalRays1[pixel_index].PixelIndex = id.x + id.y * screen_width;
    GlobalRays1[pixel_index].HitVoxel = false;
    GlobalColors[pixel_index].throughput = float3(1.0f, 1.0f, 1.0f);
    GlobalColors[pixel_index].Direct = float3(0.0f, 0.0f, 0.0f);
    GlobalColors[pixel_index].Indirect = float3(0.0f, 0.0f, 0.0f);
    GlobalColors[pixel_index].Fog = float3(0.0f, 0.0f, 0.0f);
}


#pragma kernel kernel_trace 

    static const float ONE_OVER_PI = 0.318309886548;
    static const float EPSILON = 1e-8;

    struct MyMeshDataCompacted {
        float4x4 Transform;
        float4x4 Inverse;
        float3 Center;
        int TriOffset;
        int NodeOffset;
        int MaterialOffset;
        int mesh_data_bvh_offsets;//could I convert this an int4?
        uint IsVoxel;
        int3 Size;
        int MaxAxis;
    };

    struct BVHNode8Data {
        float3 node_0xyz;
        uint node_0w;
        uint4 node_1;
        uint4 node_2;
        uint4 node_3;
        uint4 node_4;
    };

    StructuredBuffer<BVHNode8Data> cwbvh_nodes;
    StructuredBuffer<BVHNode8Data> VoxelTLAS;
    StructuredBuffer<MyMeshDataCompacted> _MeshData;


    struct TrianglePos {
        float3 pos0;
        float3 posedge1;
        float3 posedge2;
    };

    inline TrianglePos triangle_get_positions(const int ID) {
        TrianglePos tri;
        tri.pos0 = AggTris[ID].pos0;
        tri.posedge1 = AggTris[ID].posedge1;
        tri.posedge2 = AggTris[ID].posedge2;
        return tri;
    }











    inline void IntersectTriangle(int mesh_id, int tri_id, const Ray ray, inout RayHit ray_hit) {

        TrianglePos tri = triangle_get_positions(tri_id);

        float3 h = cross(ray.direction, tri.posedge2);
        float  a = dot(tri.posedge1, h);

        float  f = rcp(a);
        float3 s = ray.origin - tri.pos0;
        float  u = f * dot(s, h);

        if (u >= 0.0f && u <= 1.0f) {//This may be fucking things up later, its supposed to be u >= 0.0f && u <= 1.0f, changed it to u == saturate(u)
            float3 q = cross(s, tri.posedge1);
            float  v = f * dot(ray.direction, q);

            if (v >= 0.0f && u + v <= 1.0f) {
                float t = f * dot(tri.posedge2, q);

                if (t > 0.0f && t < ray_hit.t) {
                    ray_hit.t = t;
                    ray_hit.u = u;
                    ray_hit.v = v;
                    ray_hit.mesh_id     = mesh_id;
                    ray_hit.triangle_id = tri_id;
                }
            }
        }
    }




    int Reps;
    inline uint cwbvh_node_intersect(const Ray ray, int oct_inv4, float max_distance, const float3 node_0, uint node_0w, const uint4 node_1, const uint4 node_2, const uint4 node_3, const uint4 node_4) {
Reps++;
        uint e_x = (node_0w) & 0xff;
        uint e_y = (node_0w >> (8)) & 0xff;
        uint e_z = (node_0w >> (16)) & 0xff;

        const float3 adjusted_ray_direction_inv = float3(
            asfloat(e_x << 23) * ray.direction_inv.x,
            asfloat(e_y << 23) * ray.direction_inv.y,
            asfloat(e_z << 23) * ray.direction_inv.z
            );
        const float3 adjusted_ray_origin = ray.direction_inv * (node_0 - ray.origin);
                
        uint hit_mask = 0;
        float3 tmin3;
        float3 tmax3;
        uint child_bits;
        uint bit_index;
        [unroll]
        for(int i = 0; i < 2; i++) {
            uint meta4 = asuint(i == 0 ? node_1.z : node_1.w);

            uint is_inner4   = (meta4 & (meta4 << 1)) & 0x10101010;
            uint inner_mask4 = (((is_inner4 << 3) >> 7) & 0x01010101) * 0xff;
            uint bit_index4  = (meta4 ^ (oct_inv4 & inner_mask4)) & 0x1f1f1f1f;
            uint child_bits4 = (meta4 >> 5) & 0x07070707;

            uint q_lo_x = asuint(i == 0 ? node_2.x : node_2.y);
            uint q_hi_x = asuint(i == 0 ? node_2.z : node_2.w);

            uint q_lo_y = asuint(i == 0 ? node_3.x : node_3.y);
            uint q_hi_y = asuint(i == 0 ? node_3.z : node_3.w);

            uint q_lo_z = asuint(i == 0 ? node_4.x : node_4.y);
            uint q_hi_z = asuint(i == 0 ? node_4.z : node_4.w);

            uint x_min = ray.direction.x < 0.0f ? q_hi_x : q_lo_x;
            uint x_max = ray.direction.x < 0.0f ? q_lo_x : q_hi_x;

            uint y_min = ray.direction.y < 0.0f ? q_hi_y : q_lo_y;
            uint y_max = ray.direction.y < 0.0f ? q_lo_y : q_hi_y;

            uint z_min = ray.direction.z < 0.0f ? q_hi_z : q_lo_z;
            uint z_max = ray.direction.z < 0.0f ? q_lo_z : q_hi_z;
            [unroll]
            for(int j = 0; j < 4; j++) {

                tmin3 = float3((float)((x_min >> (j * 8)) & 0xff), (float)((y_min >> (j * 8)) & 0xff), (float)((z_min >> (j * 8)) & 0xff));
                tmax3 = float3((float)((x_max >> (j * 8)) & 0xff), (float)((y_max >> (j * 8)) & 0xff), (float)((z_max >> (j * 8)) & 0xff));

                tmin3 = tmin3 * adjusted_ray_direction_inv + adjusted_ray_origin;
                tmax3 = tmax3 * adjusted_ray_direction_inv + adjusted_ray_origin;

                float tmin = max(max(tmin3.x, tmin3.y), max(tmin3.z, EPSILON));
                float tmax = min(min(tmax3.x, tmax3.y), min(tmax3.z, max_distance));
                
                bool intersected = tmin < tmax;
                [branch]
                if (intersected) {
                    child_bits = (child_bits4 >> (j * 8)) & 0xff;
                    bit_index  = (bit_index4 >> (j * 8)) & 0xff;

                    hit_mask |= child_bits << bit_index;
                }
            }
        }
        return hit_mask;
    }

inline uint ray_get_octant_inv4(const float3 ray_direction) {
    return
        (ray_direction.x < 0.0f ? 0 : 0x04040404) |
        (ray_direction.y < 0.0f ? 0 : 0x02020202) |
        (ray_direction.z < 0.0f ? 0 : 0x01010101);
}

    RWTexture2D<float4> _DebugTex;
void IntersectBVH() {
    RayHit bestHit;
    Ray ray;

    int TrisChecked;

    uint2 stack[24];
    int stack_size = 0;
    uint ray_index;
    uint2 current_group;

    uint oct_inv4;
    int tlas_stack_size;
    int mesh_id = -1;
    int NodeOffset = 0;
    int TriOffset = 0;
    Ray ray2;

    while(true) {
        bool inactive = stack_size == 0 && current_group.y == 0;

        if (inactive) {//Revive dead threads(persistent threads, need Shader Model 6 to take true advantage of)
            InterlockedAdd(BufferSizes[CurBounce].rays_retired, 1, ray_index);
            if(ray_index >= (uint)BufferSizes[CurBounce].tracerays) return;
            ray.origin = GlobalRays1[ray_index].origin;
            ray.direction = GlobalRays1[ray_index].direction;
            ray.direction_inv = rcp(ray.direction);
            ray2 = ray;
           
            oct_inv4 = ray_get_octant_inv4(ray.direction);

            current_group.x = (uint)0;
            current_group.y = (uint)0x80000000;
            bestHit = CreateRayHit();

            tlas_stack_size = -1;
            Reps = 0;
            TrisChecked = 0;
        }

        while(true) {//Traverse Accelleration Structure(Compressed Wide Bounding Volume Hierarchy)            
            uint2 triangle_group;
            if(current_group.y & 0xff000000) {
                uint hits_imask = current_group.y;
                uint child_index_offset = firstbithigh(hits_imask);
                uint child_index_base = current_group.x;

                current_group.y &= ~(1 << child_index_offset);

                if(current_group.y & 0xff000000) {
                    stack[stack_size++] = current_group;
                }
                uint slot_index = (child_index_offset - 24) ^ (oct_inv4 & 0xff);
                uint relative_index = countbits(hits_imask & ~(0xffffffff << slot_index));
                uint child_node_index = child_index_base + relative_index;
                const BVHNode8Data TempNode = cwbvh_nodes[child_node_index];
                float3 node_0 = TempNode.node_0xyz;
                uint node_0w = TempNode.node_0w;
                
                uint4 node_1 = TempNode.node_1;
                uint4 node_2 = TempNode.node_2;
                uint4 node_3 = TempNode.node_3;
                uint4 node_4 = TempNode.node_4;

                uint hitmask = cwbvh_node_intersect(ray, oct_inv4, bestHit.t, node_0, node_0w, node_1, node_2, node_3, node_4);
                TrisChecked++;
                uint imask = (node_0w >> (24)) & 0xff;

                current_group.x = asuint(node_1.x) + ((tlas_stack_size == -1) ? 0 : NodeOffset);
                triangle_group.x = asuint(node_1.y) + ((tlas_stack_size == -1) ? 0 : TriOffset);
//Z                if(current_group.x < 11) Reps++;
                current_group .y = (hitmask & 0xff000000) | (imask);
                triangle_group.y = (hitmask & 0x00ffffff);

            }
            else {
                triangle_group.x = current_group.x;
                triangle_group.y = current_group.y;
                current_group.x = (uint)0;
                current_group.y = (uint)0;
            }

            while(triangle_group.y != 0) { 

                if(tlas_stack_size == -1) {//Transfer from Top Level Accelleration Structure to Bottom Level Accelleration Structure
                    uint mesh_offset = firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << mesh_offset);
                    mesh_id = triangle_group.x + mesh_offset;
                    NodeOffset = _MeshData[mesh_id].NodeOffset;
                    TriOffset = _MeshData[mesh_id].TriOffset;
                    if(triangle_group.y != 0) {
                        stack[stack_size++] = triangle_group;
                    }

                    if(current_group.y & 0xff000000) {
                        stack[stack_size++] = current_group;
                    }
                    tlas_stack_size = stack_size;

                    int root_index = (_MeshData[mesh_id].mesh_data_bvh_offsets & 0x7fffffff);

                    ray.direction = (mul(_MeshData[mesh_id].Transform, float4(ray.direction, 0))).xyz;
                    ray.origin = (mul(_MeshData[mesh_id].Transform, float4(ray.origin, 1))).xyz;
                    ray.direction_inv = rcp(ray.direction);
                   
                    oct_inv4 = ray_get_octant_inv4(ray.direction);

                    current_group.x = (uint)root_index;
                    current_group.y = (uint)0x80000000;
//                    Reps++;

                    break;
                }
                else {
                    uint triangle_index =  firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << triangle_index);
                  //  TrisChecked++;
                    IntersectTriangle(mesh_id, triangle_group.x + triangle_index, ray, bestHit);//Intersect Mesh Triangles
                }
            }
            if((current_group.y & 0xff000000) == 0) {
                if(stack_size == 0) {//thread has finished traversing
                    GlobalRays2[ray_index] = GlobalRays1[ray_index];
                    set2(ray_index, bestHit);
                    int PixIndex = GlobalRays2[ray_index].PixelIndex;
                    uint2 TempUv = uint2(PixIndex % screen_width, PixIndex / screen_width);
                    _DebugTex[TempUv] = float4((Reps) / 45.0f,0,0,1);
                    current_group.y = 0;
                    break;
                }

                if(stack_size == tlas_stack_size) {
                    tlas_stack_size = -1;
                    ray = ray2;
                    oct_inv4 = ray_get_octant_inv4(ray.direction);
                }
                current_group = stack[--stack_size];
            }
        }
    }
}


[numthreads(64,1,1)]
void kernel_trace () {//If I move the function contents into here, unity yells at me, so for now its just gonna continue to live in its function
    IntersectBVH();
}

int NodesTraversed;


    struct OctreeData {
        uint2 node;
        uint Meta1;
        uint Meta2;
        float3 Center;
    };
    StructuredBuffer<OctreeData> Octree;

   inline float3 GetPosition(const int Index, const int3 Size) {
        float3 location;
        location.x = Index % Size.x;
        location.y = ((((int)Index - (int)location.x) / Size.x) % Size.y);
        location.z = (((Index - location.x - Size.x * location.y) / (Size.y * Size.x)));
        return location;
    }

    inline uint DecodeUint(const uint data, const uint selection) {
        switch(selection) {
            case 0:
                return (data) & 0xff;
            break;
            case 1:
                return (data >>  8) & 0xff;
            break;
            case 2:
                return (data >> 16) & 0xff;
            break;
            case 3:
                return (data >> 24) & 0xff;
            break;
            default:
                return 0;
            break;
        }
    }
inline bool rayBoxIntersection(const float3 ray_orig, const float3 inv_dir, const float3 Min, const float3 Max, float tMax, inout float t0) {
    const float3 tmp_min = (Min - ray_orig) * inv_dir;
    const float3 tmp_max = (Max - ray_orig) * inv_dir;
    const float3 tmin = min(tmp_min, tmp_max);
    const float3 tmax = max(tmp_min, tmp_max);
    t0 = max(tmin.x, max(tmin.y, max(tmin.z, 0))); // Usually ray_tmin = 0
    float t1 = min(tmax.x, min(tmax.y, min(tmax.z, tMax)));
    return (t0 <= t1);
}

#pragma kernel kernel_octree_trace
    static const  uint OctreeLUT[] = {
        6,7,2,5,4,1,3,0,
        2,1,6,5,3,0,7,4,
        3,2,7,0,1,4,6,5,
        7,3,6,4,0,5,2,1,    
        5,1,4,6,2,7,0,3,
        1,0,5,2,3,6,4,7,
        0,1,4,3,2,7,5,6,
        4,0,5,7,6,3,1,2
    };
inline bool TraceOctree(const float3 ray_orig, const float3 ray_dir_inv, inout RayHit bestHit, const int LutIndex, const int LargestAxis, const int3 Axis, const int Offset, const int MeshIndex) {
    float2 stack[24];
    int stack_size = 1;
    stack[0] = float2(Offset, LargestAxis / 4.0f);
    float tempmax = bestHit.t;
    float tmax = bestHit.t;
    float prevdist = bestHit.t;
    int TriangleID = 0;
    OctreeData node;
    float3 BBMin, BBMax;
    Reps = 0;
    while(stack_size != 0 && Reps < 2500) {
        Reps++;
        int2 stackindex = stack[--stack_size];
        node = Octree[stackindex.x];
        [unroll]for(int i = 7; i >= 0; i--) {
            int Index = OctreeLUT[i + LutIndex];
            uint meta = DecodeUint((Index < 4) ? node.Meta1 : node.Meta2, Index % 4);
            if(asuint(meta) == 255) continue;
            meta = meta & 31;
            bool IsLeaf = (meta) < 24;
            const int ChildIndex = meta + Offset + ((IsLeaf) ? (node.node.y) : (node.node.x - 23));
            BBMin = Octree[ChildIndex].Center;
            BBMax = BBMin + 1.0f;
            if(!IsLeaf) {   
                BBMax += stackindex.y - 1.0f;
                BBMin -= stackindex.y;
            }
            [branch]if(rayBoxIntersection(ray_orig, ray_dir_inv, BBMin, BBMax, tmax, tempmax)) {
                [branch]if(!IsLeaf) {
                    stack[stack_size++] = float2(ChildIndex, stackindex.y / 2.0f);
                } else {
                    tmax = tempmax;
                    TriangleID = ChildIndex;
                }
            }

        }

     
    }
    [branch]if(prevdist == tmax) return false;
    else {
        bestHit.triangle_id = TriangleID;
        bestHit.t = tmax;
        bestHit.mesh_id = MeshIndex;
    return true;
    }
}

void IntersectVoxelTLAS() {
    RayHit bestHit;
    Ray ray;

    uint2 stack[8];
    int stack_size = 0;
    uint ray_index;
    uint2 current_group;

    uint oct_inv4;
    int tlas_stack_size;
    int mesh_id =  VoxelOffset;
    int NodeOffset = 0;
    int TriOffset = 0;
    Ray ray2;
    while(true) {
        bool inactive = stack_size == 0 && current_group.y == 0;

        if (inactive) {//Revive dead threads(persistent threads, need Shader Model 6 to take true advantage of)
            InterlockedAdd(BufferSizes[CurBounce].octree_rays_retired, 1, ray_index);
            if(ray_index >= (uint)BufferSizes[CurBounce].tracerays) return;
            ray.origin = GlobalRays2[ray_index].origin;
            ray.direction = GlobalRays2[ray_index].direction;
            ray.direction_inv = rcp(ray.direction);
            bestHit = get2(ray_index);
            ray2 = ray;
           
            oct_inv4 = ray_get_octant_inv4(ray.direction);

            current_group.x = (uint)0;
            current_group.y = (uint)0x80000000;
            bestHit = get2(ray_index);

            tlas_stack_size = -1;
        }

        while(true) {//Traverse Accelleration Structure(Compressed Wide Bounding Volume Hierarchy)           
            uint2 triangle_group;
            if(current_group.y & 0xff000000) {
                uint hits_imask = current_group.y;
                uint child_index_offset = firstbithigh(hits_imask);
                uint child_index_base = current_group.x;

                current_group.y &= ~(1 << child_index_offset);

                if(current_group.y & 0xff000000) {
                    stack[stack_size++] = current_group;
                }
                uint slot_index = (child_index_offset - 24) ^ (oct_inv4 & 0xff);
                uint relative_index = countbits(hits_imask & ~(0xffffffff << slot_index));
                uint child_node_index = child_index_base + relative_index;

                float3 node_0 = VoxelTLAS[child_node_index].node_0xyz;
                uint node_0w = VoxelTLAS[child_node_index].node_0w;
                
                uint4 node_1 = VoxelTLAS[child_node_index].node_1;
                uint4 node_2 = VoxelTLAS[child_node_index].node_2;
                uint4 node_3 = VoxelTLAS[child_node_index].node_3;
                uint4 node_4 = VoxelTLAS[child_node_index].node_4;

                uint hitmask = cwbvh_node_intersect(ray, oct_inv4, bestHit.t, node_0, node_0w, node_1, node_2, node_3, node_4);
                uint imask = (node_0w >> (3 * 8)) & 0xff;

                current_group.x = asuint(node_1.x) + ((tlas_stack_size == -1) ? 0 : NodeOffset);
                triangle_group.x = asuint(node_1.y) + ((tlas_stack_size == -1) ? 0 : TriOffset);

                current_group .y = (hitmask & 0xff000000) | (imask);
                triangle_group.y = (hitmask & 0x00ffffff);
            }
            else {
                triangle_group.x = current_group.x;
                triangle_group.y = current_group.y;
                current_group.x = (uint)0;
                current_group.y = (uint)0;
            }

            while(triangle_group.y != 0) { 
                if(tlas_stack_size == -1) {//Transfer from Top Level Accelleration Structure to Bottom Level Accelleration Structure
                    Reps += 1;
                    uint mesh_offset = firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << mesh_offset);

                    mesh_id = triangle_group.x + mesh_offset + VoxelOffset;
                    NodeOffset = _MeshData[mesh_id].NodeOffset;
                    TriOffset = _MeshData[mesh_id].TriOffset;
                    if(triangle_group.y != 0) {
                        stack[stack_size++] = triangle_group;
                    }

                    if(current_group.y & 0xff000000) {
                        stack[stack_size++] = current_group;
                    }
                    tlas_stack_size = stack_size;

                    int root_index = (_MeshData[mesh_id].mesh_data_bvh_offsets & 0x7fffffff);

                    ray.direction = (mul(_MeshData[mesh_id].Transform, float4(ray.direction, 0))).xyz;
                    ray.origin = (mul(_MeshData[mesh_id].Transform, float4(ray.origin, 1))).xyz;
                    ray.direction_inv = rcp(ray.direction);

                    oct_inv4 = ray_get_octant_inv4(ray.direction);

                    current_group.y = (uint)0x80000000;
                    uint LutIndex = 0;
                    if(ray.direction.x < 0 && ray.direction.y < 0 && ray.direction.z > 0) LutIndex = 1; 
                    if(ray.direction.x > 0 && ray.direction.y < 0 && ray.direction.z > 0) LutIndex = 2; 
                    if(ray.direction.x > 0 && ray.direction.y < 0 && ray.direction.z < 0) LutIndex = 3;
                    if(ray.direction.x < 0 && ray.direction.y > 0 && ray.direction.z < 0) LutIndex = 4;
                    if(ray.direction.x < 0 && ray.direction.y > 0 && ray.direction.z > 0) LutIndex = 5; 
                    if(ray.direction.x > 0 && ray.direction.y > 0 && ray.direction.z > 0) LutIndex = 6; 
                    if(ray.direction.x > 0 && ray.direction.y > 0 && ray.direction.z < 0) LutIndex = 7;  
                    LutIndex *= 8;
                    if(TraceOctree(ray.origin, ray.direction_inv, bestHit, LutIndex, _MeshData[mesh_id].MaxAxis + 1, _MeshData[mesh_id].MaxAxis,  _MeshData[mesh_id].NodeOffset, mesh_id)) {GlobalRays2[ray_index].HitVoxel = true; set2(ray_index, bestHit);}
                    break;
                }
                else {
                    uint triangle_index =  firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << triangle_index);
                }
            }
            if((current_group.y & 0xff000000) == 0) {
                if(stack_size == 0) {//thread has finished traversing
                    set2(ray_index, bestHit);
                    break;
                }

                if(stack_size == tlas_stack_size) {

                    tlas_stack_size = -1;
                    ray = ray2;
                    oct_inv4 = ray_get_octant_inv4(ray.direction);
                }
                current_group = stack[--stack_size];
            }
        }
    }
}


[numthreads(128,1,1)]
void kernel_octree_trace () {//If I move the function contents into here, unity yells at me, so for now its just gonna continue to live in its function

    IntersectVoxelTLAS();
}



struct Reservoir {
    float y;
    float wsum;
    float M;
    float W;
    uint WasSuccessful;
};

RWStructuredBuffer<Reservoir> CurrentReservoir;
RWStructuredBuffer<Reservoir> PreviousReservoir;


#pragma kernel kernel_shadow

TrianglePos triangle_get_positions2(int ID) {
    TrianglePos tri;
    tri.pos0 = LightTriangles[ID].pos0;
    tri.posedge1 = LightTriangles[ID].posedge1;
    tri.posedge2 = LightTriangles[ID].posedge2;
    return tri;
}

inline bool triangle_intersect_shadow(int tri_id, const Ray ray, float max_distance) {
    TrianglePos tri = triangle_get_positions(tri_id);

    float3 h = cross(ray.direction, tri.posedge2);
        float  a = dot(tri.posedge1, h);

        float  f = rcp(a);
        float3 s = ray.origin - tri.pos0;
        float  u = f * dot(s, h);

    if (u >= 0.0f && u <= 1.0f) {
        float3 q = cross(s, tri.posedge1);
        float  v = f * dot(ray.direction, q);

        if (v >= 0.0f && u + v <= 1.0f) {
            float t = f * dot(tri.posedge2, q);

            if (t > 0.0f && t < max_distance) return true;
        }
    }

    return false;
}



void IntersectBVHShadow() {
    Ray ray;

    uint2 stack[24];
    int stack_size = 0;
    uint ray_index;
    uint2 current_group;

    uint oct_inv4;
    int tlas_stack_size;
    int mesh_id;
    float max_distance;
    Ray ray2;

    while(true) {
        bool inactive = stack_size == 0 && current_group.y == 0;

        if (inactive) {//Revive dead threads(persistent threads, need Shader Model 6 to take true advantage of)
            InterlockedAdd(BufferSizes[CurBounce].shadow_rays_retired, 1, ray_index);
            if(ray_index >= (uint)BufferSizes[CurBounce].shadow_rays) return;
            ray.origin = ShadowRaysBuffer[ray_index].origin;
            ray.direction = ShadowRaysBuffer[ray_index].direction;
            ray.direction_inv = rcp(ray.direction);
            ray2 = ray;
           
            oct_inv4 = ray_get_octant_inv4(ray.direction);

            current_group.x = (uint)0;
            current_group.y = (uint)0x80000000;

            max_distance = ShadowRaysBuffer[ray_index].t;

            tlas_stack_size = -1;
        }

        while(true) {//Traverse Accelleration Structure(Compressed Wide Bounding Volume Hierarchy)            
            uint2 triangle_group;
            if(current_group.y & 0xff000000) {
                uint hits_imask = current_group.y;
                uint child_index_offset = firstbithigh(hits_imask);
                uint child_index_base = current_group.x;

                current_group.y &= ~(1 << child_index_offset);

                if(current_group.y & 0xff000000) {
                    stack[stack_size++] = current_group;
                }
                uint slot_index = (child_index_offset - 24) ^ (oct_inv4 & 0xff);
                uint relative_index = countbits(hits_imask & ~(0xffffffff << slot_index));
                uint child_node_index = child_index_base + relative_index;

                float3 node_0 = cwbvh_nodes[child_node_index].node_0xyz;
                uint node_0w = cwbvh_nodes[child_node_index].node_0w;
                
                uint4 node_1 = cwbvh_nodes[child_node_index].node_1;
                uint4 node_2 = cwbvh_nodes[child_node_index].node_2;
                uint4 node_3 = cwbvh_nodes[child_node_index].node_3;
                uint4 node_4 = cwbvh_nodes[child_node_index].node_4;

                uint hitmask = cwbvh_node_intersect(ray, oct_inv4, max_distance, node_0, node_0w, node_1, node_2, node_3, node_4);

                uint imask = (node_0w >> (3 * 8)) & 0xff;

                current_group.x = asuint(node_1.x) + ((tlas_stack_size == -1) ? 0 : _MeshData[mesh_id].NodeOffset);
                triangle_group.x = asuint(node_1.y) + ((tlas_stack_size == -1) ? 0 : _MeshData[mesh_id].TriOffset);

                current_group .y = (hitmask & 0xff000000) | (uint)(imask);
                triangle_group.y = (hitmask & 0x00ffffff);
            }
            else {
                triangle_group.x = current_group.x;
                triangle_group.y = current_group.y;
                current_group.x = (uint)0;
                current_group.y = (uint)0;
            }

            bool hit = false;

            while(triangle_group.y != 0) { 
                if(tlas_stack_size == -1) {//Transfer from Top Level Accelleration Structure to Bottom Level Accelleration Structure
                    uint mesh_offset = firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << mesh_offset);

                    mesh_id = triangle_group.x + mesh_offset;

                    if(triangle_group.y != 0) {
                        stack[stack_size++] = triangle_group;
                    }

                    if(current_group.y & 0xff000000) {
                        stack[stack_size++] = current_group;
                    }
                    tlas_stack_size = stack_size;

                    int root_index = (_MeshData[mesh_id].mesh_data_bvh_offsets & 0x7fffffff);

                    ray.direction = (mul(_MeshData[mesh_id].Transform, float4(ray.direction, 0))).xyz;
                    ray.origin = (mul(_MeshData[mesh_id].Transform, float4(ray.origin, 1))).xyz;
                    ray.direction_inv = rcp(ray.direction);
                   
                    oct_inv4 = ray_get_octant_inv4(ray.direction);

                    current_group.x = (uint)root_index;
                    current_group.y = (uint)0x80000000;

                    break;
                }
                else {
                    uint triangle_index =  firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << triangle_index);

                    if(triangle_intersect_shadow(triangle_group.x + triangle_index, ray, max_distance)) {
                        hit = true;
                        break;
                    }
                }
            }

            if(hit) {
                stack_size = 0;
                current_group.y = 0;
                break;
            }

            if((current_group.y & 0xff000000) == 0) {
                if(stack_size == 0) {//thread has finished traversing
                    ShadowRaysBuffer[ray_index].HitMesh = false;
                    CurrentReservoir[ray_index].WasSuccessful = 1;
                    current_group.y = 0;
                    break;
                }

                if(stack_size == tlas_stack_size) {
                    tlas_stack_size = -1;
                    ray = ray2;
                    oct_inv4 = ray_get_octant_inv4(ray.direction);
                }
                current_group = stack[--stack_size];
            }
        }
    }
}


[numthreads(64,1,1)]
void kernel_shadow () {//If I move the function contents into here, unity yells at me, so for now its just gonna continue to live in its function
    IntersectBVHShadow();
}



#pragma kernel kernel_shadow_octree

inline bool rayBoxIntersection(const float3 ray_orig, const float3 inv_dir, const float3 Min, const float3 Max, float tMax) {
    float3 tmp_min = (Min - ray_orig) * inv_dir;
    float3 tmp_max = (Max - ray_orig) * inv_dir;
    float3 tmin = min(tmp_min, tmp_max);
    float3 tmax = max(tmp_min, tmp_max);
    return (max(tmin.x, max(tmin.y, max(tmin.z, 0))) <= min(tmax.x, min(tmax.y, min(tmax.z, tMax))));
}

inline bool TraceShadowOctree(const float3 ray_orig, const float3 ray_dir_inv, float tmax, const int LutIndex, const int LargestAxis, const int Offset, const int MeshIndex) {
    float2 stack[8];
    int stack_size = 1;
    stack[0] = float2(Offset, LargestAxis / 4.0f);
    float tmin = 0;
    float tempmax = tmax;
    float tempmin = 0;
    int TriangleID = 0;
    OctreeData node;
    float3 BBMax, BBMin;
    bool DidHit = false;
    Reps = 0;
    while(stack_size != 0 && Reps < 2500) {
        Reps++;
        int2 stackindex = stack[--stack_size];
        node = Octree[stackindex.x];
        [unroll]for(int i = 7; i >= 0; i--) {
            int Index = OctreeLUT[i + LutIndex];
            uint meta = DecodeUint((Index < 4) ? node.Meta1 : node.Meta2, Index % 4);
            if(asuint(meta) == 255) continue;
            meta = meta & 31;
            bool IsLeaf = (meta) < 24;
            const int ChildIndex = meta + Offset + ((IsLeaf) ? (node.node.y) : (node.node.x - 23));
            BBMin = Octree[ChildIndex].Center;
            BBMax = BBMin + 1.0f;
            if(!IsLeaf) {   
                BBMax += stackindex.y - 1.0f;
                BBMin -= stackindex.y;
            }
            [branch]if( rayBoxIntersection(ray_orig, ray_dir_inv, BBMin, BBMax, tmax)) {
                [branch]if(!IsLeaf) {
                    stack[stack_size++] = int2(ChildIndex, stackindex.y / 2.0f);
                } else {
                    DidHit = true; 
                }
            }

        }
    }
    return DidHit;
}

void IntersectVoxelTLASShadow() {
    Ray ray;

    uint2 stack[8];
    int stack_size = 0;
    uint ray_index;
    uint2 current_group;

    uint oct_inv4;
    int tlas_stack_size;
    int mesh_id =  VoxelOffset;
    int NodeOffset = 0;
    int TriOffset = 0;
    float max_distance;
    Ray ray2;
    bool DidHit = false;
    while(true) {
        bool inactive = stack_size == 0 && current_group.y == 0;

        if (inactive) {//Revive dead threads(persistent threads, need Shader Model 6 to take true advantage of)
            InterlockedAdd(BufferSizes[CurBounce].octree_shadow_rays_retired, 1, ray_index);
            if(ray_index >= (uint)BufferSizes[CurBounce].shadow_rays) return;
            if(ShadowRaysBuffer[ray_index].HitMesh) continue;
            max_distance = ShadowRaysBuffer[ray_index].t;
            ray.origin = ShadowRaysBuffer[ray_index].origin;
            ray.direction = ShadowRaysBuffer[ray_index].direction;
            ray.direction_inv = rcp(ray.direction);
            ray2 = ray;
            DidHit = false;
           
            oct_inv4 = ray_get_octant_inv4(ray.direction);

            current_group.x = (uint)0;
            current_group.y = (uint)0x80000000;

            tlas_stack_size = -1;
        }

        while(true) {//Traverse Accelleration Structure(Compressed Wide Bounding Volume Hierarchy)          
            uint2 triangle_group;
            if(current_group.y & 0xff000000) {
                uint hits_imask = current_group.y;
                uint child_index_offset = firstbithigh(hits_imask);
                uint child_index_base = current_group.x;

                current_group.y &= ~(1 << child_index_offset);

                if(current_group.y & 0xff000000) {
                    stack[stack_size++] = current_group;
                }
                uint slot_index = (child_index_offset - 24) ^ (oct_inv4 & 0xff);
                uint relative_index = countbits(hits_imask & ~(0xffffffff << slot_index));
                uint child_node_index = child_index_base + relative_index;

                float3 node_0 = VoxelTLAS[child_node_index].node_0xyz;
                uint node_0w = VoxelTLAS[child_node_index].node_0w;
                
                uint4 node_1 = VoxelTLAS[child_node_index].node_1;
                uint4 node_2 = VoxelTLAS[child_node_index].node_2;
                uint4 node_3 = VoxelTLAS[child_node_index].node_3;
                uint4 node_4 = VoxelTLAS[child_node_index].node_4;

                uint hitmask = cwbvh_node_intersect(ray, oct_inv4, max_distance, node_0, node_0w, node_1, node_2, node_3, node_4);
                uint imask = (node_0w >> (3 * 8)) & 0xff;

                current_group.x = asuint(node_1.x) + ((tlas_stack_size == -1) ? 0 : NodeOffset);
                triangle_group.x = asuint(node_1.y) + ((tlas_stack_size == -1) ? 0 : TriOffset);

                current_group .y = (hitmask & 0xff000000) | (imask);
                triangle_group.y = (hitmask & 0x00ffffff);
            }
            else {
                triangle_group.x = current_group.x;
                triangle_group.y = current_group.y;
                current_group.x = (uint)0;
                current_group.y = (uint)0;
            }

            while(triangle_group.y != 0) { 
                if(tlas_stack_size == -1) {//Transfer from Top Level Accelleration Structure to Bottom Level Accelleration Structure
                    uint mesh_offset = firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << mesh_offset);

                    mesh_id = triangle_group.x + mesh_offset + VoxelOffset;
                    NodeOffset = _MeshData[mesh_id].NodeOffset;
                    TriOffset = _MeshData[mesh_id].TriOffset;
                    if(triangle_group.y != 0) {
                        stack[stack_size++] = triangle_group;
                    }

                    if(current_group.y & 0xff000000) {
                        stack[stack_size++] = current_group;
                    }
                    tlas_stack_size = stack_size;

                    int root_index = (_MeshData[mesh_id].mesh_data_bvh_offsets & 0x7fffffff);

                    ray.direction = (mul(_MeshData[mesh_id].Transform, float4(ray.direction, 0))).xyz;
                    ray.origin = (mul(_MeshData[mesh_id].Transform, float4(ray.origin, 1))).xyz;
                    ray.direction_inv = rcp(ray.direction);

                    oct_inv4 = ray_get_octant_inv4(ray.direction);

                    current_group.y = (uint)0x80000000;
                    uint LutIndex = 0;
                    if(ray.direction.x < 0 && ray.direction.y < 0 && ray.direction.z > 0) LutIndex = 1; 
                    if(ray.direction.x > 0 && ray.direction.y < 0 && ray.direction.z > 0) LutIndex = 2; 
                    if(ray.direction.x > 0 && ray.direction.y < 0 && ray.direction.z < 0) LutIndex = 3;
                    if(ray.direction.x < 0 && ray.direction.y > 0 && ray.direction.z < 0) LutIndex = 4;
                    if(ray.direction.x < 0 && ray.direction.y > 0 && ray.direction.z > 0) LutIndex = 5; 
                    if(ray.direction.x > 0 && ray.direction.y > 0 && ray.direction.z > 0) LutIndex = 6; 
                    if(ray.direction.x > 0 && ray.direction.y > 0 && ray.direction.z < 0) LutIndex = 7;  
                    LutIndex *= 8;
                    DidHit = TraceShadowOctree(ray.origin, ray.direction_inv, max_distance, LutIndex, _MeshData[VoxelOffset].MaxAxis + 1, _MeshData[mesh_id].NodeOffset, mesh_id);
                    break;
                }
                else {
                    uint triangle_index =  firstbithigh(triangle_group.y);
                    triangle_group.y &= ~(1 << triangle_index);
                }
            }
            if((current_group.y & 0xff000000) == 0 || DidHit) {
                if(DidHit) {
                    stack_size = 0;
                    break;
                }
                if(stack_size == 0) {//thread has finished traversing
                    int pixel_index = ShadowRaysBuffer[ray_index].PixelIndex;
                    if(ShadowRaysBuffer[ray_index].IsNotFog) {
                        if(CurBounce == 0) {
                            GlobalColors[pixel_index].Direct += ShadowRaysBuffer[ray_index].illumination;
                        } else {
                            GlobalColors[pixel_index].Indirect +=ShadowRaysBuffer[ray_index].illumination;
                        }
                    } else {
                        GlobalColors[pixel_index].Fog += ShadowRaysBuffer[ray_index].illumination;
                    }
                    break;
                }

                if(stack_size == tlas_stack_size) {

                    tlas_stack_size = -1;
                    ray = ray2;
                    oct_inv4 = ray_get_octant_inv4(ray.direction);
                }
                current_group = stack[--stack_size];
            }
        }
    }
}

void IntersectShadowOctree() {
    uint ray_index;
    if(DoVoxels) {
        IntersectVoxelTLASShadow();
    } else {
        while(true) {
            InterlockedAdd(BufferSizes[CurBounce].octree_shadow_rays_retired, 1, ray_index);
            if(ray_index >= (uint)BufferSizes[CurBounce].shadow_rays) return;
            if(ShadowRaysBuffer[ray_index].HitMesh) continue;
            int pixel_index = ShadowRaysBuffer[ray_index].PixelIndex;
            if(ShadowRaysBuffer[ray_index].IsNotFog) {
                if(CurBounce == 0) {
                    GlobalColors[pixel_index].Direct += ShadowRaysBuffer[ray_index].illumination;
                } else {
                    GlobalColors[pixel_index].Indirect +=ShadowRaysBuffer[ray_index].illumination;
                }
            } else {
                GlobalColors[pixel_index].Fog += ShadowRaysBuffer[ray_index].illumination;
            }
        }
    }
}


[numthreads(64,1,1)]
void kernel_shadow_octree () {//If I move the function contents into here, unity yells at me, so for now its just gonna continue to live in its function

    IntersectShadowOctree();
}


#pragma kernel kernel_shade

int LightMeshCount;

struct LightMeshData {
    float4x4 Inverse;
    float3 Center;
    float energy;
    float TotalEnergy;
    int StartIndex;
    int IndexEnd;
};
StructuredBuffer<LightMeshData> _LightMeshes;

struct LightData {
    float3 Radiance;
    float3 Position;
    float3 Direction;
    float energy;
    float TotalEnergy;
    int Type;
    float2 SpotAngle;
};
StructuredBuffer<LightData> _UnityLights;


struct MaterialData {//56
    float4 AlbedoTex;//16
    float4 NormalTex;//32
    float4 EmissiveTex;//48
    float4 MetallicTex;//64
    float4 RoughnessTex;//80
    int HasAlbedoTex;//81
    int HasNormalTex;//82
    int HasEmissiveTex;//83
    int HasMetallicTex;//84
    int HasRoughnessTex;//85
    float3 BaseColor;//97
    float emmissive;//101
    float roughness;//105
    int MatType;//109
    float3 eta;//121
};


StructuredBuffer<MaterialData> _Materials;

Texture2D<float4> _SkyboxTexture;
SamplerState sampler_SkyboxTexture;

Texture2D<float4> _TextureAtlas;
SamplerState sampler_TextureAtlas;

Texture2D<float4> _NormalAtlas;
SamplerState sampler_NormalAtlas;

Texture2D<float4> _EmissiveAtlas;
SamplerState sampler_EmissiveAtlas;

Texture2D<float4> _MetallicAtlas;
SamplerState sampler_MetallicAtlas;

Texture2D<float4> _RoughnessAtlas;
SamplerState sampler_RoughnessAtlas;

//These are here purely for the Atrous
RWTexture2D<float4> TempPosTex;
RWTexture2D<float4> TempNormTex;
RWTexture2D<float4> TempAlbedoTex;

struct HitMat {
    float3 surfaceColor;
    float emmis;
    float roughness;
    uint MatType;
    float3 eta;
};

HitMat CreateHitMat() {
    HitMat hit;
    hit.surfaceColor  = float3(0.0f, 0.0f, 0.0f);
    hit.emmis = 0.0f;
    hit.roughness = 0.0f;
    hit.MatType = 0;
    hit.eta = float3(0.0f, 0.0f, 0.0f);
    return hit;
}

int SelectUnityLight() {
    if(unitylightcount == 1) return 0;
    const float2 rand_light = random(5);
    float e = _UnityLights[unitylightcount - 1].TotalEnergy * rand_light.x + _UnityLights[0].TotalEnergy;
    int low = 0;
    int high = unitylightcount - 1;
    if(e > _UnityLights[high - 1].energy + _UnityLights[high - 1].TotalEnergy) return high;
    int mid = -1;
    while(low < high) {
        int mid = (low + high) >> 1;
        LightData thislight = _UnityLights[mid];
        if(e < thislight.TotalEnergy)
            high = mid;
        else if(e > thislight.TotalEnergy + thislight.energy)
            low = mid + 1;
        else
            return mid;
    }
    return mid;
    // Failed to find a light using importance sampling, pick a random one from the array
    // NOTE: this is a failsafe, we should never get here!
    return clamp((rand_light.y * unitylightcount), 0, unitylightcount - 1);
}

int SelectLight(int MeshIndex) {//Need to check these to make sure they arnt simply doing uniform sampling

    const float2 rand_light = random(3);
    const int StartIndex = _LightMeshes[MeshIndex].StartIndex;
    const int IndexEnd = _LightMeshes[MeshIndex].IndexEnd;
    float e = LightTriangles[IndexEnd - 1].sumEnergy * rand_light.x + LightTriangles[StartIndex].energy;
    int low = StartIndex;
    int high = IndexEnd - 1;
    if(e > LightTriangles[high - 1].energy + LightTriangles[high - 1].sumEnergy) return high;
    int mid = -1;
    while(low < high) {
        int mid = (low + high) >> 1;
        LightTriangleData tri = LightTriangles[mid];
        if(e < tri.sumEnergy)
            high = mid;
        else if(e > tri.sumEnergy + tri.energy)
            low = mid + 1;
        else
            return mid;
    }
    return mid;
    // Failed to find a light using importance sampling, pick a random one from the array
    // NOTE: this is a failsafe, we should never get here!
    return clamp((rand_light.y * (IndexEnd - StartIndex)), StartIndex, IndexEnd - 1);
}

int SelectLightMesh() {//Select mesh to sample light from
    if(LightMeshCount == 1) return 0;
    const float2 rand_mesh = random(4);
    float e = _LightMeshes[LightMeshCount - 1].TotalEnergy * rand_mesh.x + _LightMeshes[0].energy;
    int low = 0;
    int high = LightMeshCount - 1;
    if(e > _LightMeshes[high - 1].energy + _LightMeshes[high - 1].TotalEnergy) return high;
    int mid = -1;
    while(low < high) {
        int mid = (low + high) >> 1;
        LightMeshData mesh = _LightMeshes[mid];
        if(e < mesh.TotalEnergy)
            high = mid;
        else if(e > mesh.TotalEnergy + mesh.energy)
            low = mid + 1;
        else
            return mid;
    }
    return mid;
    // Failed to find a light using importance sampling, pick a random one from the array
    // NOTE: this is a failsafe, we should never get here!
    return clamp((rand_mesh.y * LightMeshCount), 0, LightMeshCount - 1);
}

float2 sample_disc(float u1, float u2) {
    float a = 2.0f * u1 - 1.0f;
    float b = 2.0f * u2 - 1.0f;
    if(a == 0.0f) a = 0.00001;
    if(b == 0.0f) b = 0.00001;

    float phi, r;
    if(a*a > b*b) {
        r = a;
        phi = (0.25f * PI) * (b/a);
    } else {
        r = b;
        phi = (0.25f * PI) * (a/b) + (0.5f * PI);
    }

    float sin_phi, cos_phi;
    sincos(phi, sin_phi, cos_phi);
    
    return float2(r * cos_phi, r * sin_phi);
}

float3 sample_cosine_weighted_direction(float u1, float u2) {
    float2 d = sample_disc(u1, u2);
    return float3(d.x, d.y, sqrt(abs(1.0f - dot(d, d))));
}

float3 sample(inout float pdf) {//Diffuse
    float2 rando = random(5);
    float3 omega_o = sample_cosine_weighted_direction(rando.x, rando.y);
    pdf = omega_o.z * ONE_OVER_PI;
    return omega_o;
}

float3 sample(inout float pdf, int rand) {//Diffuse
    float2 rando = random(rand);
    float3 omega_o = sample_cosine_weighted_direction(rando.x, rando.y);
    pdf = omega_o.z * ONE_OVER_PI;
    return omega_o;
}

float3x3 GetTangentSpace(float3 normal) {
    // Choose a helper vector for the cross product
    float3 helper = float3(1, 0, 0);
    if (abs(normal.x) > 0.99f)
        helper = float3(0, 0, 1);

    // Generate vectors
    float3 tangent = normalize(cross(normal, helper));
    float3 binormal = cross(normal, tangent);
    
    return float3x3(tangent, binormal, normal);
}

float3 sample_visible_normals_ggx(float3 omega, float alpha_x, float alpha_y, float u1, float u2) {
    float3 v = normalize(float3(alpha_x * omega.x, alpha_y * omega.y, omega.z));

    float length_squared = v.x*v.x + v.y*v.y;
    float3 axis_1 = (length_squared > 0.0f) ? float3(-v.y, v.x, 0.0f) / sqrt(length_squared) : float3(1.0f, 0.0f, 0.0f);
    float3 axis_2 = cross(v, axis_1);

    float2 d = sample_disc(u1, u2);
    float t1 = d.x;
    float t2 = d.y;

    float s = 0.5f * (1.0f + v.z);
    t2 = (1.0f - s) * sqrt(max(1.0f - t1 * t1, 0.0f)) + s*t2;

    float3 n_h = t1*axis_1 + t2*axis_2 + sqrt(max(0.0f, 1.0f - t1*t1 - t2*t2)) * v;

    return normalize(float3(alpha_x * n_h.x, alpha_y * n_h.y, n_h.z));
}

float3 fresnel_conductor(float cos_theta_i, const float3 eta, const float3 k) {
    float cos_theta_i2 = cos_theta_i * cos_theta_i;

    float3 t1 = eta*eta + k*k;
    float3 t0 = t1 * cos_theta_i;

    float3 p2 = (t0 - (eta * (2.0f * cos_theta_i)) + float3(1.0f, 1.0f, 1.0f)) / (t0 + (eta * (2.0f * cos_theta_i)) + float3(1.0f, 1.0f, 1.0f));
    float3 s2 = (t1 - (eta * (2.0f * cos_theta_i)) + float3(cos_theta_i2, cos_theta_i2, cos_theta_i2)) / (t1 + (eta * (2.0f * cos_theta_i)) + float3(cos_theta_i2, cos_theta_i2, cos_theta_i2));

    return 0.5f * (p2 + s2);
}

float ggx_D(const float3 micro_normal, float alpha_x, float alpha_y) {
    float sx = -micro_normal.x / (micro_normal.z * alpha_x);
    float sy = -micro_normal.y / (micro_normal.z * alpha_y);

    float s1 = 1.0f + sx * sx + sy * sy;

    float cos_theta_2 = micro_normal.z * micro_normal.z;
    float cos_theta_4 = cos_theta_2 * cos_theta_2;

    return 1.0f / (s1 * s1 * PI * alpha_x * alpha_y * cos_theta_4);
}

float ggx_lambda(const float3 omega, float alpha_x, float alpha_y) {
    return 0.5f * (sqrt(1.0f + ((alpha_x * omega.x) * (alpha_x * omega.x) + (alpha_y * omega.y) * (alpha_y * omega.y)) / (omega.z * omega.z)) - 1.0f);
}
float ggx_G1(const float3 omega, float alpha_x, float alpha_y) {
    return 1.0f / (1.0f + ggx_lambda(omega, alpha_x, alpha_y));
}

float ggx_G2(const float3 omega_o, const float3 omega_i, const float3 omega_m, float alpha_x, float alpha_y) {
    bool omega_i_backfacing = dot(omega_i, omega_m) * omega_i.z <= 0.0f;
    bool omega_o_backfacing = dot(omega_o, omega_m) * omega_o.z <= 0.0f;

    if(omega_i_backfacing || omega_o_backfacing) {
        return 0.0f;
    } else {
        return 1.0f / (1.0f + ggx_lambda(omega_o, alpha_x, alpha_y) + ggx_lambda(omega_i, alpha_x, alpha_y));
    }
}

bool sample_conductor(inout float3 throughput, HitMat material, float3 omega_i, inout float3 direction_out, inout float pdf) {//Metal
    float2 rand_brdf = random(5);
    float alpha_x = material.roughness;
    float alpha_y = material.roughness;
    float3 omega_m = sample_visible_normals_ggx(omega_i, alpha_x, alpha_y, rand_brdf.x, rand_brdf.y);

    float3 omega_o = reflect(-omega_i, omega_m);

    float o_dot_m = dot(omega_o, omega_m);
    if(o_dot_m <= 0.0f) return false;

    float3 F = fresnel_conductor(o_dot_m, material.eta, material.surfaceColor);

    float D = ggx_D(omega_m, alpha_x, alpha_y);
    float G1 = ggx_G1(omega_i, alpha_x, alpha_y);

    float G2 = ggx_G2(omega_o, omega_i, omega_m, alpha_x, alpha_y);
    
    [branch]if(UseNEE) {
    pdf = G1 * D / (4.0f * omega_i.z);
    }

    throughput *= F * G2 / G1;
    direction_out = omega_o;
    return true;
}


float fresnel_dielectric(float cos_theta_i, float eta) {
    float sin_theta_o2 = eta * eta * (1.0f - cos_theta_i*cos_theta_i);
    if(sin_theta_o2 >= 1.0f) {
        return 1.0f;
    }

    float cos_theta_o = sqrt(max(1.0f - sin_theta_o2, 0.0f));

    float s = (cos_theta_i - eta * cos_theta_o) / (eta * cos_theta_o + cos_theta_i);
    float p = (eta * cos_theta_i - cos_theta_o) / (eta * cos_theta_i + cos_theta_o);

    return 0.5f * (p*p + s*s);
}

bool sample_dielectric(inout float3 throughput, HitMat material, float3 omega_i, inout float3 direction_out, float eta, inout float pdf) {//Glass
    float rand_fresnel = random(2).y;
    float2 rand_brdf = random(5);

    float alpha_x = material.roughness;
    float alpha_y = material.roughness;

    float3 omega_m = sample_visible_normals_ggx(omega_i, alpha_x, alpha_y, rand_brdf.x, rand_brdf.y);

    float F = fresnel_dielectric(abs(dot(omega_i, omega_m)), eta);

    bool reflected = rand_fresnel < F;

    float3 omega_o;
    if(reflected) {
        omega_o = 2.0f * dot(omega_i, omega_m) * omega_m - omega_i;
    } else {
        float k = 1.0f - eta*eta * (1.0f - (dot(omega_i, omega_m) * dot(omega_i, omega_m)));
        omega_o = (eta * abs(dot(omega_i, omega_m)) - sqrt(max(k, 0.0f))) * omega_m - eta * omega_i;
    }

    direction_out = omega_o;

    if(reflected ^ (omega_o.z >= 0.0f)) return false;

    float D = ggx_D(omega_m, alpha_x, alpha_y);
    float G1 = ggx_G1(omega_i, alpha_x, alpha_y);
    float G2 = ggx_G2(omega_o, omega_i, omega_m, alpha_x, alpha_y);

    float i_dot_m = abs(dot(omega_i, omega_m));
    float o_dot_m = abs(dot(omega_o, omega_m));

    [branch]if(!UseNEE) {
        if(!reflected) {
            throughput *= eta*eta;
        }
    }else {
        if(reflected) {
            pdf = F * G1 * D / (4.0f * omega_i.z);
        } else {
            float temp = eta * i_dot_m + o_dot_m;
            pdf = (1.0f - F) * G1 * D * i_dot_m * o_dot_m / (omega_i.z * (temp * temp));
            throughput *= eta*eta;   
        }
    }
    
    throughput *= G2 / G1;

    direction_out = omega_o;

    return true;
}

inline void orthonormal_basis(const float3 normal, inout float3 tangent, inout float3 binormal) {
    float sign2 = (normal.z >= 0.0f) ? 1.0f : -1.0f;
    float a = -1.0f / (sign2 + normal.z);
    float b = normal.x * normal.y * a;

    tangent  = float3(1.0f + sign2 * normal.x * normal.x * a, sign2 * b, -sign2 * normal.x);
    binormal = float3(b, sign2 + normal.y * normal.y * a, -normal.y);
}

inline float3 local_to_world(const float3 vec, const float3 tangent, const float3 binormal, const float3 normal) {
    return float3(
        tangent.x * vec.x + binormal.x * vec.y + normal.x * vec.z,
        tangent.y * vec.x + binormal.y * vec.y + normal.y * vec.z,
        tangent.z * vec.x + binormal.z * vec.y + normal.z * vec.z
    );
}

float3 sample_henyey_greenstein(const float3 omega, float g, float u1, float u2) {
    float cos_theta;
    if (abs(g) < 1e-3f) {
        // Isotropic case
        cos_theta = 1.0f - 2.0f * u1;
    } else {
        float sqr_term = (1.0f - g * g) / (1.0f + g - 2.0f * g * u1);
        cos_theta = -(1.0f + g * g - sqr_term * sqr_term) / (2.0f * g);
    }
    float sin_theta = sqrt(max(1.0f - cos_theta * cos_theta, 0.0f));

    float phi = (PI * 2.0f) * u2;
    float sin_phi, cos_phi;
    sincos(phi, sin_phi, cos_phi);

    float3 direction = float3(
        sin_theta * cos_phi,
        sin_theta * sin_phi,
        cos_theta
    );

    float3 v1, v2;
    orthonormal_basis(omega, v1, v2);

    return local_to_world(direction, v1, v2, omega);
}

bool VolumetricScatter(inout float3 throughput, RayHit hit, inout Ray ray, inout float3 Pos, HitMat hitDat) {
    float3 SigmaS = hitDat.surfaceColor;
    float3 SigmaA = hitDat.eta;

    bool medium_can_scatter = (SigmaS.x + SigmaS.y + SigmaS.z) > 0.0f;

    if(medium_can_scatter) {
        float2 rand_scatter = random(3);
        float2 rand_phase = random(5);

        float3 sigma_t = SigmaA + SigmaS;

        float throughput_sum = throughput.x + throughput.y + throughput.z;
        float3 wavelength_pdf = throughput / throughput_sum;

        float sigma_t_used_for_sampling;
        if(rand_scatter.x * throughput_sum < throughput.x) {
            sigma_t_used_for_sampling = sigma_t.x;
        } else if(rand_scatter.x * throughput_sum < throughput.x + throughput.y) {
            sigma_t_used_for_sampling = sigma_t.y;
        } else {
            sigma_t_used_for_sampling = sigma_t.z;
        }

        float scatter_distance = -log(rand_scatter.y) / sigma_t_used_for_sampling;
        float dist = min(scatter_distance, hit.t);
        float3 transmittance = float3(
            exp(-sigma_t.x * dist),
            exp(-sigma_t.y * dist),
            exp(-sigma_t.z * dist)
            );

        if(scatter_distance < hit.t) {
            float3 pdf = wavelength_pdf * sigma_t * transmittance;
            throughput *= SigmaS * transmittance / (pdf.x + pdf.y + pdf.z);

            float3 direction_out = sample_henyey_greenstein(-ray.direction, hitDat.roughness, rand_phase.x, rand_phase.y);

            float3 ray_origin = ray.origin;
            ray.origin = ray_origin + scatter_distance * ray.direction;
            Pos = ray.origin;
            ray.direction = direction_out;
            return true;
        } else {
            float3 pdf = wavelength_pdf * transmittance;
            throughput *= transmittance / (pdf.x + pdf.y + pdf.z);
            return false;
        }
    }
    return false;
}

float3 SunDir;

Texture3D ScatterTex;
Texture3D MieTex;
SamplerState linearClampSampler;

static uint ScatteringTexRSize = 32;
static uint ScatteringTexMUSize = 128;
static uint ScatteringTexMUSSize = 32;
static uint ScatteringTexNUSize = 8;
static float bottom_radius = 6371.0f;
static float top_radius = 6403.0f;

float RayleighPhaseFunction(float nu) {
  float k = 3.0 / (16.0 * PI);
  return k * (1.0 + nu * nu);
}
float GetTextureCoordFromUnitRange(float x, int texture_size) {
    return 0.5f / (float)texture_size + x * (1.0f - 1.0f / (float)texture_size);
}

float MiePhaseFunction(float g, float nu) {
  float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
  return k * (1.0 + nu * nu) / pow(1.0 + g * g - 2.0 * g * nu, 1.5);
}

float GetUnitRangeFromTextureCoord(float u, int texture_size) {
    return (u - 0.5f / (float)texture_size) / (1.0f - 1.0f / (float)texture_size);
}

float DistanceToTopAtmosphereBoundary(float r, float mu) {
    float discriminant = r * r * (mu * mu - 1.0f) + top_radius * top_radius;
    return max(-r * mu + sqrt(max(discriminant, 0.0f)), 0.0f);
}

float4 GetScatteringTextureUvwzFromRMuMuSNu(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
    float H = sqrt(top_radius * top_radius - bottom_radius * bottom_radius);
    float rho = sqrt(max(r * r - bottom_radius * bottom_radius, 0.0f));
    float u_r = GetTextureCoordFromUnitRange(rho / H, ScatteringTexRSize);

    float r_mu = r * mu;
    float discriminant = r_mu * r_mu - r * r + bottom_radius * bottom_radius;
    float u_mu;
    if(ray_r_mu_intersects_ground) {
        float d = -r_mu - sqrt(max(discriminant, 0.0f));
        float d_min = r - bottom_radius;
        float d_max = rho;
        u_mu = 0.5f - 0.5f * GetTextureCoordFromUnitRange((d_max == d_min) ? 0.0f : (d - d_min) / (d_max - d_min), ScatteringTexMUSize / 2);
    } else {
        float d = -r_mu + sqrt(max(discriminant + H * H, 0.0f));
        float d_min = top_radius - r;
        float d_max = rho + H;
        u_mu = 0.5f + 0.5f * GetTextureCoordFromUnitRange((d - d_min) / (d_max - d_min), ScatteringTexMUSize / 2);
    }

    float d = DistanceToTopAtmosphereBoundary(bottom_radius, mu_s);
    float d_min = top_radius - bottom_radius;
    float d_max = H;
    float a = (d - d_min) / (d_max - d_min);
    float D = DistanceToTopAtmosphereBoundary(bottom_radius, -0.2f);
    float A = (D - d_min) / (d_max - d_min);

    float u_mu_s = GetTextureCoordFromUnitRange(max(1.0f - a / A, 0.0f) / (1.0f + a), ScatteringTexMUSSize);

    float u_nu = (nu + 1.0f) / 2.0f;
    return float4(u_nu, u_mu_s, u_mu, u_r);
}

float3 GetScattering(Texture3D Tex, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
  float4 uvwz = GetScatteringTextureUvwzFromRMuMuSNu(r, mu, mu_s, nu, ray_r_mu_intersects_ground);
  float tex_coord_x = uvwz.x * (float)(ScatteringTexNUSize - 1);
  float tex_x = floor(tex_coord_x);
  float lerp2 = tex_coord_x - tex_x;
  float3 uvw0 = float3((tex_x + uvwz.y) / (float)ScatteringTexNUSize,
      uvwz.z, uvwz.w);
  float3 uvw1 = float3((tex_x + 1.0 + uvwz.y) / (float)ScatteringTexNUSize,
      uvwz.z, uvwz.w);
  return float3(Tex.SampleLevel(linearClampSampler, uvw0, 0).xyz * (1.0 - lerp2) + Tex.SampleLevel(linearClampSampler, uvw1, 0).xyz * lerp2);
}

float3 GetScattering(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
    float3 rayleigh = GetScattering(ScatterTex, r, mu, mu_s, nu, ray_r_mu_intersects_ground);
    float3 mie = GetScattering(MieTex, r, mu, mu_s, nu, ray_r_mu_intersects_ground);
    return rayleigh * RayleighPhaseFunction(nu) + mie * MiePhaseFunction(-0.2f, nu);
}

float3 CalculateSkyBox(float3 rayOrig, float3 rayDir, RayHit hit) {
    rayOrig /= 1000.0f;
    rayOrig.y += bottom_radius;
    float muStartPos = dot(rayOrig, rayDir) / rayOrig.y;
    float nuStartPos = dot(rayDir, normalize(SunDir));
    float musStartPos = dot(rayOrig, normalize(SunDir)) / rayOrig.y;
    return GetScattering(rayOrig.y, muStartPos, musStartPos, nuStartPos, false);
}

float2 sample_triangle(float u1, float u2) {
    if (u2 > u1) {
        u1 *= 0.5f;
        u2 -= u1;
    } else {
        u2 *= 0.5f;
        u1 -= u2;
    }
    return float2(u1, u2);
}

bool evaldiffuse(const float3 to_light, float cos_theta_o, inout float3 bsdf, inout float pdf) {
    if (cos_theta_o <= 0.0f) return false;

    bsdf = float3(cos_theta_o * ONE_OVER_PI, cos_theta_o * ONE_OVER_PI, cos_theta_o * ONE_OVER_PI);
    pdf  = cos_theta_o * ONE_OVER_PI;

    return (pdf > 0 || pdf < 0 || pdf == 0);
}

bool evalconductor(HitMat material, const float3 to_light, float cos_theta_o, inout float3 bsdf, inout float pdf, float3 omega_i) {
    if (cos_theta_o <= 0.0f) return false;

    float3 omega_o = to_light;
    float3 omega_m = normalize(omega_o + omega_i);

    float o_dot_m = dot(omega_o, omega_m);
    if (o_dot_m <= 0.0f) return false;

    float alpha_x = material.roughness;
    float alpha_y = material.roughness;

    float3 F  = fresnel_conductor(o_dot_m, material.eta, material.surfaceColor);
    float  D  = ggx_D (omega_m, alpha_x, alpha_y);
    float  G1 = ggx_G1(omega_i, alpha_x, alpha_y);
    float  G2 = ggx_G2(omega_o, omega_i, omega_m, alpha_x, alpha_y);

    pdf  =     G1 * D / (4.0f * omega_i.z);
    bsdf = F * G2 * D / (4.0f * omega_i.z); // BRDF * cos(theta_o)

    return (pdf > 0 || pdf < 0 || pdf == 0);
}

bool evaldielectric(HitMat material, const float3 to_light, float cos_theta_o, inout float3 bsdf, inout float pdf, float3 omega_i) {
    float3 omega_o = to_light;

    bool reflected = omega_o.z >= 0.0f; // Same sign means reflection, alternate signs means transmission

    float3 omega_m;
    if (reflected) {
        omega_m = normalize(omega_i + omega_o);
    } else {
        omega_m = normalize(material.eta.x * omega_i + omega_o);
    }
    omega_m *= sign(omega_m.z);

    float i_dot_m = abs(dot(omega_i, omega_m));
    float o_dot_m = abs(dot(omega_o, omega_m));

    float alpha_x = material.roughness;
    float alpha_y = material.roughness;

    float F  = fresnel_dielectric(i_dot_m, material.eta.x);
    float D  = ggx_D (omega_m, alpha_x, alpha_y);
    float G1 = ggx_G1(omega_i, alpha_x, alpha_y);
    float G2 = ggx_G2(omega_o, omega_i, omega_m, alpha_x, alpha_y);

    if (reflected) {
        pdf = F * G1 * D / (4.0f * omega_i.z);
        float base = F * G2 * D / (4.0f * omega_i.z);
        bsdf = float3(base, base, base); // BRDF times cos(theta_o)
    } else {
        if (F >= 0.999f) return false; // TIR, no transmission possible

        pdf = (1.0f - F) * G1 * D * i_dot_m * o_dot_m / (omega_i.z * (material.eta.x * i_dot_m + o_dot_m) * (material.eta.x * i_dot_m + o_dot_m));
        float base2 = (1.0f - F) * G2 * D * i_dot_m * o_dot_m / (omega_i.z * (material.eta.x * i_dot_m + o_dot_m) * (material.eta.x * i_dot_m + o_dot_m));
        bsdf = material.eta.x * material.eta.x * float3(base2, base2, base2); // BRDF times cos(theta_o)
    }

    return (pdf > 0 || pdf < 0 || pdf == 0);
}

inline float power_heuristic(float pdf_f, float pdf_g) {
    return (pdf_f * pdf_f) / (pdf_f * pdf_f + pdf_g * pdf_g); // Power of 2 hardcoded, best empirical results according to Veach
}

inline float luminance(const float r, const float g, const float b) {
    return 0.299f * r + 0.587f * g + 0.114f * b;
}

void sampleEquiAngular( float u, float maxDistance, float3 rOrigin, float3 rDirection, float3 lightPos, inout float dist, inout float pdf )
{
    // get coord of closest point to light along (infinite) ray
    float delta = clamp(dot(lightPos - rOrigin, rDirection), 0.0, 1.0);
    
    // get distance this point is from light
    float D = distance(rOrigin + delta * rDirection, lightPos);

    // get angle of endpoints
    float thetaA = atan((0.0 - delta) / D);
    float thetaB = atan((maxDistance - delta) / D);

    // take sample
    float t = D * tan( lerp(thetaA, thetaB, u) );
    dist = delta + t;
    pdf = D / ( (thetaB - thetaA) * (D * D + t * t) );
}



static const int NumSamples = 8;


void calcFinalColor(inout Ray ray, inout ColData Color, const HitMat hitDat, RayHit hit, uint2 Uv, inout bool terminated, float2 NormalUV, bool HitVoxel) {//main function

    float3 pos = ray.direction * hit.t + ray.origin;
    float3 PrevDirection = ray.direction;
    float3 PrevOrigin = ray.origin;


    const float3 SigmaS = float3(3.996f, 3.996f, 3.996f) * 0.001f;
    const float3 SigmaA = float3(1.0f, 2.0f, 4.4f) * 0.001f;
    const float3 sigma_t = SigmaA + SigmaS;
    if(AllowVolumetrics)  Color.throughput *= (exp( -((hit.t) * sigma_t) ));
    const float3 PrevThroughput = Color.throughput;
    const uint index = hit.triangle_id;
    float3 Geomnorm = (DoVoxels || !HitVoxel) ? normalize(mul(_MeshData[hit.mesh_id].Inverse, float4(AggTris[index].norm0 + hit.u * AggTris[index].normedge1 + hit.v * AggTris[index].normedge2, 0.0f)).xyz) : float3(0,0,0);
    if(DoVoxels && HitVoxel) {
        Geomnorm = float3(1,0,0);
        float3 VoxPos = Octree[index].Center + 0.5f;
        float3 initdiff = mul(_MeshData[hit.mesh_id].Transform, float4(pos, 1)).xyz - VoxPos;
        float Greatest = max(max(abs(initdiff.x), abs(initdiff.y)), abs(initdiff.z));
        if(Greatest == abs(initdiff.y)) Geomnorm = float3(0,1,0);
        if(Greatest == abs(initdiff.z)) Geomnorm = float3(0,0,1);
        Geomnorm = normalize(mul(_MeshData[hit.mesh_id].Inverse, float4(Geomnorm, 0)).xyz);

    }

    bool GotFlipped = false;
    [branch]if(dot(ray.direction, Geomnorm) >= 0.0f) {
        Geomnorm *= -1;
        GotFlipped = true;
    }

    float3 norm = Geomnorm;
    [branch]if(NormalUV.x != -1) {
         float3 LocalTan = normalize(mul(_MeshData[hit.mesh_id].Inverse, float4(AggTris[index].tan0 + hit.u * AggTris[index].tanedge1 + hit.v * AggTris[index].tanedge2, 0.0f)).xyz);
        float3 LocalBinorm = normalize(cross(Geomnorm, LocalTan));
        float2 InputNormal = _NormalAtlas.SampleLevel(sampler_NormalAtlas, NormalUV,0).ag;
        InputNormal.y = pow(InputNormal.y, 0.4545f);
        float3 LocalNormIN = float3((2.0f * InputNormal.xy - 1.0f),0.0f);
        LocalNormIN.z = 1.0 - 0.5 * dot(LocalNormIN, LocalNormIN );
        norm = normalize(mul(normalize(LocalNormIN), float3x3(LocalTan, LocalBinorm, Geomnorm)));
        norm = clamp(norm, -1, 1);
        if(abs(norm.x) == abs(norm.y) == abs(norm.z)) norm = Geomnorm;
    }

    if(CurBounce == 0) {//Setting textures for denosier to use
        TempPosTex[Uv] = float4(pos, 1.0f);
        TempNormTex[Uv] = float4(norm, length(pos - ray.origin));
        if(hitDat.MatType != 2) {
            TempAlbedoTex[Uv] = float4((AllowVolumetrics ? PrevThroughput : 1.0f) * hitDat.surfaceColor, 1.0f);
        } else {
            TempAlbedoTex[Uv] = float4(1.0f, 1.0f, 1.0f, 1.0f);
        }
    }

    [branch]if(hitDat.emmis > 0.0f) {//if we hit a light, this ray is done
        [flatten]if(CurBounce == 0) {
            Color.Direct = hitDat.emmis;
        } else if(CurBounce == 1) {
            Color.Direct += hitDat.surfaceColor * (hitDat.emmis);
        } else {
            Color.Indirect += Color.throughput * hitDat.emmis * hitDat.surfaceColor;
        }
        return;
    }
    float3 throughput = Color.throughput;

    float3 tempraydir = float3(0.0f, 0.0f, 0.0f);
    bool valid = true;
    float pdf = 0.0f;

    float3 omega_i = mul(GetTangentSpace(norm), -ray.direction);

    [branch]switch(hitDat.MatType) {//Switch between different materials
        case 1://Conductor material(metal)
            valid = sample_conductor(throughput, hitDat, omega_i, tempraydir, pdf);
            ray.direction = normalize(mul(tempraydir, GetTangentSpace(norm)));    
        break;
        case 2://Dielectric material(glass)
            float eta = hitDat.eta.x;
            if(!GotFlipped) {
                norm *= -1;
                Geomnorm *= -1;
                eta = rcp(eta);
            } else {
                norm *= -1;
                Geomnorm *= -1;
                throughput *= exp(-hitDat.surfaceColor * hit.t);//Beers law
            }
            valid = sample_dielectric(throughput, hitDat, mul(GetTangentSpace(-norm), -ray.direction), tempraydir, eta, pdf);
            ray.direction = normalize(mul(tempraydir, GetTangentSpace(-norm)));
        break;
        case 3://"Glossy" material
            ray.direction = normalize(mul(sample(pdf), GetTangentSpace(norm)) * hitDat.roughness + reflect(ray.direction, norm));
            throughput *= hitDat.surfaceColor;
        break;
        case 4://mask material
                Geomnorm *= -1;
        break;
        case 5://"Volumetric" material
            if(GotFlipped) {
                if(VolumetricScatter(throughput, hit, ray, pos, hitDat)) {
                    norm = -norm;
                    Geomnorm = -Geomnorm;
                }
            } else {
                ray.direction = ray.direction;
                norm = -norm;
                Geomnorm = -Geomnorm;
            }
        break;
        case 6://SSS
                        
                if(GotFlipped) {
                    norm = -norm;
                    Geomnorm = -Geomnorm;
                    float tempdist = hit.t * 24.0f;
                    throughput *= exp(-hitDat.eta * tempdist * tempdist * tempdist * 2.0f);//Beers law
                } else {
                    pos -= Geomnorm  * 0.005f;
                    throughput *= hitDat.surfaceColor;
                }
                float3 modifier = 0.5f * normalize(mul(sample(pdf, 14), GetTangentSpace(-norm)));
                ray.direction = normalize(normalize(mul(sample(pdf), GetTangentSpace(norm))) + ( modifier));

        break;
        case 7://DiffTrans
            if(random(10).x > 0.5f) {
                    norm = -norm;
                    Geomnorm = -Geomnorm;
                     throughput *= hitDat.surfaceColor;
                } else {
                     throughput *= hitDat.surfaceColor * 2.0f;
                    if(GotFlipped) throughput *= exp(-hitDat.surfaceColor * hit.t);//Beers law
                }
                ray.direction = normalize(normalize(mul(sample(pdf), GetTangentSpace(norm))) * (1.0f - hitDat.roughness) + hitDat.roughness * ray.direction);
        break;
        default:
            ray.direction = normalize(mul(sample(pdf), GetTangentSpace(norm)));
            throughput *= hitDat.surfaceColor;
        break;
    }
    if(!valid) return;//If the ray failed, we have no choice but to terminate this path
    ray.origin = Geomnorm * 0.001f + pos;//Offset the ray origin so we dont self intersect with the triangle we just bounced off of
   // _DebugTex[Uv] = float4(ray.direction,1);
   // return;
    [branch]if(UseNEE || AllowVolumetrics) {//Next event estimation
        bool UseUnityLight = true;//(unitylightcount != 0) ? (LightMeshCount != 0) ? (random(11).x <= (_UnityLights[unitylightcount - 1].TotalEnergy / (_UnityLights[unitylightcount - 1].TotalEnergy + _LightMeshes[LightMeshCount - 1].TotalEnergy))) : true : false;//Choose whether to sample unity lights or mesh lights based off which is more powerful
        float3 pos2;
        float3 LightNorm;
        int triindex;
        bool IsAboveHorizon = true;
        bool IsDirectional = false;
        float MeshChance = 0.0f;
        if(UseUnityLight) {
            triindex = ((Uv.x > screen_width / 2) ? CurrentReservoir[Uv.x + Uv.y * screen_width].y : SelectUnityLight());
            LightData Light = _UnityLights[triindex];
            [branch]switch(Light.Type) {
                default:
                    pos2 = Light.Position;
                    LightNorm = normalize(ray.origin - pos2);
                break;
                case 1:
                    pos2 = ray.origin - Light.Direction;
                    LightNorm = Light.Direction;
                    IsAboveHorizon = (LightNorm.y <= 0.0f);
                    IsDirectional = true;
                break;
                case 2:
                    pos2 = Light.Position;
                    LightNorm = Light.Direction;
                    IsAboveHorizon = false;
                break;
            }
            MeshChance = (_UnityLights[triindex].energy / (_UnityLights[unitylightcount - 1].TotalEnergy + _LightMeshes[LightMeshCount - 1].TotalEnergy));
        } else {
            int MeshIndex = SelectLightMesh();
            triindex = SelectLight(MeshIndex);
            TrianglePos CurTri = triangle_get_positions2(triindex);
            float2 rand_triangle = random(4);
            float2 CurUv = sample_triangle(rand_triangle.x, rand_triangle.y);
            pos2 = mul(_LightMeshes[MeshIndex].Inverse, float4(CurTri.pos0 + CurUv.x * CurTri.posedge1 + CurUv.y * CurTri.posedge2, 0.0f)).xyz + _LightMeshes[MeshIndex].Center;
            LightNorm = normalize(mul(_LightMeshes[MeshIndex].Inverse, float4(LightTriangles[triindex].Norm, 0.0f)).xyz);
            MeshChance = (LightTriangles[triindex].energy / (_UnityLights[unitylightcount - 1].TotalEnergy + _LightMeshes[LightMeshCount - 1].TotalEnergy));//unused, needs more testing
        }
        float3 to_light = pos2 - ray.origin;

        float distance_to_light_squared = dot(to_light, to_light);
        float distance_to_light = sqrt(max(distance_to_light_squared, 0.0f));

        to_light = to_light / distance_to_light;
        float Attenuation = 1.0f;
        if(!IsDirectional && !IsAboveHorizon) {
            float theta = dot(to_light, -LightNorm);
            if(theta > _UnityLights[triindex].SpotAngle.x) {
                IsAboveHorizon = true;
                float epsilon = _UnityLights[triindex].SpotAngle.x - _UnityLights[triindex].SpotAngle.y;
                Attenuation = clamp((theta - _UnityLights[triindex].SpotAngle.x) / epsilon, 0.0f, 1.0f);
            }
        }
        
        bool validbsdf = false;
        float3 bsdf_value = 0.0f;
        float bsdf_pdf = 0.0f;

        float cos_theta_light = abs(dot(to_light, LightNorm));
        float cos_theta_hit = dot(to_light, norm);
        [branch]switch(hitDat.MatType) {//Switch between different materials
            case 1:
                validbsdf = evalconductor(hitDat, mul(GetTangentSpace(LightNorm), -to_light), cos_theta_hit, bsdf_value, bsdf_pdf, omega_i);
            break;
            default:
                validbsdf = evaldiffuse(to_light, cos_theta_hit, bsdf_value, bsdf_pdf);
            break;
            case 2:
                validbsdf = evaldielectric(hitDat, mul(GetTangentSpace(LightNorm), -to_light), cos_theta_hit, bsdf_value, bsdf_pdf, omega_i);
            break;
            case 4:
                validbsdf = false;
            break;
            case 5:
                validbsdf = true;
            break;
            case 6:
                validbsdf = evaldiffuse(to_light, cos_theta_hit, bsdf_value, bsdf_pdf);
            break;
            case 7:
                validbsdf = evaldiffuse(to_light, cos_theta_hit, bsdf_value, bsdf_pdf);
            break;
        }

        if(validbsdf && IsAboveHorizon && UseNEE) {
            float G = max(0.0, dot(norm, to_light)) * max(0.0, -dot(to_light, LightNorm)) / distance_to_light_squared;
            if(G > 0.0f) {
                float light_pdf;
                float3 Radiance;
                if(UseUnityLight) {
                    Radiance = _UnityLights[triindex].Radiance / MeshChance;
                    light_pdf = luminance(Radiance.x, Radiance.y, Radiance.z) * distance_to_light_squared / (cos_theta_light * (_UnityLights[unitylightcount - 1].TotalEnergy));
                    Radiance /= (_UnityLights[unitylightcount - 1].TotalEnergy / (_UnityLights[unitylightcount - 1].TotalEnergy + _LightMeshes[LightMeshCount - 1].TotalEnergy));
                } else {
                    Radiance = LightTriangles[triindex].radiance / MeshChance;
                    light_pdf = luminance(Radiance.x, Radiance.y, Radiance.z) * distance_to_light_squared / (cos_theta_light * _LightMeshes[LightMeshCount - 1].TotalEnergy);
                    Radiance /= (_LightMeshes[LightMeshCount - 1].TotalEnergy / (_UnityLights[unitylightcount - 1].TotalEnergy + _LightMeshes[LightMeshCount - 1].TotalEnergy));
                }

                float w = power_heuristic(light_pdf, bsdf_pdf);//For some reason 1 works way better for point lights
                float3 Illum = ((CurBounce == 0) ? PrevThroughput : throughput) * Radiance  * bsdf_value * ((Uv.x > screen_width / 2) ? w : w)/ light_pdf;//throughput * G * ((Radiance * w * bsdf_value) / light_pdf) * Attenuation;
                float maxillum = max(max(Illum.x, Illum.y), Illum.z);
              //  if(maxillum > random(9).y) {//NEE russian roulette, massively improves performance while giivng the same result
                    uint index3;//Congrats we shoot a shadow ray for NEE
                  InterlockedAdd(BufferSizes[CurBounce].shadow_rays, 1, index3);

                    ShadowRaysBuffer[index3].origin = ray.origin;
                    ShadowRaysBuffer[index3].direction = to_light;
                    ShadowRaysBuffer[index3].t = (IsDirectional) ? 10000.0f : distance_to_light - 2.0f * EPSILON;
                    ShadowRaysBuffer[index3].illumination = Illum;// * rcp(saturate(maxillum));
                    ShadowRaysBuffer[index3].PixelIndex = Uv.y * screen_width + Uv.x;
                    ShadowRaysBuffer[index3].IsNotFog = true;
                    ShadowRaysBuffer[index3].HitMesh = true;
                //}

            }
        }
        [branch]if(AllowVolumetrics) {


            float3 to_light;
            float3 Radiance;
            if(UseUnityLight) { 
                Radiance = _UnityLights[triindex].Radiance / MeshChance;
                LightData Light = _UnityLights[triindex];
                pos2 = (IsDirectional) ? PrevOrigin - Light.Direction * 15000.0f : Light.Position;
                LightNorm = Light.Direction;
            } else {
                Radiance = LightTriangles[triindex].radiance / MeshChance;
            }

            float dist;
            float pdf;
            sampleEquiAngular(random(14).x, hit.t, PrevOrigin, PrevDirection, pos2, dist, pdf );
            float3 SamplePoint = PrevOrigin + dist * PrevDirection;
            float light_pdf;
            if(!UseUnityLight)  {
                to_light = pos2 - SamplePoint;
                light_pdf = luminance(Radiance.x, Radiance.y, Radiance.z) * distance_to_light_squared / (cos_theta_light * _LightMeshes[LightMeshCount - 1].TotalEnergy);
            } else {
                Radiance *= rcp(1.0f - (_LightMeshes[LightMeshCount - 1].TotalEnergy / _UnityLights[unitylightcount - 1].TotalEnergy));
                light_pdf = luminance(Radiance.x, Radiance.y, Radiance.z) * distance_to_light_squared / (cos_theta_light * (_UnityLights[unitylightcount - 1].TotalEnergy));
                to_light = (IsDirectional) ? (SamplePoint - LightNorm * 2.0f) - SamplePoint : pos2 - SamplePoint;
            }
             float distance_to_light_squared = dot(to_light, to_light);
             float distance_to_light = sqrt(max(dot(to_light, to_light),0.0001f));
             to_light = to_light / distance_to_light;

             if(!IsDirectional) LightNorm = -normalize(SamplePoint - pos2);

            float cos_theta_light = abs(dot(to_light, -normalize(SamplePoint - pos2)));
            float cos_theta_hit = dot(to_light, -LightNorm);

            float3 transmittance = exp( -((distance_to_light + dist) * sigma_t) );
            float geomTerm = 1.0f / (distance_to_light_squared);
            float w = power_heuristic(light_pdf, pdf);
            float3 Illum = PrevThroughput * w * Radiance * geomTerm * transmittance / (light_pdf) * VolumeDensity;// * (exp( -((hit.t) * hitDat.surfaceColor) ))
            float maxillum = max(max(Illum.x, Illum.y), Illum.z);
            if(maxillum > random(9).y) {//NEE russian roulette, massively improves performance while giivng the same result
                uint index4;//Congrats we shoot a shadow ray for NEE
                InterlockedAdd(BufferSizes[CurBounce].shadow_rays, 1, index4);

                ShadowRaysBuffer[index4].origin = SamplePoint;
                ShadowRaysBuffer[index4].direction = to_light;
                ShadowRaysBuffer[index4].t = IsDirectional ? 100000.0f : distance_to_light - 2.0f * EPSILON;
                ShadowRaysBuffer[index4].illumination =  Illum * rcp(saturate(maxillum));// * (CurBounce == 0) ? rcp(TempAlbedoTex[Uv].xyz) : 1.0f;
                ShadowRaysBuffer[index4].PixelIndex = Uv.y * screen_width + Uv.x;
                ShadowRaysBuffer[index4].IsNotFog = false;
                ShadowRaysBuffer[index4].HitMesh = true;
            }

        }
    }
    if(UseRussianRoulette) {
        float3 AdjustedCol = throughput * TempAlbedoTex[Uv].xyz;
        float p = saturate(max(AdjustedCol.x, max(AdjustedCol.y, AdjustedCol.z)));
       if(random(2).x > p && CurBounce > 0)//Simple Russian Roulette
         return;
       if(CurBounce > 0)
           throughput *= rcp(p);//rcp is a slightly faster but less accurate version of 1 / p, I decided the inaccuracy was worth the performance bump
    }
    Color.throughput = throughput;

    uint index2;//Congrats, the ray will continue its path
    InterlockedAdd(BufferSizes[CurBounce + 1].tracerays, 1, index2);
    GlobalRays1[index2].origin = ray.origin;
    GlobalRays1[index2].direction = ray.direction;
    GlobalRays1[index2].PixelIndex = Uv.x + Uv.y * screen_width;
    
    set(index2, hit);
    terminated = false;//identifier so we dont write to output before the ray ends
}

[numthreads(8,8,1)]
void kernel_shade () {

    uint index;
    InterlockedAdd(BufferSizes[CurBounce].shade_rays, 1, index);
    if(BufferSizes[CurBounce].shade_rays >= BufferSizes[CurBounce].tracerays) return;
    int PixIndex = GlobalRays2[index].PixelIndex;
    uint2 TempUv = uint2(PixIndex % screen_width, PixIndex / screen_width);
    pixel_index = PixIndex;//TempUv is the origional screen coordinates of the ray

    Ray ray;
    RayHit bestHit = get2(index);
    ray.origin = GlobalRays2[index].origin;
    ray.direction = GlobalRays2[index].direction;
    ray.direction_inv = float3(0.0f, 0.0f, 0.0f);//We dont need to calculate this, but we do need to give it some value or Unity complains

    ColData Color = GlobalColors[pixel_index];
    if(bestHit.t > 1000000.0) {//if ray goes into the void, sample skybox
        float3 SkyColAcc;
        #ifdef UseSkyBox
            float theta = acos(ray.direction.y) / -PI;
            float phi = atan2(ray.direction.x, -ray.direction.z) / -PI * 0.5f;
            float3 sky = _SkyboxTexture.SampleLevel(sampler_SkyboxTexture, float2(phi, theta), 0).xyz;
            if(CurBounce == 0) {//Seperated into direct and indirect channels
                Color.Direct = sky;
            } else if(CurBounce == 1) {
                Color.Direct += sky;
            } else {
                Color.Indirect += Color.throughput * sky;
            }
            SkyColAcc = Color.throughput * sky;
        #else
            float3 SkyBoxCol = CalculateSkyBox(ray.origin, ray.direction, bestHit);
            float Sun = (ray.direction.y >= 0) ? pow(max(dot(-SunDir, -ray.direction), 0.0f), 140.0f) : 0.0f;
            if(CurBounce == 0) {//Seperated into direct and indirect channels
                Color.Direct = (SkyBoxCol * 12.0f) + Sun;
            } else if(CurBounce == 1) {
                Color.Direct += (SkyBoxCol * 12.0f) + Sun;
            } else {
                Color.Indirect += Color.throughput * (SkyBoxCol * 12.0f) + Sun;
            }
            SkyColAcc = Color.throughput * (SkyBoxCol * 12.0f) + Sun;
        #endif
        GlobalColors[pixel_index] = Color;
        if(CurBounce == 0) {
            TempAlbedoTex[TempUv] = float4(SkyColAcc, 1.0f);
            TempPosTex[TempUv] = float4(0.0f, 0.0f, 0.0f, 0.0f);
        }
        return;
    }

    int MaterialIndex = (GlobalRays2[index].HitVoxel) ? (_MeshData[bestHit.mesh_id].MaterialOffset + Octree[bestHit.triangle_id].node.x) : (_MeshData[bestHit.mesh_id].MaterialOffset + AggTris[bestHit.triangle_id].MatDat);

    float2 BaseUv = AggTris[bestHit.triangle_id].tex0 * (1.0f - bestHit.u - bestHit.v) + AggTris[bestHit.triangle_id].texedge1 * bestHit.u + AggTris[bestHit.triangle_id].texedge2 * bestHit.v;
    float2 Uv = fmod(BaseUv + 100.0f, float2(1.0f, 1.0f)) * (_Materials[MaterialIndex].AlbedoTex.xy - _Materials[MaterialIndex].AlbedoTex.zw) + _Materials[MaterialIndex].AlbedoTex.zw;
    float2 NormalUV = (_Materials[MaterialIndex].HasNormalTex == 1) ? fmod(BaseUv + 100.0f, float2(1.0f, 1.0f)) * (_Materials[MaterialIndex].NormalTex.xy - _Materials[MaterialIndex].NormalTex.zw) + _Materials[MaterialIndex].NormalTex.zw : float2(-1,-1);
    HitMat hitmat = CreateHitMat();//Transfer Material properties
    MaterialData TempMat = _Materials[MaterialIndex];
    float4 BaseCol = (TempMat.HasAlbedoTex > 0) ? _TextureAtlas.SampleLevel(sampler_TextureAtlas, Uv, 0) : float4(TempMat.BaseColor, 1.0f);
    hitmat.surfaceColor = BaseCol.xyz;
    hitmat.emmis = TempMat.emmissive;
    hitmat.roughness = TempMat.roughness;
    hitmat.MatType = TempMat.MatType;
    hitmat.eta = TempMat.eta;

    if(TempMat.HasMetallicTex > 0 && hitmat.MatType != 2) {
        float2 MetallicUV = fmod(BaseUv + 100.0f, float2(1.0f, 1.0f)) * (_Materials[MaterialIndex].MetallicTex.xy - _Materials[MaterialIndex].MetallicTex.zw) + _Materials[MaterialIndex].MetallicTex.zw;
        float3 MetallicCol = _MetallicAtlas.SampleLevel(sampler_MetallicAtlas, MetallicUV, 0).xyz;
        if(MetallicCol.x > 0.001f) {
            hitmat.surfaceColor += 0.001f;
            hitmat.MatType = 1;
        }
    }
    if(TempMat.HasRoughnessTex > 0) {
        float2 RoughnessUV = fmod(BaseUv + 100.0f, float2(1.0f, 1.0f)) * (_Materials[MaterialIndex].RoughnessTex.xy - _Materials[MaterialIndex].RoughnessTex.zw) + _Materials[MaterialIndex].RoughnessTex.zw;
        float3 RoughnessCol = _RoughnessAtlas.SampleLevel(sampler_RoughnessAtlas, RoughnessUV, 0).xyz;
        hitmat.roughness = pow(RoughnessCol.x * RoughnessCol.x, 0.4545f);
    }
    if(TempMat.HasEmissiveTex > 0) {
        float2 EmissionUV = fmod(BaseUv + 100.0f, float2(1.0f, 1.0f)) * (_Materials[MaterialIndex].EmissiveTex.xy - _Materials[MaterialIndex].EmissiveTex.zw) + _Materials[MaterialIndex].EmissiveTex.zw;
        float3 EmissCol = _EmissiveAtlas.SampleLevel(sampler_EmissiveAtlas, EmissionUV, 0).xyz;
        if(EmissCol.x > 0.001f) {
            hitmat.emmis = 1.0f + EmissCol.x;
        }
    }

    bool DidTerminate = true;//Identifier marking whether we have terminated the ray or if it will continue
    calcFinalColor(ray, Color, hitmat, bestHit, TempUv, DidTerminate, NormalUV, GlobalRays2[index].HitVoxel);
    GlobalColors[pixel_index] = Color;
}



#pragma kernel kernel_finalize

[numthreads(16,16,1)]
void kernel_finalize (uint3 id : SV_DispatchThreadID) {//Moved final accumulation into its own kernel, improves performance
    
    if(id.x >= screen_width || id.y >= screen_height) return;
    int final_pixel_index = id.y * screen_width + id.x;

    Result[id.xy] = float4((GlobalColors[final_pixel_index].Direct + GlobalColors[final_pixel_index].Indirect) * TempAlbedoTex[id.xy].xyz + GlobalColors[final_pixel_index].Fog, 1.0f);

}




#pragma kernel kernel_reservoir


float4x4 viewprojection;
float4x4 prevviewprojection;

float3 camPos;


float Attenuate(LightData light, float3 worldPos)
{
    float dist = distance(light.Position, worldPos);

    float att = saturate(1.0f - (dist * dist / (10000.0f)));

    return att * att;
}

float GeometricShadowing(
    float3 n, float3 v, float3 h, float roughness)
{
    // End result of remapping:
    float k = pow(roughness + 1, 2) / 8.0f;
    float NdotV = saturate(dot(n, v));

    // Final value
    return NdotV / max((NdotV * (1 - k) + k), 0.0001f);
}

//function for the fresnel term(Schlick approximation)
float3 Fresnel(float3 h, float3 v, float3 f0)
{
    //calculating v.h
    float VdotH = saturate(dot(v, h));
    //raising it to fifth power
    float VdotH5 = pow(1 - VdotH, 5);

    float3 finalValue = f0 + (1 - f0) * VdotH5;

    return finalValue;
}

//function for the GGX normal distribution of microfacets
float SpecularDistribution(float roughness, float3 h, float3 n)
{
    //remapping the roughness
    float a = pow(roughness, 2);
    float a2 = a * a;

    float NdotHSquared = saturate(dot(n, h));
    NdotHSquared *= NdotHSquared;

    float denom = NdotHSquared * (a2 - 1) + 1;
    denom *= denom;
    denom *= PI;

    return a2 / max(denom, 0.00001f);

}

void CookTorrenceRaytrace(float3 n, float3 h, float roughness, float3 v, float3 f0, float3 l, out float3 F, out float D, out float G)
{

    D = SpecularDistribution(roughness, h, n);
    F = Fresnel(h, v, f0);
    G = GeometricShadowing(n, v, h, roughness) * GeometricShadowing(n, l, h, roughness);

}

float CalculateDiffuse(float3 n, float3 l)
{
    float3 L = l;
    L = normalize(L); //normalizing the negated direction
    float3 N = n;
    N = normalize(N); //normalizing the normal

    float NdotL = dot(N, L);
    NdotL = saturate(NdotL); //this is the light amount, we need to clamp it to 0 and 1.0

    return NdotL;
}

float3 PointLightPBRRaytrace(LightData light, float3 normal, float3 worldPos, float3 cameraPos, float roughness, float metalness, float3 surfaceColor, float3 f0)
{
    //variables for different functions
    float3 F; //fresnel
    float D; //ggx
    float G; //geomteric shadowing

    //light direction calculation
    float3 L = normalize(light.Position - worldPos);
    float3 V = normalize(cameraPos - worldPos);
    float3 H = normalize(L + V);
    float3 N = normalize(normal);

    float atten = Attenuate(light, worldPos);

    CookTorrenceRaytrace(normal, H, roughness, V, f0, L, F, D, G);

    float lambert = CalculateDiffuse(normal, L);
    float3 ks = F;
    float3 kd = float3(1.0f, 1.0f, 1.0f) - ks;
    kd *= (float3(1.0f, 1.0f, 1.0f) - metalness);

    float3 numSpec = D * F * G;
    float denomSpec = 4.0f * max(dot(N, V), 0.001f) * max(dot(N, L), 0.001f);
    float3 specular = numSpec / max(denomSpec, 0.0001f); //just in case denominator is zero

    return ((kd * surfaceColor.xyz / PI) + specular) * lambert * light.Radiance;

}

void UpdateReservoir(inout Reservoir r, float x, float w, float rndnum)
{
    r.wsum += w;
    r.M += 1;
    if (rndnum < (w/r.wsum))
        r.y = x;

}


[numthreads(16,16,1)]
void kernel_reservoir (uint3 id : SV_DispatchThreadID) {//Moved final accumulation into its own kernel, improves performance

    if(id.x >= screen_width || id.y >= screen_height) return;
    pixel_index = id.y * screen_width + id.x;
rng_state = pixel_index * curframe;
    int LightCount = unitylightcount;

    float3 Norm = TempNormTex[id.xy].xyz;
    float3 Albedo = TempAlbedoTex[id.xy].xyz;
    float3 WorldPosition = TempPosTex[id.xy].xyz;
    float AlbedoLum = luminance(Albedo.x, Albedo.y, Albedo.z);


    Reservoir prevReservoir = {0,0,0,0,0};
    float4 PrevPos = mul(prevviewprojection, float4(TempPosTex[id.xy].xyz, 1));
    float2 PrevUV =  float2(PrevPos.x, PrevPos.y) / PrevPos.w;
    uint2 prevIndex = (int2)((PrevUV * 0.5f + 0.5f) * float2(screen_width, screen_height) + 0.5f);
    //prevIndex.x = ((PrevUV.x + 1.f) / 2.f) * (float) screen_width;
    //prevIndex.y = ((1.f - PrevUV.y) / 2.f) * (float) screen_height;
    if (prevIndex.x >= 0 && prevIndex.x < screen_width && prevIndex.y >= 0 && prevIndex.y < screen_height)
    {
        prevReservoir = PreviousReservoir[prevIndex.y * screen_width + prevIndex.x];
    }

    Reservoir reservoir = {0,0,0,0,0};
    for(int i = 0; i < min(LightCount, 32); i++) {



        int lighttosample = floor(min(float(rand_xorshift()) * (1.0 / 4294967296.0) * LightCount, LightCount - 1));
        if(prevReservoir.y == lighttosample && (prevReservoir.WasSuccessful == 0)) continue;
        LightData light = _UnityLights[lighttosample];
        float p = rcp(LightCount);
        float3 L = saturate(normalize(light.Position - WorldPosition));

        float ndotl = saturate(dot(Norm, L));

        float3 brdf_val = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);
        float w = length(brdf_val) / p;
        UpdateReservoir(reservoir, lighttosample, w, float(rand_xorshift()) * (1.0 / 4294967296.0));

        CurrentReservoir[id.y * screen_width + id.x] = reservoir;

    }
    LightData light = _UnityLights[reservoir.y];

    float3 L = saturate(normalize(light.Position - WorldPosition));

    float ndotl = saturate(dot(Norm, L));

    float3 bsdf_value;
        float bsdf_pdf;
        float cos_theta_hit = dot(L, Norm);
                float3 brdf_val = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 0.0f, 0.0f, Albedo, Albedo);
        float p_hat = length(brdf_val);

    if(p_hat == 0) reservoir.W = 0;
    else reservoir.W = (1.0f / max(p_hat, 0.00001f)) * (reservoir.wsum / max(reservoir.M, 0.0000001f));


    Reservoir temporalRes = {0,0,0,0,0};

    UpdateReservoir(temporalRes, reservoir.y, p_hat * reservoir.W * reservoir.M, float(rand_xorshift()) * (1.0 / 4294967296.0));

    {
        LightData light = _UnityLights[prevReservoir.y];

        float3 L = saturate(normalize(light.Position - WorldPosition));

    float ndotl = saturate(dot(Norm, L));

    float3 bsdf_value;
        float bsdf_pdf;
        float cos_theta_hit = dot(L, Norm);
                float3 brdf_val = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);

        if(prevReservoir.M > 20 * reservoir.M) {
            prevReservoir.wsum *= 20 * reservoir.M / prevReservoir.M;
            prevReservoir.M = 20 * reservoir.M;
        }
        float p_hat = length(brdf_val);
        UpdateReservoir(temporalRes, prevReservoir.y, p_hat * prevReservoir.W * prevReservoir.M, float(rand_xorshift()) * (1.0 / 4294967296.0));

    } 

    temporalRes.M = reservoir.M + prevReservoir.M;


    {
        LightData light = _UnityLights[temporalRes.y];

        float3 L = saturate(normalize(light.Position - WorldPosition));

    float ndotl = saturate(dot(Norm, L));

    float3 bsdf_value;
        float bsdf_pdf;
        float cos_theta_hit = dot(L, Norm);
                float3 brdf_val = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);
        float p_hat = length(brdf_val);
        if(p_hat == 0) {
            temporalRes.W = 0;
        } else {
            temporalRes.W = (temporalRes.wsum / temporalRes.M) / p_hat;
        }
        reservoir = temporalRes;

        CurrentReservoir[id.y * screen_width + id.x] = reservoir;

    _DebugTex[id.xy] = float4(brdf_val  / reservoir.W, 1);


    } 

//    _DebugTex[id.xy] = float4(reservoir.y / 2.0f, reservoir.wsum, reservoir.M, reservoir.W);

}







#pragma kernel kernel_reservoir_spatial

float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

//function to generate a hammersly low discrepency sequence for importance sampling
float2 Hammersley(uint i, uint N)
{
    return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

[numthreads(16,16,1)]
void kernel_reservoir_spatial (uint3 id : SV_DispatchThreadID) {//Moved final accumulation into its own kernel, improves performance


    if(id.x >= screen_width || id.y >= screen_height) return;
    pixel_index = id.y * screen_width + id.x;

    float3 Norm = TempNormTex[id.xy].xyz;
    float3 Albedo = TempAlbedoTex[id.xy].xyz;
    float3 WorldPosition = TempPosTex[id.xy].xyz;

    Reservoir reservoirNew = {0,0,0,0,0};
    Reservoir r = PreviousReservoir[pixel_index];
    LightData light = _UnityLights[r.y];
    float3 L = saturate(dot(Norm, L)); // lambertian term
        
            // p_hat of the light is f * Le * G / pdf   
    float3 brdfVal = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);
    float p_hat = length(brdfVal); // technically p_hat is divided by pdf, but point light pdf is 1
    UpdateReservoir(reservoirNew, r.y, p_hat * r.W * r.M, random(34).x);


    uint2 neighborOffset;
    uint2 neighborIndex;
    int lightSamplesCount = 0;
    for (int i = 0; i < 100;i++)
    {
        float2 xi = Hammersley(i, 100);
        
        float radius = 30 * random(i).x;
        float angle = 2.0f * PI * random(i).y;
        
        float2 neighborIndex = pixel_index;
        
        neighborIndex.x += radius * cos(angle);
        neighborIndex.y += radius * sin(angle);
         
        uint2 u_neighbor = uint2(neighborIndex);
        if (u_neighbor.x < 0 || u_neighbor.x >= screen_width || u_neighbor.y < 0 || u_neighbor.y >= screen_width)
        {
            continue;
        }
        
        // The angle between normals of the current pixel to the neighboring pixel exceeds 25 degree        
        if ((dot(TempNormTex[id.xy].xyz, TempNormTex[id.xy].xyz)) < 0.906)
        {
            continue;
        }
        
    //  Exceed 10% of current pixel's depth
        if (TempNormTex[id.xy].w > 1.1 * TempNormTex[id.xy].w || TempNormTex[id.xy].w < 0.9 * TempNormTex[id.xy].w)
        {
            continue;
        }
        
        Reservoir neighborRes = PreviousReservoir[u_neighbor.y * uint(screen_width) + u_neighbor.x];
        
        if(neighborRes.WasSuccessful == 0) continue;

         LightData light = _UnityLights[neighborRes.y];
         
         float3 L = saturate(normalize(light.Position - WorldPosition));
             
         float ndotl = saturate(dot(Norm.xyz, L)); // lambertian term
        
         float3 brdfVal = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);
         float p_hat = length(brdfVal); // technically p_hat is divided by pdf, but point light pdf is 1
         UpdateReservoir(reservoirNew, neighborRes.y, p_hat * neighborRes.W * neighborRes.M, random(i + 100).y);
         
         lightSamplesCount += neighborRes.M;
    }

    reservoirNew.M = lightSamplesCount;

    //Adjusting the final weight of reservoir Equation 6 in paper
    light = _UnityLights[reservoirNew.y];
    L = saturate(normalize(light.Position - WorldPosition));
            
    float ndotl = saturate(dot(Norm.xyz, L)); // lambertian term

                // p_hat of the light is f * Le * G / pdf   
    brdfVal = PointLightPBRRaytrace(light, Norm, WorldPosition, camPos, 1.0f, 1.0f, Albedo, Albedo);
    p_hat = length(brdfVal); // technically p_hat is divided by pdf, but point light pdf is 1
    
    if(p_hat == 0)
        reservoirNew.W == 0;
    
    else
        reservoirNew.W = (1.0 / max(p_hat, 0.00001)) * (reservoirNew.wsum / max(reservoirNew.M, 0.0001));
    
    CurrentReservoir[pixel_index] = reservoirNew;
        

    _DebugTex[id.xy] = float4(brdfVal * reservoirNew.W, 1);

}

#pragma kernel kernel_reservoir_copy

[numthreads(16,16,1)]
void kernel_reservoir_copy (uint3 id : SV_DispatchThreadID) {//Moved final accumulation into its own kernel, improves performance

    if(id.x >= screen_width || id.y >= screen_height) return;
    int final_pixel_index = id.y * screen_width + id.x;
    PreviousReservoir[final_pixel_index] = CurrentReservoir[final_pixel_index];

}