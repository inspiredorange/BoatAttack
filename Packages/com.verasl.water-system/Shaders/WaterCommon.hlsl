﻿#ifndef WATER_COMMON_INCLUDED
#define WATER_COMMON_INCLUDED

#define _MAIN_LIGHT_SHADOWS_CASCADE 1
#define SHADOWS_SCREEN 0

#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"
#include "WaterInput.hlsl"
#include "CommonUtilities.hlsl"
#include "GerstnerWaves.hlsl"
#include "WaterLighting.hlsl"

///////////////////////////////////////////////////////////////////////////////
//                  				Structs		                             //
///////////////////////////////////////////////////////////////////////////////

struct WaterVertexInput // vert struct 
{
	float4	vertex 					: POSITION;		// vertex positions
	float2	texcoord 				: TEXCOORD0;	// local UVs
	float4	lightmapUV 				: TEXCOORD1;	// lightmap UVs
	float4	color					: COLOR;		// vertex colors
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct WaterVertexOutput // fragment struct
{
	float4	uv 						: TEXCOORD0;	// Geometric UVs stored in xy, and world(pre-waves) in zw
	//float4	lightmapUVOrVertexSH	: TEXCOORD1;	// holds either lightmapUV or vertex SH. depending on LIGHTMAP_ON - TODO
	float3	posWS					: TEXCOORD1;	// world position of the vertices
	half3 	normal 					: NORMAL;		// vert normals
	float3 	viewDir 				: TEXCOORD2;	// view direction
	float3	preWaveSP 				: TEXCOORD3;	// screen position of the verticies before wave distortion
	half2 	fogFactorNoise : TEXCOORD4;	// x: fogFactor, y: noise

	float4	additionalData			: TEXCOORD5;	// x = distance to surface, y = distance to surface, z = normalized wave height
	half4	shadowCoord				: TEXCOORD6;	// for ssshadows

	float4	clipPos					: SV_POSITION;
	UNITY_VERTEX_INPUT_INSTANCE_ID
	UNITY_VERTEX_OUTPUT_STEREO
};

///////////////////////////////////////////////////////////////////////////////
//          	   	      Water shading functions                            //
///////////////////////////////////////////////////////////////////////////////

half3 Scattering(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth, 0.375h)).rgb;
}

half3 Absorption(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth, 0.0h)).rgb;
}

float2 AdjustedDepth(half2 uvs, half4 additionalData)
{
	float rawD = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_ScreenTextures_linear_clamp, uvs);
	float d = LinearEyeDepth(rawD, _ZBufferParams);
	return float2(d * additionalData.x - additionalData.y, (rawD * -_ProjectionParams.x) + (1-UNITY_REVERSED_Z));
}

float3 WaterDepth(float3 posWS, half2 texcoords, half4 additionalData, half2 screenUVs)// x = seafloor depth, y = water depth
{
	float3 outDepth = 0;
	outDepth.xz = AdjustedDepth(screenUVs, additionalData);
	float wd = UNITY_REVERSED_Z + (SAMPLE_DEPTH_TEXTURE(_WaterDepthMap, sampler_WaterDepthMap_linear_clamp, texcoords).r * _ProjectionParams.x);
	outDepth.y = ((wd * _depthCamZParams.y) - 4 - _depthCamZParams.x) + posWS.y;
	return outDepth;
}

half3 Refraction(half2 distortion, half mip)
{
	half3 refrac = SAMPLE_TEXTURE2D_LOD(_CameraOpaqueTexture, sampler_CameraOpaqueTexture_linear_clamp, distortion, mip);
	return refrac;
}

half2 DistortionUVs(half depth, float3 normalWS)
{
	//half2 distortion;
    half3 viewNormal = mul(GetWorldToHClipMatrix(), -normalWS).xyz;
    
    return viewNormal.xz * saturate((depth) * 0.005);
}

///////////////////////////////////////////////////////////////////////////////
//               	   Vertex and Fragment functions                         //
///////////////////////////////////////////////////////////////////////////////

