Shader "Singularity/Parallax_StarMap"
{
    Properties
    {
        [NoScaleOffset]_MainTex ("Texture", 2D) = "white" {}
        _NormalTex("Normal Tex",2D) = "bump"{}

        _ReflectionTex("Reflection Texture", 2D) = "black"{}
        _ReflectionStrength("Reflection Strength", Range(0,1)) = 0.5
        _ReflectionSmoothness("Reflection Smoothness", Range(0,1)) = 0.5
        _ReflectionOpacity("Reflection Opacity", Range(0,1)) = 0.5

        [NoScaleOffset]_HeightTex ("Parallax Texture", 2D) = "white" {}
        _ParallaxOffset("Texture Offset", Range(0,1)) = 0.05
        _Iterations("Texture Iterations", Range(0,20)) = 5
        _CracksPower("Red Power", Range(0,50)) = 2
        _CracksColor("Red Color", Color) = (1,1,1,1)
        _StarsPower("Green Power", Range(0,50)) = 2
        _StarsColor("Green Color", Color) = (1,1,1,1)
        
        


    }
    SubShader
    {
        Tags { "Queue"="Geometry" "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        HLSLINCLUDE
        #include "Assets/Shaders/AnaelToonShader.hlsl"
        #define UNITY_INITIALIZE_OUTPUT(type,name) name = (type)0;

        CBUFFER_START(UnityPerMaterial)
        float4      _MainTex_ST;
        float4      _HeightTex_ST;
        float       _ParallaxOffset;
        float       _Iterations;
        float       _CracksPower;
        float4      _CracksColor;
        float       _StarsPower;
        float4      _StarsColor;     
        float       _ReflectionStrength;
        float       _ReflectionSmoothness;
        float4      _ReflectionTex_ST;
        float       _ReflectionOpacity;
        float4      _NormalTex_ST;
        CBUFFER_END
        TEXTURE2D(_MainTex);              SAMPLER(sampler_MainTex);
        TEXTURE2D(_HeightTex);            SAMPLER(sampler_HeightTex);
        TEXTURE2D(_ReflectionTex);            SAMPLER(sampler_ReflectionTex);
        TEXTURE2D(_NormalTex);            SAMPLER(sampler_NormalTex);
        
        //--------------------------------------------------------------------------ATTRIBUTES------------------------------------------------------------------------------------
        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normal : NORMAL;
            float4 tangentWS : TANGENT;
            float2 uv : TEXCOORD0;
             UNITY_VERTEX_INPUT_INSTANCE_ID    
        };
        //--------------------------------------------------------------------------VARYINGS--------------------------------------------------------------------------------------
        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 viewDir : TEXCOORD1;
            float3 viewDirTangent : TEXCOORD2;
            float3 positionWS : TEXCOORD3;
            float3 normalWS : TEXCOORD4;
            float3 T : TEXCOORD5;
            float3 B : TEXCOORD6;
        };

        ENDHLSL


        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex VertShader
            #pragma fragment FragShader
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            //----------------------------------------------------------------------HELPER FUNCTIONS------------------------------------------------------------------------------
            float4 BlendOverlayShadergraph(float4 Base, float4 Blend, float Opacity)
            {
                float4 result1 = 1.0 - 2.0 * (1.0 - Base) * (1.0 - Blend);
                float4 result2 = 2.0 * Base * Blend;
                float4 zeroOrOne = step(Base, 0.5);
                float4 output = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
                return  lerp(Base, output, Opacity);
            }
            //----------------------------------------------------------------------VERTEX SHADER---------------------------------------------------------------------------------
            Varyings VertShader(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                Light light = GetMainLight();

                float4 worldPosition = (mul(unity_ObjectToWorld, IN.positionOS));
                float3 lightDir = worldPosition.xyz - light.direction.xyz;
                float3 viewDir = normalize(lightDir);
                viewDir = normalize(worldPosition.xyz - _WorldSpaceCameraPos.xyz);
                OUT.viewDir = viewDir;

                OUT.uv = IN.uv;
                float3 worldNormal = mul((float3x3)unity_ObjectToWorld, IN.normal);
                OUT.normalWS = normalize(worldNormal);
                float3 worldTangent = mul((float3x3)unity_ObjectToWorld, IN.tangentWS.xyz);
                    float3 binormal = cross(IN.normal, IN.tangentWS.xyz);
                    float3 worldBinormal = mul((float3x3)unity_ObjectToWorld, binormal);
                    OUT.T = normalize(worldTangent);
                    OUT.B = normalize(worldBinormal);

                float tangentSign = IN.tangentWS.w * unity_WorldTransformParams.w;
                float3 bitangent  = cross(IN.normal.xyz,IN.tangentWS.xyz) * tangentSign;
                OUT.viewDirTangent = float3(
                                     dot(viewDir, IN.tangentWS.xyz),
                                     dot(viewDir, bitangent.xyz),
                                     dot(viewDir, IN.normal.xyz));
                
                VertexPositionInputs posIN = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = posIN.positionCS;
                OUT.positionWS = posIN.positionWS;
                
                return OUT;
            }
            //----------------------------------------------------------------------FRAGMENT SHADER-------------------------------------------------------------------------------
            float4 FragShader(Varyings IN) : SV_TARGET
            {
                // Main Map
                float4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,IN.uv);
                // Normal Map
                float3 normalTex = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, IN.uv));
                // Specular Map
                float4 reflectionTex = SAMPLE_TEXTURE2D(_ReflectionTex, sampler_ReflectionTex,IN.uv).b;

                float3 normalWS = TransformTangentToWorld(normalTex,half3x3(IN.T, IN.B, IN.normalWS));
                normalWS = normalize(normalWS);
                // Specular reflection
                float4 reflectionColor = float4(1,1,1,1);
                InitSpecular(_ReflectionStrength,_ReflectionSmoothness, reflectionColor,reflectionColor, reflectionColor,1);
                float reflectionAmount = reflectionTex.r;
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                float4 reflectionRamp = ReflectionRamp(shadowCoord,normalWS, IN.positionWS) * reflectionAmount; //(_ReflectionOpacity+ reflectionAmount);

                // Parallax loop
                //float3 heightOffset = _ParallaxOffset * normalize(IN.viewDirTangent);
                float height = 0;
                float stars = 0;
                for (int i = 0; i<_Iterations; i++)
                {
                    float ratio = (float) i/_Iterations;
                    height += SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, IN.uv + (lerp(0.1,_ParallaxOffset,ratio) * normalize(IN.viewDirTangent)).xy).r * lerp(1,0,ratio);
                    stars += SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, IN.uv + (lerp(0.1,_ParallaxOffset + 0.5,ratio) * normalize(IN.viewDirTangent)).xy).g * lerp(1,0,ratio);
                }
                height /= _Iterations;
                float4 heightColor =height * _CracksPower * _CracksColor;
                stars /= _Iterations;
                float4 starsColor = stars * _StarsPower * _StarsColor;
                float4 blendTex = BlendOverlayShadergraph(mainTex, heightColor + starsColor, 0.5);
                return blendTex + reflectionRamp;
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
    CustomEditor "CustomParallaxShaderGUI"
}
