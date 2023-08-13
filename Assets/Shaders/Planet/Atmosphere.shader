Shader "Singularity/Atmosphere"
{
    Properties
    {
        [NoScaleOffset]_GradientMap("Gradient Map",2D) = "white"{}

        [HDR]_Color("color", Color) = (1,1,1,1)
        _Radius("Radius",float) = 1
        _PlanetSize("Planet Size", float) = -1
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        HLSLINCLUDE
        #include "Assets/Shaders/AnaelToonShader.hlsl"

        #define MAX_DISTANCE 100
        #define MAX_STEP 100
        #define MIN_RADIUS 0.001


        CBUFFER_START(UnityPerMaterial)
        float4 _GradientMap_ST;
        float4 _Color;
        float   _Radius;
        float _PlanetSize;

        TEXTURE2D(_GradientMap); SAMPLER(sampler_GradientMap);
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
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
           Blend SrcAlpha OneMinusSrcAlpha
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
               float shadows = smoothstep( 0.5 ,  0.5 + 0.2, d);

               float4 clipPosition = mul(UNITY_MATRIX_MVP, float4(position,1));
               depth = clipPosition.z / clipPosition.w;



               //Fresnel effect for atmosphere
               float3 viewDir = normalize(GetWorldSpaceViewDir(IN.positionWS));
               //Outer atmosphere
               float rimFresnel = 1- pow((1 - saturate(dot(normal,viewDir))),0.01);
               float innerFresnel = pow((1 - saturate(dot(normal,viewDir))),_PlanetSize);
               float outerAtmo = rimFresnel * innerFresnel;

               //Planet
               float planet = 1- outerAtmo;
               float planetDepth = 0.2 * clamp(outerAtmo,0,1);

               float atmo = clamp(outerAtmo * planet, 0, 1);

               float planetAtmosphere  = atmo + planetDepth;

               float lightFresnel = planetAtmosphere * (shadows * 2);
               
               float4 coloredTex = SAMPLE_TEXTURE2D(_GradientMap, sampler_GradientMap, float2(planetAtmosphere, planetAtmosphere));
               coloredTex.a = lightFresnel;
               return coloredTex;

           }

           ENDHLSL
        }
       
    }
}