// Vertex: Used for Standard non-tessellated water
WaterVertexOutput WaterVertex(WaterVertexInput v)
{
    WaterVertexOutput o = (WaterVertexOutput)0;
	UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    o.uv.xy = v.texcoord; // geo uvs

	// initializes o.normal
    o.normal = float3(0, 1, 0);

    o.posWS = TransformObjectToWorld(v.vertex.xyz);
	o.uv.zw = o.posWS.xz;
	o.fogFactorNoise.y = ((noise((o.posWS.xz * 0.5) + _GlobalTime) + noise((o.posWS.xz * 1) + _GlobalTime)) * 0.25 - 0.5) + 1;

	half4 screenUV = ComputeScreenPos(TransformWorldToHClip(o.posWS));
	screenUV.xyz /= screenUV.w;

    // shallows mask
    half waterDepth = UNITY_REVERSED_Z + SAMPLE_DEPTH_TEXTURE_LOD(_WaterDepthMap, sampler_WaterDepthMap_linear_clamp, (o.posWS.xz * 0.002) + 0.5, 1).r * _ProjectionParams.x;
    waterDepth = ((waterDepth * _depthCamZParams.y) - 4 - _depthCamZParams.x);
    o.posWS.y += saturate((1 - waterDepth) * 0.6 - 0.5);

	//Gerstner here
	WaveStruct wave;
	SampleWaves(o.posWS, saturate((waterDepth * 0.25)) + 0.1, wave);
	o.normal = normalize(wave.normal.xzy);
	o.posWS += wave.position;

	half4 waterFX = SAMPLE_TEXTURE2D_LOD(_WaterFXMap, sampler_ScreenTextures_linear_clamp, screenUV.xy, 0);

	o.posWS.y += waterFX.w * 2 - 1;

	//after waves
	o.clipPos = TransformWorldToHClip(o.posWS);
	o.shadowCoord = ComputeScreenPos(o.clipPos);
    o.viewDir = SafeNormalize(_WorldSpaceCameraPos - o.posWS);

    // We either sample GI from lightmap or SH. lightmap UV and vertex SH coefficients
    // are packed in lightmapUVOrVertexSH to save interpolator.
    // The following funcions initialize
    //OUTPUT_LIGHTMAP_UV(v.lightmapUV, unity_LightmapST, o.lightmapUVOrVertexSH);
    //OUTPUT_SH(o.normal, o.lightmapUVOrVertexSH);

    //o.fogFactorAndVertexLight = VertexLightingAndFog(o.normal, o.posWS, o.clipPos.xyz);
	o.fogFactorNoise.x = ComputeFogFactor(o.clipPos.z);
	o.preWaveSP = screenUV; // pre-displaced screenUVs
	// Additional data
    float3 viewPos = TransformWorldToView(o.posWS.xyz);
	o.additionalData.x = length(viewPos / viewPos.z);// distance to surface
    o.additionalData.y = length(GetCameraPositionWS().xyz - o.posWS); // local position in camera space
	o.additionalData.z = wave.position.y / _MaxWaveHeight; // encode the normalized wave height into additional data
	o.additionalData.w = wave.position.x + wave.position.z;

	// distance blend
	half distanceBlend = saturate(o.additionalData.y * 0.005);

	o.normal = lerp(o.normal, half3(0, 1, 0), distanceBlend);

    return o;
}

