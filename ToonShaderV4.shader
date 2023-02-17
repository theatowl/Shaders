Shader "Singularity/ToonShaderV4"
{
    
    Properties
    {
        //Main maps
        _MainTex("Base Map",2D) = "white" {}
        _MainColor("Base Color", Color) = (1,1,1,1)
        [Normal]_BumpMap("Normal Map", 2D) = "bump" {}
        
        _Cutoff("Alpha Cutoff", Range(0,1)) = 0
        
        //Reflections
        _ReflectionTex("Reflection",2D) = "white" {}
        _ReflectionOpacity ("Reflection Opacity", Range(0,1)) = 1
        _ReflectionStrength("Reflection Strength", Range(0.1,1)) = 0.5
        _ReflectionSmoothness("Reflection Smoothness", Range(0,1)) = 0

        [HDR]_Reflection_Color1("Reflection Color 1", Color) = (0,0,0,0)
        [HDR]_Reflection_Color2("Reflection Color 2", Color) = (0,0,0,0)
        [HDR]_Reflection_Color3("Reflection Color 3", Color) = (0,0,0,0)
        _ReflectionGradientStretch("Gradient Stretch", Range (0,1)) = 0.8

        //Emission
        _Emission("Emission",2D) = "black" {}
        [HDR]_EmissionColor("Emission Color", Color) = (0,0,0,1)

        //Rim Light
        [HDR]_RimColor("Rim Color", Color)=(1,1,1,1)
        _RimAmount("Rim Amount", Range(0,1)) = 0.7
        _RimThreshold("Rim Threshold", Range(0,1)) = 0.4
        
        //Shadows
        _Color3("Light Shadow Color", Color) = (1,1,1,1)
        _Color2("Medium Shadow Color", Color) = (0.5,0.5,0.5,1)
        _Color("Dark Shadows Color", Color) = (0,0,0,1)
        _GradientStretch("Gradient Stretch", Range (0,1)) = 1
        
        _ToonRampOffset ("Shadow Offset", Range(0,1)) = 0.5
        _ShadowStrength ("Shadow Strength", Range(0,1)) = 0.65
        _ToonRampSmoothness ("Shadow Smoothness", Range(0,1)) = 0.1


        [HideInInspector]_SrcBlend("_SrcBlend", Float) = 1
        [HideInInspector]_DstBlend("_DstBlend", Float) = 0
        [HideInInspector] _ZWrite ("_ZWrite", Float) = 1
    }


    SubShader
    {
        Tags{ "Queue" = "Geometry" "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 200

        HLSLINCLUDE
        #include "Assets/Shaders/AnaelToonShader.hlsl"

        #pragma shader_feature_local _NORMALMAP
        #pragma shader_feature_local _EMISSIONMAP
        #pragma shader_feature_local _REFLECTIONMAP
        #pragma shader_feature_local _ _ALPHACUTOFF _TRANSPARENT
        
        #define UNITY_INITIALIZE_OUTPUT(type,name) name = (type)0;

        CBUFFER_START(UnityPerMaterial)

        float4  _MainTex_ST;
        float4  _MainColor;
        float4  _BumpMap_ST;

        float   _Cutoff;

        float4  _ReflectionTex_ST;
        float   _ReflectionOpacity;
        float   _ReflectionStrength;
        float   _ReflectionSmoothness;
        float4  _Reflection_Color3;
        float4  _Reflection_Color2;
        float4  _Reflection_Color1;
        float   _ReflectionGradientStretch;

        float4  _Emission_ST;
        float4  _EmissionColor;

        float4  _RimColor;
        float   _RimAmount;
        float   _RimThreshold;

        float4  _Color;
        float4  _Color2;
        float4  _Color3;
        float   _GradientStretch;

        
        float   _ToonRampOffset;
        float   _ShadowStrength;
        float   _ToonRampSmoothness;
        float4  _ShadowTex_ST;
        float4  _ShadowEdgeColor;
        float   _ShadowDilation;
        
        CBUFFER_END

        TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);

        TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
        
        TEXTURE2D(_ReflectionTex);      SAMPLER(sampler_ReflectionTex);
        
        TEXTURE2D(_Emission);           SAMPLER(sampler_Emission);

        TEXTURE2D(_ShadowTex);          SAMPLER(sampler_ShadowTex);

        //Vertex shader's input
        struct Attributes
        {
            float4 positionOS : POSITION; 
            float3 normal : NORMAL;
            float4 tangentWS : TANGENT ;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID    
        };

        //Vertex shader's output
        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            float3 viewDir : TEXCOORD3;
           #ifdef _NORMALMAP
                float3 T : TEXCOORD4;
                float3 B : TEXCOORD5;
           #endif
        };

        ENDHLSL
       
        Pass
        {
            Tags {"LightMode"="UniversalForward"}
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            HLSLPROGRAM
            
            #pragma vertex vertShader
            #pragma fragment fragShader
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            
            //----------------------------------------------------------------------HELPER FUNCTIONS------------------------------------------------------------------------------
            static float2 sobelSamplePoints[9] = {
                        float2(-1,1),float2(0,1),float2(1,1),
                        float2(-1,0),float2(0,0),float2(1,0),
                        float2(-1,-1),float2(0,-1),float2(1,-1)};

                        static float sobelXKernel[9] = {
                        1,0,-1,
                        2,0,-2,
                        1,0,-1
                        };

                        static float sobelYKernel[9] = {
                        1,2,1,
                        0,0,0,
                        -1,-2,-1
                        };

            //Calculate the Sobel Operator of the shadowmap
            float ShadowSobelOperator(float4 shadowCoord, float dilation)
            {
                //get shadowmap texel size
                ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
                float4 shadowMap_TexelSize = shadowSamplingData.shadowmapSize;

                //initialize results
                float sobelX = 0;
                float sobelY = 0;

                //loop over sample points
                [unroll] for (int i =0; i< 9; i++)
                {
                    //sample shadowmap
                    float shadowImage = MainLightRealtimeShadow(float4(shadowCoord.xy + sobelSamplePoints[i] * dilation * shadowMap_TexelSize.xy, shadowCoord.zw));

                    //sum the convolution values
                    sobelX += shadowImage * sobelXKernel[i];
                    sobelY += shadowImage * sobelYKernel[i];
                }
                //Return the magnitude
                return sqrt(sobelX * sobelX + sobelY*sobelY);
            }
            

            //----------------------------------------------------------------------VERTEX SHADER---------------------------------------------------------------------------------
            Varyings vertShader(Attributes IN)
            {
                Varyings OUT;
                UNITY_INITIALIZE_OUTPUT(Varyings, OUT);

                //Vertex position
                VertexPositionInputs posIN = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = posIN.positionCS;
                OUT.positionWS = posIN.positionWS;
                
                //UV et vertex color
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                
                float3 worldNormal = mul((float3x3)unity_ObjectToWorld, IN.normal);
                OUT.normalWS = normalize(worldNormal);
               #ifdef _NORMALMAP
                    float3 worldTangent = mul((float3x3)unity_ObjectToWorld, IN.tangentWS.xyz);
                    float3 binormal = cross(IN.normal, IN.tangentWS.xyz);
                    float3 worldBinormal = mul((float3x3)unity_ObjectToWorld, binormal);
                    OUT.T = normalize(worldTangent);
                    OUT.B = normalize(worldBinormal);
               #endif
                
                return OUT;
            }

            //----------------------------------------------------------------------FRAGMENT SHADER-------------------------------------------------------------------------------
            float4 fragShader(Varyings IN) : SV_Target
            {
                // Init AnaelToonShader.hlsl functions
                InitToon(_ToonRampOffset,_ToonRampSmoothness, _Color, _Color2, _Color3, _GradientStretch);
                InitSpecular(_ReflectionStrength,_ReflectionSmoothness, _Reflection_Color1, _Reflection_Color2, _Reflection_Color3, _ReflectionGradientStretch);
                InitRim(_RimAmount,_RimThreshold, _RimColor);
                
                //Main texture
                float4 albedoTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                float albedoClip = albedoTex.a;
                //alpha clip
                #ifdef _ALPHACUTOFF
				    clip(albedoClip - _Cutoff );
                #endif

                //Specular map
                #ifdef _REFLECTIONMAP 
                    float4 reflectionTex = SAMPLE_TEXTURE2D(_ReflectionTex, sampler_ReflectionTex,IN.uv);
                    float reflectionAmount = reflectionTex.a;
                #else
                    float reflectionAmount = _ReflectionOpacity;
                #endif

                //Normal mapping
               #ifdef _NORMALMAP
                    float3 normalTex = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv));
                    float3 normalWS = TransformTangentToWorld(normalTex,half3x3(IN.T, IN.B, IN.normalWS));
               #else
                    float3 normalWS = IN.normalWS;
               #endif
                    normalWS = normalize(normalWS);

                // Shadow coordinates
               #if SHADOWS_SCREEN
                    float4 clipPos = TransformWorldToHClip(IN.positionWS);
                    float4 shadowCoord = ComputeScreenPos(clipPos);
                #else
	                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS); //TRANSFER_SHADOWS(o)
                #endif 

                float shadowMap = MainLightRealtimeShadow(shadowCoord);

                // Emission Map
                 #ifdef _EMISSIONMAP
                    float4 emissiveTex = SAMPLE_TEXTURE2D(_Emission, sampler_Emission, IN.uv);
                    float4 emissive = emissiveTex * _EmissionColor;
                #else
                    float4 emissive = _EmissionColor;
                #endif

                // Toon functions
                float4 shadows = ToonRamp(shadowCoord, normalWS, IN.positionWS);
                float4 reflection = ReflectionRamp(shadowCoord, normalWS, IN.positionWS) *  reflectionAmount;
                float4 rim = RimRamp(shadowCoord, normalWS, IN.positionWS);

                //Transparent
                #if defined (_TRANSPARENT)
                    _Reflection_Color1.a = 0;
                    _Reflection_Color2.a = 0;
                    _Reflection_Color3.a = 0;
                    float alpha = albedoClip * _MainColor.a;
                    float4 clr =  albedoTex * _MainColor;
                    clr *= alpha;
                    clr = BlendMultiply(clr, shadows * albedoClip, _ShadowStrength);
                    clr += reflection + rim;
                #else
                //Dans le shader normal
                float4 clr = BlendMultiply(albedoTex * _MainColor, shadows, _ShadowStrength);
                clr += reflection + rim;
                clr += emissive;
                #endif

                return clr;  
            }

            ENDHLSL
        }



          Pass
        {
            Name "ShadowCaster"
            Tags {"LightMode" = "ShadowCaster"}
            ZWrite On
            ZTest LEqual
            ColorMask 0 

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            float3 _LightDirection;

            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normal);

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #endif

                return positionCS;
            }

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_INITIALIZE_OUTPUT(Varyings, output);
                UNITY_SETUP_INSTANCE_ID(input);

                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {   
               float alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
               #ifdef _ALPHACUTOFF
               clip (alpha - _Cutoff);
               #endif
                return 0;
            }

            
            ENDHLSL
        
        }
        Pass 
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
 
            ZWrite On
            ColorMask 0
 
            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x gles
            //#pragma target 4.5
 
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
 
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
             
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
             
            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                return 0;
            }
 
            // Again, using this means we also need _BaseMap, _BaseColor and _Cutoff shader properties
            // Also including them in cbuffer, except _BaseMap as it's a texture.
 
            ENDHLSL
            }
       
    }
    
    CustomEditor "CustomToonShaderGUI"
}
