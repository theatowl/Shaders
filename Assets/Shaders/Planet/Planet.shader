Shader "Singularity/Planet"
{
    Properties
    {
        [NoScaleOffset]_MainTex ("Texture", 2D) = "white" {}
        _Tiling("Tiling",float) = 1
        _Offset("Offset", float) = 0

        [NoScaleOffset]_FlowMap("Flow Map", 2D) = "white" {}
        [NoScaleOffset]_GradientMap("Gradient Map",2D) = "white"{}

        [HDR]_Color("color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (1,1,1,1)
        _Radius("Radius",float) = 1
        _RimAmount("Rim Amount", float) = 1
        _RimThreshold("Rim Threshold", float) = 1
        _Octaves("fBM octaves", Integer) = 10
    }
    SubShader
    {
        Tags { "Queue"="Geometry" "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        HLSLINCLUDE
        #include "Assets/Shaders/AnaelToonShader.hlsl"
        
        #include "Assets/Shaders/NoiseGenerator.hlsl"

        #define MAX_DISTANCE 100
        #define MAX_STEP 100
        #define MIN_RADIUS 0.001


        CBUFFER_START(UnityPerMaterial)
        float4  _MainTex_ST;
        float4 _FlowMap_ST;
        float4 _GradientMap_ST;
        float _Tiling;
        float _Offset;
        float4 _Color;
        float4 _ShadowColor;
        float   _Radius;
        float _RimAmount;
        float _RimThreshold;
        int _Octaves;

        TEXTURE2D(_MainTex);     SAMPLER(sampler_MainTex);
        TEXTURE2D(_FlowMap);     SAMPLER(sampler_FlowMap);
        TEXTURE2D(_GradientMap); SAMPLER(sampler_GradientMap);
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
            float3 normal : NORMAL;
        };
        struct Varyings
        {
            float4 positionCS : SV_Position;
            float2 uv : TEXCOORD0;
            float3 rayOrigin : TEXCOORD1;
            float3 rayDirection : TEXCOORD2;
            float3 positionWS : TEXCOORD3;
            float3 viewDir : TEXCOORD4;
        };
        ENDHLSL

        Pass
        {
            //Blend One One
            ZWrite On

           HLSLPROGRAM
           
            #pragma vertex vertShader
            #pragma fragment fragShader
           Varyings vertShader(Attributes IN)
           {
               Varyings OUT = (Varyings)0;
               VertexPositionInputs posIN = GetVertexPositionInputs(IN.positionOS.xyz);
               OUT.positionCS = posIN.positionCS;
               OUT.positionWS = posIN.positionWS;
               OUT.uv = IN.uv;
               float3 cameraPosition = GetCameraPositionWS();
               OUT.rayOrigin = TransformWorldToObject(cameraPosition);
               OUT.rayDirection = IN.positionOS - OUT.rayOrigin;
               OUT.viewDir = GetWorldSpaceViewDir(IN.positionOS);
               return OUT;
           }

           float SDF(float3 p)
           {
               return length(p) - _Radius;
           }

           float3 planetNormal (float3 position)
           {
               float epsilon = 0.0001;
               float2 h = float2(epsilon,0);
               return normalize(float3(SDF(position + h.xyy) - SDF(position - h.xyy),
                                       SDF(position + h.yxy) - SDF(position - h.yxy),
                                       SDF(position + h.yyx) - SDF(position - h.yyx))); 
           }

           //fBM ressources
           //https://iquilezles.org/articles/fbm/
           //https://styly.cc/tips/unity-shader-domainwarping-dotpattern/
           //https://gist.github.com/sneha-belkhale/d944211b9af1e3575392d4e460676f30
           //https://www.shadertoy.com/view/tltXWM

           float noise(float2 uv)
           {
               float2 i = floor(uv);
               float2 u = smoothstep(0,1,frac(uv));
               float a = Random2dTo1d(i + float2(0,0));
               float b = Random2dTo1d(i + float2(1,0));
               float c = Random2dTo1d(i + float2(0,1));
               float d = Random2dTo1d(i + float2(1,1));
               float r = lerp(lerp(a,b,u.x), lerp(c,d,u.x), u.y);
               return r * r;
           }

           float fBM(float2 uv, int octaves)
           {
               float value = 0.0;
               float amplitude = 0.5;
               float e = 3;
               for(int i = 0; i<octaves; i++)
               {
                   value += amplitude * noise(uv);
                   uv = uv * e;
                   amplitude *= 0.5;
                   e *= 0.95;
               }
               return value;
           }

           float4 fragShader(Varyings IN, out float depth : SV_Depth) : SV_Target
           {
               Light mainLight = GetMainLight();
                 
               float3 ro = IN.rayOrigin;
               float3 rd =  normalize(IN.rayDirection);
               float3 position;
               float t = 0;
               for (int i; i< MAX_STEP && i<MAX_DISTANCE; i++)
               {
                   position = ro + t * rd;
                   float d = SDF(position);

                   if(d< MIN_RADIUS)
                   {
                       break;
                   }
                   t += d;
               }
               if (t>= MAX_DISTANCE)
               {discard;}

               

               float3 normal = planetNormal(position);
               //Shadows
               float d = dot(normal, normalize(mainLight.direction)) * 0.5 + 0.5;
               float shadows = smoothstep( 0.3 ,  0.3 + 0.5, d);
               

               float4 clipPosition = mul(UNITY_MATRIX_MVP, float4(position,1));
               depth = clipPosition.z / clipPosition.w;

               //FlowMap
               //float2 flowMap = SAMPLE_TEXTURE2D(_FlowMap,sampler_FlowMap, IN.uv * _Tiling + _Offset).xy;
               //flowMap = (flowMap - 0.5) * 2;
               //float niceTime1 = frac(_Time.y * 0.005);
               //float niceTime2 = frac(niceTime1 + 0.5);
               //float flowMix = abs((niceTime1 - 0.5)*2);

               //float4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv * _Tiling + _Offset + (flowMap * niceTime1 * 0.1));
               //float4 mainTex2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv * _Tiling + _Offset + (flowMap * niceTime2 * 0.1));
               //float4 lerpedTex = lerp(mainTex,mainTex2, flowMix);

               float f = fBM(IN.uv + fBM(5 * IN.uv + _Time.y * 0.002, _Octaves), _Octaves);
               float f2 = fBM(IN.uv + fBM(6 * IN.uv + _Time.y * 0.001, _Octaves), _Octaves) ;
               float ff = f - f2 + 0.5;
               ff= smoothstep(0.1,1,ff);

               float4 coloredTex = SAMPLE_TEXTURE2D(_GradientMap, sampler_GradientMap, ff);
               //float4 coloredTex = SAMPLE_TEXTURE2D(_GradientMap, sampler_GradientMap, lerpedTex);

               //Fresnel effect for atmosphere
               float3 viewDir = normalize(GetWorldSpaceViewDir(IN.positionWS));
               float fresnel = 1 - pow((1 - saturate(dot(normal,viewDir))),1);

               float4 color = BlendMultiply(coloredTex, shadows, 1);

               color.a = fresnel;
               return color * fresnel ;// + (lightFresnel * _Color);

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
                Varyings output = (Varyings)0;
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
        /*Pass 
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
        }*/
    }
}