// Fragment for water
half4 WaterFragment(WaterVertexOutput IN) : SV_Target
{
	UNITY_SETUP_INSTANCE_ID(IN);
	half3 screenUV = IN.shadowCoord.xyz / IN.shadowCoord.w;//screen UVs

	half4 waterFX = SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, IN.preWaveSP.xy);

	half animT = frac(_GlobalTime) * 16; // amination value for caustics(16 frames)
	
	// Detail waves
	half t = _Time.x;
	half2 detailBump = SAMPLE_TEXTURE2D_ARRAY(_SurfaceMap, sampler_SurfaceMap, IN.uv.zw * 0.25h + t + (IN.fogFactorNoise.y * 0.1), animT).xy; // TODO - check perf
	IN.normal += (half3(detailBump.x, 0.5h, detailBump.y) * 2 - 1) * _BumpScale;
	IN.normal += half3(waterFX.y, 0.5h, waterFX.z) - 0.5;

	// Depth
	float3 depth = WaterDepth(IN.posWS, (IN.posWS.xz * 0.002) + 0.5, IN.additionalData, screenUV.xy);// TODO - hardcoded shore depth UVs

	// Distortion
	half2 distortion = DistortionUVs(depth.x, IN.normal);
	distortion = screenUV.xy + distortion;// * clamp(depth.x, 0, 5);
	float d = depth.x;
	depth.xz = AdjustedDepth(distortion, IN.additionalData);
	distortion = depth.x < 0 ? screenUV.xy : distortion;
	depth.x = depth.x < 0 ? d : depth.x;

	// Seabed UVs from depth
    float4 H = float4(distortion*2.0-1.0, UNITY_REVERSED_Z == 1 ? depth.z : 1-depth.z, 1.0);
    float4 D = mul(_InvViewProjection,H);
	float2 seabedWS = D.xz/D.w;

	// Caustics
	half2 causticUV = (seabedWS * 0.3h + t + half2((IN.fogFactorNoise.y * 0.25), (1-IN.fogFactorNoise.y) * 0.25)) + IN.additionalData.w * 0.1h;
	half caustics = SAMPLE_TEXTURE2D_ARRAY_LOD(_SurfaceMap, sampler_SurfaceMap, causticUV, animT, depth.x * 0.5).z * saturate(depth.x); // caustics for sea floor, darkened to 25%

	// Fresnel
	half fresnelTerm = CalculateFresnelTerm(lerp(IN.normal, half3(0, 1, 0), 0.5), IN.viewDir.xyz);

	// Shadows
	half shadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(IN.posWS));
	
	// Specular
	half3 spec = Highlights(IN.posWS, 0.001, IN.normal, IN.viewDir) * shadow;
	Light mainLight = GetMainLight();
	//half3 ambient = SampleSHPixel(IN.lightmapUVOrVertexSH, IN.normal) * (mainLight.color * mainLight.distanceAttenuation);

	// Foam
	float2 foamMapUV = (IN.uv.zw * 0.1) + (detailBump.xy * 0.0025) + half2(IN.fogFactorNoise.y * 0.1, (1-IN.fogFactorNoise.y) * 0.1) + _GlobalTime * 0.05;
	half3 foamMap = SAMPLE_TEXTURE2D(_FoamMap, sampler_FoamMap, foamMapUV).rgb; //r=thick, g=medium, b=light
	half shoreMask = pow(((1-depth.y + 9) * 0.1), 6);
	half foamMask = (IN.additionalData.z);
	half shoreWave = (sin(_Time.z + (depth.y * 10) + IN.fogFactorNoise.y) * 0.5 + 0.5) * saturate((1-depth.x) + 1);
	foamMask = max(max((foamMask + shoreMask) - IN.fogFactorNoise.y * 0.25, waterFX.r * 2), shoreWave);
	half3 foamBlend = SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(foamMask, 0.66)).rgb;

	half3 foam = length(foamMap * foamBlend).rrr;

	// Reflections
	half3 reflection = SampleReflections(IN.normal, IN.viewDir.xyz, screenUV.xy, fresnelTerm, 0.0);
	reflection = reflection + spec;
	reflection *= 1 - saturate(foam);

	// Refraction
	half3 refraction = Refraction(distortion, depth.x * 0.25);

	// Final Colouring
	half depthMulti = 1 / _MaxDepth;
    half3 color = (refraction + ((caustics * refraction) * mainLight.color));
	color *= Absorption((depth.x) * depthMulti);
	color += Scattering(depth.x * depthMulti) * (shadow * 0.5 + 0.5);// * saturate(1-length(reflection));// TODO - scattering from main light(maybe additional lights too depending on cost)
	color *= 1 - saturate(foam);
	//color *= 1-saturate(length(reflection));

	// Foam lighting
	foam *= (shadow * 0.9 + 0.1) * mainLight.color;

	// Do compositing
	half3 comp = lerp(refraction, color + reflection + foam, 1-saturate(1-depth.x * 25));
	
	// Fog
    float fogFactor = IN.fogFactorNoise.x;
    comp = MixFog(comp, fogFactor);
	return half4(comp, 1);
	//return half4(refraction, 1); // debug line
}

#endif // WATER_COMMON_INCLUDED