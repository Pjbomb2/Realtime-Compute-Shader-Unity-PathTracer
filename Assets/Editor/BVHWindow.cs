 using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
 using UnityEngine;
 using UnityEditor;
using CommonVars;
 using System.Xml;
 using System.IO;
         using System.Threading;

public class EditModeFunctions : EditorWindow {
     [MenuItem("PathTracer/Pathtracer Settings")]
     public static void ShowWindow() {
         GetWindow<EditModeFunctions>("Pathtracing Settings");
     }

      private void OnStartAsyncCombined() {
         EditorUtility.SetDirty(GameObject.Find("Scene").GetComponent<AssetManager>());
         GameObject.Find("Scene").GetComponent<AssetManager>().EditorBuild();
      }

      private void QuickStart() {
         List<Transform> Children = new List<Transform>();
            for(int i = 0; i < Assets.transform.childCount; i++) {
                  Children.Add(Assets.transform.GetChild(i));   
               }
            List<Transform> Parents = new List<Transform>();
            while(Children.Count != 0) {
               Transform Child = Children[Children.Count - 1];//its much faster to read and remove from the end than the beginning
               Children.RemoveAt(Children.Count - 1);
               if(Child.GetComponent<Light>() != null && Child.GetComponent<RayTracingLights>() == null) Child.gameObject.AddComponent<RayTracingLights>(); 
               if(!Child.gameObject.activeInHierarchy && !(Child.GetComponent<SkinnedMeshRenderer>() != null || Child.GetComponent<MeshFilter>() != null)) continue;
               if(Child.parent.GetComponent<ParentObject>() != null) {
                  if((Child.GetComponent<SkinnedMeshRenderer>() != null || Child.GetComponent<MeshFilter>() != null)  && Child.GetComponent<RayTracingObject>() == null) {
                     Child.gameObject.AddComponent<RayTracingObject>();
                  }
               } else {
                  if((Child.GetComponent<SkinnedMeshRenderer>() != null || Child.GetComponent<MeshFilter>() != null)  && Child.GetComponent<ParentObject>() == null) {
                     if(Child.GetComponent<SkinnedMeshRenderer>() != null) {
                        bool AlreadyIsParented = false;
                        for(int i2 = 0; i2 < Parents.Count; i2++) {
                           if(Child.IsChildOf(Parents[i2])) AlreadyIsParented = true;                        
                        }
                        if(!AlreadyIsParented) {
                           Parents.Add(Child);
                           Child.gameObject.AddComponent<ParentObject>();
                        }
                     } else {
                        Child.gameObject.AddComponent<ParentObject>(); 
                     }
                  }
                  if((Child.GetComponent<SkinnedMeshRenderer>() != null || Child.GetComponent<MeshFilter>() != null)  && Child.GetComponent<RayTracingObject>() == null) {
                     Child.gameObject.AddComponent<RayTracingObject>(); 
                  }
               }

               bool HasChildrenMesh = false;
               for(int i = 0; i < Child.childCount; i++) {
                  Children.Add(Child.GetChild(i));   
                  if((Child.GetChild(i).GetComponent<MeshFilter>() != null) && Child.GetComponent<ParentObject>() == null) {
                     Child.gameObject.AddComponent<ParentObject>();
                  }
                  if((Child.GetChild(i).GetComponent<SkinnedMeshRenderer>() != null) && Child.GetComponent<ParentObject>() == null) {
                     bool AlreadyIsParented = false;
                     for(int i2 = 0; i2 < Parents.Count; i2++) {
                        if(Child.IsChildOf(Parents[i2])) AlreadyIsParented = true;                        
                     }
                     if(!AlreadyIsParented) {
                        Parents.Add(Child);
                        Child.gameObject.AddComponent<ParentObject>();
                     }
                  } else if(Child.GetComponent<ParentObject>() != null) {
                     Parents.Add(Child);
                  }
               }
            }
            Parents.Clear();
            Parents.TrimExcess();
            Children.TrimExcess();
      }
      public bool UseAtrous = false;
      public bool UseSVGF = false;
      public bool UseNEE = false;
      public bool UseDoF = false;
      public float DoFAperature = 0.2f;
      public float DoFFocal = 1.0f;
      public int SVGF_Atrous_Kernel_Sizes = 6;
      public int Atrous_Kernel_Sizes = 6;
      public int BounceCount = 24;
      public bool UseRussianRoulette = true;
      public bool AllowConverge = true;
      public bool DynamicTLAS = true;
      private RayTracingMaster RayMaster;
      public float SunDir = 0.0f;
      public float Atrous_CW = 0.1f;
      public float Atrous_NW = 0.1f;
      public float Atrous_PW = 0.1f;
      public bool AllowSkinning = true;
      public bool AllowVolumetrics = false;
      public bool AllowBloom = false;
      public bool AllowTAA = false;
      public bool UseAutoExpose = false;
      public float VolumeDensity = 0.001f;
      public AssetManager Assets;
      private void OnGUI() {
         if(RayMaster == null) {
            Camera TempCam = Camera.main;
            if(TempCam.GetComponent<RayTracingMaster>() == null) TempCam.gameObject.AddComponent(typeof(RayTracingMaster));
            if(TempCam.GetComponent<FlyCamera>() == null) TempCam.gameObject.AddComponent(typeof(FlyCamera));
            RayMaster = Camera.main.GetComponent<RayTracingMaster>();
         }
         if(Assets == null) {
            if(GameObject.Find("Scene") == null) {
            List<GameObject> Objects = new List<GameObject>();
            UnityEngine.SceneManagement.SceneManager.GetActiveScene().GetRootGameObjects(Objects);
            GameObject SceneObject = new GameObject("Scene", typeof(AssetManager));
            foreach(GameObject Obj in Objects) {
               if(!Obj.Equals(Camera.main.gameObject)) {
                  Obj.transform.SetParent(SceneObject.transform);
               }
            }
            }
            Assets = GameObject.Find("Scene").GetComponent<AssetManager>();
            QuickStart();

            }
         Rect ScreenShotButton = new Rect(10 + (position.width - 10) / 2,10,(position.width - 10) / 2 - 10, 20);
         Rect EasySetupButton = new Rect(10 + (position.width - 10) / 2,35,(position.width - 10) / 2 - 10, 20);
         Rect CombinedBuilderButton = new Rect(10,10,(position.width - 10) / 2, 20);
         Rect ClearParentData = new Rect(10,35,(position.width - 10) / 2, 20);
         Rect SunDirLabel   =         new Rect(10,60,(position.width - 10) / 2, 20);
         Rect Sun_Dir_Slider = new Rect(Mathf.Max((position.width - 10) / 4,145), 60, (position.width - 10) / 4, 20);
         Rect BounceCountInput =   new Rect(Mathf.Max((position.width - 10) / 4,145), 85, (position.width - 10) / 4, 20);
         Rect BounceCountLabel =   new Rect(10, 85, Mathf.Max((position.width - 10) / 4,145), 20);
         Rect RussianRouletteToggle = new Rect(10, 110, (position.width - 10) / 2, 20);
         Rect DynamicTLASToggle =       new Rect(10, 135, (position.width - 10) / 2, 20);
         Rect AllowConvergeToggle =       new Rect(10, 160, (position.width - 10) / 2, 20);
         Rect UseNEEToggle =       new Rect(10, 185, (position.width - 10) / 2, 20);
         Rect AllowVolumetricsToggle =       new Rect(10, 210, (position.width - 10) / 2, 20);
         Rect VolumetricsDensityLabel =       new Rect(10 + (position.width - 10) / 2, 210, (position.width - 10) / 4, 20);
         Rect VolumetricsDensityInput =       new Rect(10 + (position.width - 10) / 2 + (position.width - 10) / 4, 210, (position.width - 10) / 4 - 10, 20);
         Rect SkinnedHandlingToggle =       new Rect(10, 235, (position.width - 10) / 2, 20);
         Rect AllowBloomToggle =       new Rect(10, 260, (position.width - 10) / 2, 20);
         Rect DoFToggle =       new Rect(10, 285, (position.width - 10) / 2, 20);
         Rect AutoExposeToggle =       new Rect(10, 310, (position.width - 10) / 2, 20);
         Rect TAAToggle =       new Rect(10, 335, (position.width - 10) / 2, 20);
         int SVGFVertOffset = 360;
         UseDoF = GUI.Toggle(DoFToggle, UseDoF, "Use DoF");
         if(UseDoF) {
            Rect DoF_Aperature_Input = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset, (position.width - 10) / 4, 20);
            Rect DoF_Aperature_Lable = new Rect(10, SVGFVertOffset, Mathf.Max((position.width - 10) / 4,145), 20);
            GUI.Label(DoF_Aperature_Lable, "Aperature Size");
            DoFAperature = GUI.HorizontalSlider(DoF_Aperature_Input, DoFAperature, 0.0f, 1.0f);
            SVGFVertOffset += 25;
            Rect DoF_Focal_Input = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset, (position.width - 10) / 4, 20);
            Rect DoF_Focal_Lable = new Rect(10, SVGFVertOffset, Mathf.Max((position.width - 10) / 4,145), 20);
            GUI.Label(DoF_Focal_Lable, "Focal Length");
            DoFFocal = GUI.HorizontalSlider(DoF_Focal_Input, DoFFocal, 0.0f, 60.0f);
            SVGFVertOffset += 25;
            RayMaster.DoFAperature = DoFAperature;
            RayMaster.DoFFocal = DoFFocal;
         }
         RayMaster.AllowDoF = UseDoF;

         UseAutoExpose = GUI.Toggle(AutoExposeToggle, UseAutoExpose, "Use Auto Exposure");
         RayMaster.AllowAutoExpose = UseAutoExpose;
         AllowTAA = GUI.Toggle(TAAToggle, AllowTAA, "Use Temporal Antialiasing");
         RayMaster.AllowTAA = AllowTAA;


         Rect SVGFToggle =       new Rect(10, SVGFVertOffset, (position.width - 10) / 2, 20);
         SVGFVertOffset += 25;
         AllowConverge = GUI.Toggle(AllowConvergeToggle, AllowConverge, "Allow Image Accumulation");
         DynamicTLAS = GUI.Toggle(DynamicTLASToggle, DynamicTLAS, "Enable Object Moving");
         UseNEE = GUI.Toggle(UseNEEToggle, UseNEE, "Use Next Event Estimation");
         AllowVolumetrics = GUI.Toggle(AllowVolumetricsToggle, AllowVolumetrics, "Allow Volumetrics");
         AllowSkinning = GUI.Toggle(SkinnedHandlingToggle, AllowSkinning, "Allow Mesh Skinning");
         AllowBloom = GUI.Toggle(AllowBloomToggle, AllowBloom, "Allow Bloom");
         Assets.UseSkinning = AllowSkinning;
         RayMaster.AllowVolumetrics = AllowVolumetrics;
         RayMaster.AllowBloom = AllowBloom;
         RayMaster.DoTLASUpdates = DynamicTLAS;
         RayMaster.AllowConverge = AllowConverge;
         RayMaster.UseNEE = UseNEE;
         
         if (GUI.Button(ScreenShotButton, "Take ScreenShot")) {
            GameObject result = new GameObject();
            string dirPath = Application.dataPath + "/../Assets/ScreenShots";
            if(!System.IO.Directory.Exists(dirPath)) {
               Debug.Log("No Folder Named ScreenShots in Assets");
            } else {
               ScreenCapture.CaptureScreenshot(dirPath + "/" + System.DateTime.Now.ToString("yyyy-MM-dd HH-mm-ss") + ", " + RayMaster.SampleCount + " Samples.png");
               UnityEditor.AssetDatabase.Refresh();
            }

         }


         if (GUI.Button(EasySetupButton, "QuickStart")) {
            QuickStart();
         }


         if (GUI.Button(CombinedBuilderButton, "Build Aggregated BVH")) {
            OnStartAsyncCombined();
         }
         if (GUI.Button(ClearParentData, "Clear Parent Data")) {
            EditorUtility.SetDirty(Assets);
            Assets.ClearAll();
         }
         
         GUI.Label(BounceCountLabel, "Max Bounces");
         GUI.Label(SunDirLabel, "Sun Position");
         SunDir = GUI.HorizontalSlider(Sun_Dir_Slider, SunDir, 0.0f, 3.14159f * 2.0f);
         RayMaster.SunDirFloat = SunDir;
         BounceCount = EditorGUI.IntField(BounceCountInput, BounceCount);
         //Debug.Log(885720 % BounceCount);
         RayMaster.bouncecount = BounceCount;
         UseRussianRoulette = GUI.Toggle(RussianRouletteToggle, UseRussianRoulette, "Use Russian Roulette");
         RayMaster.UseRussianRoulette = UseRussianRoulette;
         UseSVGF = GUI.Toggle(SVGFToggle, UseSVGF, "Use SVGF Denoiser");
         RayMaster = Camera.main.GetComponent<RayTracingMaster>() as RayTracingMaster;
         if(UseSVGF) {
            Rect Atrous_Kernel_Size = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset, (position.width - 10) / 4, 20);
            Rect Atrous_Kernel_Size_Lable = new Rect(10, SVGFVertOffset, Mathf.Max((position.width - 10) / 4,145), 20);
            
            GUI.Label(Atrous_Kernel_Size_Lable, "SVGF Atrous Kernel Size");
            SVGF_Atrous_Kernel_Sizes = EditorGUI.IntField(Atrous_Kernel_Size, SVGF_Atrous_Kernel_Sizes);
            SVGFVertOffset += 25;
            RayMaster.SVGFAtrousKernelSizes = SVGF_Atrous_Kernel_Sizes;
         }
         RayMaster.UseSVGF = UseSVGF;
         Rect AtrousToggle = new Rect(10,  SVGFVertOffset, (position.width - 10) / 2, 20);
         UseAtrous = GUI.Toggle(AtrousToggle, UseAtrous, "Use Atrous Denoiser");
         if(UseAtrous) {
            SVGFVertOffset += 25;
            Rect Atrous_Color_Weight = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset, (position.width - 10) / 4, 20);
            Rect Atrous_Color_Weight_Lable = new Rect(10, SVGFVertOffset, Mathf.Max((position.width - 10) / 4,145), 20);
            Rect Atrous_Normal_Weight = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset + 25, (position.width - 10) / 4, 20);
            Rect Atrous_Normal_Weight_Lable = new Rect(10, SVGFVertOffset + 25, Mathf.Max((position.width - 10) / 4,145), 20);
            Rect Atrous_Position_Weight = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset + 50, (position.width - 10) / 4, 20);
            Rect Atrous_Position_Weight_Lable = new Rect(10, SVGFVertOffset + 50, Mathf.Max((position.width - 10) / 4,145), 20);
            Rect Atrous_Kernel_Size = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset + 75, (position.width - 10) / 4, 20);
            Rect Atrous_Kernel_Size_Lable = new Rect(10, SVGFVertOffset + 75, Mathf.Max((position.width - 10) / 4,145), 20);
            
            GUI.Label(Atrous_Color_Weight_Lable, "Atrous Color Weight");
            Atrous_CW = GUI.HorizontalSlider(Atrous_Color_Weight, Atrous_CW, 0.0f, 1.0f);
            GUI.Label(Atrous_Normal_Weight_Lable, "Atrous Normal Weight");
            Atrous_NW = GUI.HorizontalSlider(Atrous_Normal_Weight, Atrous_NW, 0.0f, 1.0f);
            GUI.Label(Atrous_Position_Weight_Lable, "Atrous Position Weight");
            Atrous_PW = GUI.HorizontalSlider(Atrous_Position_Weight, Atrous_PW, 0.0f, 1.0f);
            GUI.Label(Atrous_Kernel_Size_Lable, "Atrous Kernel Size");
            Atrous_Kernel_Sizes = EditorGUI.IntField(Atrous_Kernel_Size, Atrous_Kernel_Sizes);
            RayMaster.c_phiGlob = Atrous_CW;
            RayMaster.n_phiGlob = Atrous_NW;
            RayMaster.p_phiGlob = Atrous_PW;
            RayMaster.AtrousKernelSizes = Atrous_Kernel_Sizes;
            SVGFVertOffset += 75;
         }

         Rect SampleCountLabel =   new Rect(10, SVGFVertOffset + 25, Mathf.Max((position.width - 10) / 4,145), 20);
         Rect SampleCountIndicator = new Rect(Mathf.Max((position.width - 10) / 4,145), SVGFVertOffset + 25, (position.width - 10) / 4, 20);
         GUI.Label(SampleCountLabel, "Current Samples");
         int Throwaway = EditorGUI.IntField(SampleCountIndicator, RayMaster.SampleCount);
         RayMaster.UseAtrous = UseAtrous;
         if(AllowVolumetrics) {
            GUI.Label(SampleCountLabel, "Current Samples");
            GUI.Label(VolumetricsDensityLabel, "Volume Density");
            VolumeDensity = GUI.HorizontalSlider(VolumetricsDensityInput, VolumeDensity, 0.0f, 1.0f);
            RayMaster.VolumeDensity = VolumeDensity;

         }
     }

void OnInspectorUpdate() {
   Repaint();
}

            void OnFinishAsync(GameObject result, AnimationClip[] A) {
                 Debug.Log("Finished importing " + result.name);
            }

}