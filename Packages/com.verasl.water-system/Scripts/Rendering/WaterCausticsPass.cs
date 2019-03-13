﻿//using UnityEngine;
//using UnityEngine.Rendering;
//using UnityEngine.Experimental.Rendering;
//using UnityEngine.Experimental.Rendering.LightweightPipeline;

//namespace WaterSystem
//{
//    [ImageEffectAllowedInSceneView]
//    public class WaterCausticsPass : MonoBehaviour, IAfterOpaquePass
//    {
//        private WaterCausticsPassImpl m_WaterCausticsPass;

//        WaterCausticsPassImpl waterCausticsPass
//        {
//            get
//            {
//                if (m_WaterCausticsPass == null)
//                    m_WaterCausticsPass = new WaterCausticsPassImpl();

//                return m_WaterCausticsPass;
//            }
//        }

//        public ScriptableRenderPass GetPassToEnqueue(RenderTextureDescriptor baseDescriptor,
//            RenderTargetHandle colorHandle, RenderTargetHandle depthHandle)
//        {
//            return waterCausticsPass;
//        }
//    }

//    public class WaterCausticsPassImpl : ScriptableRenderPass
//    {
//        const string k_RenderWaterFXTag = "Render Water FX";
//        private RenderTargetHandle m_WaterFX = RenderTargetHandle.CameraTarget;

//        private FilteringSettings transparentFilterSettings { get; set; }

//        public WaterCausticsPassImpl()
//        {
//            RegisterShaderPassName("WaterFX");
//            m_WaterFX.Init("_WaterFXMap");


//            transparentFilterSettings = new FilteringSettings(RenderQueueRange.transparent);
//        }

//        public override void Execute(ScriptableRenderer renderer, ScriptableRenderContext context, ref RenderingData renderingData)
//        {
//            CommandBuffer cmd = CommandBufferPool.Get(k_RenderWaterFXTag);

//            RenderTextureDescriptor descriptor = ScriptableRenderer.CreateRenderTextureDescriptor(ref renderingData.cameraData);
//            descriptor.width = (int)(descriptor.width * 0.5f);
//            descriptor.height = (int)(descriptor.height * 0.5f);
//            descriptor.colorFormat = RenderTextureFormat.Default;

//            using (new ProfilingSample(cmd, k_RenderWaterFXTag))
//            {
//                cmd.GetTemporaryRT(m_WaterFX.id, descriptor, FilterMode.Bilinear);

//                SetRenderTarget(
//                    cmd,
//                    m_WaterFX.Identifier(),
//                    RenderBufferLoadAction.DontCare,
//                    RenderBufferStoreAction.Store,
//                    ClearFlag.Color,
//                    new Color(0.0f, 0.5f, 0.5f, 0.5f),
//                    descriptor.dimension);

//                context.ExecuteCommandBuffer(cmd);
//                cmd.Clear();

//                var drawSettings = CreateDrawingSettings(renderingData.cameraData.camera,
//                    SortingCriteria.CommonTransparent, PerObjectData.None, renderingData.supportsDynamicBatching);
//                var filteringSettings = transparentFilterSettings;
//                if (renderingData.cameraData.isStereoEnabled)
//                {
//                    Camera camera = renderingData.cameraData.camera;
//                    context.StartMultiEye(camera);
//                    context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);
//                    context.StopMultiEye(camera);
//                }
//                else
//                {
//                    context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);
//                }
//            }

//            context.ExecuteCommandBuffer(cmd);
//            CommandBufferPool.Release(cmd);
//        }

//        public override void FrameCleanup(CommandBuffer cmd)
//        {
//            base.FrameCleanup(cmd);
//            if (m_WaterFX != RenderTargetHandle.CameraTarget)
//            {
//                cmd.ReleaseTemporaryRT(m_WaterFX.id);
//            }
//        }
//    }
//}