Shader "Custom/SnowShader"
{
    Properties
    {
        _MainColor("Snow Color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (1,1,1,1)
        [Normal]_MainTex("Snow Normal", 2D) = "bump"{}
        [Normal]_GlitterTex("Snow Glitter", 2D) = "bump"{}
        _GlitterColor("Glitter Color", Color) = (1,1,1,1)
        _GlitterThreshold("Glitter Threshold", Range(0,1)) = 1
        [NoScaleOffset]_TrailTex ("Trail Texture", 2D) = "white" {}
        _FactorUniform("Tessellation Factor", Range(1,32)) = 1
        _TessellationBias("Tessellation Bias", float) = 1
        _MaxTessellationDistance("max Tessellation Distance", float) = 10
        _DisplacementStrength("Displacement Strength", Range(0,1)) = 0
        _RimPower("Rim Power", Range(0,10)) = 1
        _RimStrength("Rim Strength", Range(0,1)) = 1

        _DisplacementTexDimY("Displacement Texture Y dimension", float) = 1
        _DisplacementTexDimX("Displacement Texture X dimension", float) = 1

        _SandStrength("strength", float) = 1

    }
    SubShader
    {
        Tags{ "Queue" = "Geometry" "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        #define UNITY_INITIALIZE_OUTPUT(type,name) name = (type)0;

        CBUFFER_START(UnityPerMaterial)
        float4 _MainColor;
        float4 _ShadowColor;
        float4 _MainTex_ST;
        float4 _GlitterTex_ST;
        float4 _GlitterColor;
        float  _GlitterThreshold;
        float4 _TrailTex_ST;
        float  _FactorUniform;
        float  _TessellationBias;
        float  _DisplacementStrength;
        float  _MaxTessellationDistance;
        float  _RimPower;
        float  _RimStrength;
        float3 _MainCameraPosition;
        float  _DisplacementTexDimY;
        float  _DisplacementTexDimX;

        float _SandStrength;
        CBUFFER_END

        TEXTURE2D(_TrailTex);                       SAMPLER(sampler_TrailTex);
        TEXTURE2D(_MainTex);                        SAMPLER(sampler_MainTex);
        TEXTURE2D(_GlitterTex);                     SAMPLER(sampler_GlitterTex);
        
        ENDHLSL

        Pass
        {
            HLSLPROGRAM

            //5.0  required for tessellation
            #pragma target 5.0 

            #pragma vertex VertShader

            //Receives data in form of patches, aka lists of vertices (tris, for example)
            //A patch is an array of vertices that contains output data from the vertex shader corresponding to each vertex
            //The hull function also receives an index specifyingwhich vertex in the patch it must output data for
            //It runs once per vertex in the patch and can look at all the vertices in the patch to produce a new data structure
            //for later in the chain
            //Running in parallel is the patch constant function that runs once per patch and outputs tessellation factors
            #pragma hull Hull 

            //Runs for each vertex on the tessellated mesh and outputs the final data for a vertex
            //This is where we'll do our displacements
            #pragma domain Domain

            #pragma fragment FragShader
            
            
            //------------------------------------------------------------------------------------------
            //STRUCTS
            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 tangentWS : TANGENT;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct TessellationControlPoint //Varyings, the data that will be fed to the hull function
            {
                float3 positionWS : INTERNALTESSPOS; //SV_POSITION interdit : décrit l'emplacement des pixels; hors on ne passera
                //la position en clip space qu'au stade du domain
                float3 normalWS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 tangentWS : TANGENT;
                float3 binormalWS : BINORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TESSFACTOR;
                float inside : SV_INSIDETESSFACTOR;
                float3 normalWS : NORMAL;
                float4 tangentWS : TANGENT;
                float3 binormalWS : BINORMAL;
                //float3 bezierPoints[NUM_BEZIER_CONTROL_POINTS] : BEZIERPOS;
            };

            struct Interpolators
            {
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 T : TEXCOORD3;
                float3 B : TEXCOORD4;
                float3 viewDir : TEXCOORD5;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            
            
            
            
            //------------------------------------------------------------------------------------------
            //HELPER FUNCTIONS
            float3 nlerp(float3 n1, float3 n2, float t)
            {
                return normalize(lerp(n1,n2,t));
            }

            float3 SnowNormal (Interpolators IN)
            {
                float3 normalTex = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, TRANSFORM_TEX(IN.uv,_MainTex)));
                float3 random = TransformTangentToWorld(normalTex,half3x3(IN.T, IN.B, IN.normalWS));

                float3 S = normalize(normalTex);
                float3 Ns = nlerp(IN.normalWS, S, _SandStrength);
                return S;
            }

            float3 DiffuseLightingJourney( Light light, float3 normal)
            {
                float3 L = light.direction;
                float3 N = normal;
                float diffuseLighting = saturate( 4 * dot(N,L));
                float3 diffuseColor = lerp(_ShadowColor, _MainColor, diffuseLighting );
                return diffuseColor;
            }
           

            float3 blendMultiply(float3 Base, float3 Blend, float Opacity)
            {
                
                float3 OUT = (Base*Blend);
                OUT = lerp(Base,OUT,Opacity);
                return OUT;
            }

            float3 GlitterSpecular(float2 uv, float3 normal, Light light, float3 viewDir, float3 T, float3 B)
            {
                float3 normalTex = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D(_GlitterTex, sampler_GlitterTex, TRANSFORM_TEX(uv,_GlitterTex)));
                float3 random = TransformTangentToWorld(normalTex,half3x3(T, B,normal));
                
                float3 randomGlitter = normalize(normalTex.rgb );
                //Light that reflects on the glitter and hits the eye
                float3 reflection = reflect(light.direction, randomGlitter);
                float rDotV = max(0, dot(reflection, viewDir));
                //Keep only the strong reflection
                if(rDotV < _GlitterThreshold)
                return 0;
                float depth = SAMPLE_TEXTURE2D(_TrailTex, sampler_TrailTex, uv).r * SAMPLE_TEXTURE2D(_TrailTex, sampler_TrailTex, uv).g;

                return (rDotV * (1-depth)) * _GlitterColor;
            }

            float DistanceTessellationFactor(float3 vertex, float minDist, float maxDist, float tess)
            {
                float3 worldPosition = mul(unity_ObjectToWorld, vertex).xyz;
                float dist = distance(worldPosition, _MainCameraPosition);
                float factor = clamp(1.0 - (dist - minDist) / (maxDist - minDist),0.01,1.0);
                return factor * tess;
            }

            float EdgeTessellationFactor(float scale, float bias, float3 p0PositionWS, float3 p1PositionWS, float multiplier)
            {
                float length = distance(p0PositionWS, p1PositionWS);
                float distanceToCamera = distance(_MainCameraPosition, (p0PositionWS + p1PositionWS) * 0.5);
                float factor = scale;
                return max(1,(factor + bias) * multiplier);
            }

            float3 HeightToNormal(float height, float3 normal, float3 pos)
            {
                float3 worldDirivativeX = ddx(pos);
                float3 worldDirivativeY = ddy(pos);
                float3 crossX = cross(normal, worldDirivativeX);
                float3 crossY = cross(normal, worldDirivativeY);
                float3 d = abs(dot(crossY, worldDirivativeX));
                float3 inToNormal = ((((height + ddx(height)) - height) * crossY) + (((height + ddy(height)) - height) * crossX)) * sign(d);
                inToNormal.y *= -1.0;
                return normalize((d * normal) - inToNormal);
            }

            //Rim light
            float RimRamp(Light light, float3 normal, float3 WorldPos)
            {
                // RimLight
                float d = dot(light.direction, normal)* 0.5 + 0.5 ;
                //View direction
                float3 viewDir = normalize(GetWorldSpaceViewDir(WorldPos));
                //dot product for rim
                float4 rimDot = 1 - dot(viewDir, normal);
                float floatRimDot = rimDot.x * rimDot.y * rimDot.z * rimDot.w;
                float rimIntensity = floatRimDot* (pow(abs(d), _RimPower) * _RimStrength);
                
                return rimIntensity;
            }

            float3 nFromH(float2 uv, float3 normal, float3 T, float3 B)
            {
                float displaceTex = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, uv,0).r * SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, uv,0).g;
                float north = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x,uv.y + 1/(10*_DisplacementTexDimY)),0).r * SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x,uv.y + 1/(10 * _DisplacementTexDimY)),0).g;
                float south = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x,uv.y - 1/(10*_DisplacementTexDimY)),0).r *SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x,uv.y - 1/(10 * _DisplacementTexDimY)),0).g;
                float east = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x+ 1/(10*_DisplacementTexDimX),uv.y ),0).r * SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x+ 1/(10*_DisplacementTexDimX),uv.y ),0).g;
                float west = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x - 1/(10*_DisplacementTexDimX),uv.y ),0).r * SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, float2(uv.x - 1/(10*_DisplacementTexDimX),uv.y ),0).g;

                float3 norm = normal;
                float3 n;
                normal.z += west - east;
                normal.x += north - south;
                normal.y += 1;
                return normalize(normal);
                
            }
         
            

            //------------------------------------------------------------------------------------------
            //VERTEX SHADER

            TessellationControlPoint VertShader(Attributes IN)
            {
                TessellationControlPoint OUT = (TessellationControlPoint)0;
                UNITY_SETUP_INSTANCE_ID(IN);

                VertexPositionInputs posIN = GetVertexPositionInputs(IN.positionOS);
                VertexNormalInputs normIN = GetVertexNormalInputs(IN.normalOS);

                OUT.positionWS = posIN.positionWS;
                OUT.normalWS = normIN.normalWS;
                OUT.uv = IN.uv;
                OUT.tangentWS = IN.tangentWS;
                return OUT;
            }
            
            
            
            
            //------------------------------------------------------------------------------------------
            //HULL FUNCTION

            //The hull function runs once per vertex. It can be used to modify vertex data based on values in the entire triange
            [domain("tri")] //Signals we're inputting triangles
            [outputcontrolpoints(3)] //Triangles have 3 points
            [outputtopology("triangle_cw")] //Signals we're outputting triangles
            [patchconstantfunc("PatchConstantFunction")] //Registers the patch constant function
            [partitioning("fractional_odd")] //Selects a partitioning mode : integer, fractional_odd, fractional_even
            //OutputStruct (can be the same as the input or another entirely, keep using INTERNALTESSPOS for the position) Hull(Input from the vertex shader, 3 points per patch, input the vertex id to signal which vertex to output to)
            TessellationControlPoint Hull(InputPatch<TessellationControlPoint,3> patch, uint id : SV_OUTPUTCONTROLPOINTID)
            {
                return patch[id]; //return the correct vertex in the patch 
            }
            //------------------------------------------------------------------------------------------
            //PATCH FUNCTION
            
            //The patch function runs once per patch, in parallel to the hull function
            //It receives the same input as the hull function but outputs to its own data structure which contains the tessellation
            //factors specified per edge on the triangle using SV_TESSFACTOR
            //Edges are arranges opposite of the vertex with the same index : edge 0 lies between vertices 1 and 2, edge 1 between v0 and v2, etc
            //There's also a center tessellation factor tagged with SV_INSIDETESSFACTOR
            //The edge factor is the number of times an edge subdivides and the inside factor squared is roughly the number
            //of new triangles created inside the original
            TessellationFactors PatchConstantFunction(InputPatch<TessellationControlPoint,3> patch)
            {
                UNITY_SETUP_INSTANCE_ID(patch[0]); //Set up instancing
                TessellationFactors f = (TessellationFactors)0;
                float minDist = 5.0;
                float maxDist = _MaxTessellationDistance;

                //Texture Based Tessellation @Mr_Admirals
                float p0Factor = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, patch[0].uv.xy,0).r;
                float p1Factor = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, patch[1].uv.xy,0).r;
                float p2Factor = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, patch[2].uv.xy,0).r;
                float factor = (p0Factor + p1Factor + p2Factor);

                //Edge Length Based Tessellation @NedMakesGames
                float e0F = EdgeTessellationFactor(_FactorUniform,_TessellationBias,patch[1].positionWS,patch[2].positionWS, (p1Factor + p2Factor) / 2);
                float e1F = EdgeTessellationFactor(_FactorUniform,_TessellationBias,patch[2].positionWS,patch[0].positionWS, (p0Factor + p2Factor) / 2);
                float e2F = EdgeTessellationFactor(_FactorUniform,_TessellationBias,patch[0].positionWS,patch[1].positionWS, (p1Factor + p0Factor) / 2);
                
                //Distance Based Tessellation (@MinionsArt)
                float edge0 = DistanceTessellationFactor(patch[0].positionWS, minDist, maxDist, _FactorUniform);
                float edge1 = DistanceTessellationFactor(patch[1].positionWS, minDist, maxDist, _FactorUniform);
                float edge2 = DistanceTessellationFactor(patch[2].positionWS, minDist, maxDist, _FactorUniform);

                //Calculate tessellation factors
                f.edge[0] = ((edge1 + edge2) / 2) + e0F ;//(factor * ((edge1 + edge2) / 2))>0.5 ? _FactorUniform : 1.0 ;//(edge1 + edge2) / 2;//
                f.edge[1] = ((edge0 + edge2) / 2) + e1F;//(factor * ((edge0 + edge2) / 2))>0.5 ? _FactorUniform : 1.0 ;//(edge2 + edge0) / 2;//
                f.edge[2] = ((edge1 + edge0) / 2) + e2F;//(factor * ((edge1 + edge0) / 2))>0.5 ? _FactorUniform : 1.0 ;//(edge0 + edge1) / 2;//
                f.inside = ((edge0 + edge1 + edge2)/3) + (f.edge[0] + f.edge[1] + f.edge[2])/3;//(factor * ((edge0 + edge1 + edge2)/3))>0.5 ? _FactorUniform : 1.0 ;//
                return f;
            }





            





            //------------------------------------------------------------------------------------------
            //DOMAIN STAGE

            //Call this macro to interpolate between a triangle patch, passing the field name
            #define BARYCENTRIC_INTERPOLATE(fieldName) \
                            patch[0].fieldName * barycentricCoordinates.x + \
                            patch[1].fieldName * barycentricCoordinates.y + \
                            patch[2].fieldName * barycentricCoordinates.z


            //The domain function runs once per vertex in the final tessellated mesh
            //Use it to reposition vertices and prepare for the fragment stage
            [domain("tri")] //Signals we're inputting triangles
            //Outputs to Interpolators Domain(Input the output of the patch function, describe the input triangle, input the barycentric coordinates of the vertex on the triangle)
            Interpolators Domain(TessellationFactors factors, OutputPatch<TessellationControlPoint,3> patch, float3 barycentricCoordinates : SV_DOMAINLOCATION)
            {
                Interpolators OUT = (Interpolators)0;

                //Set up instancing and stereo support (for VR)
                UNITY_SETUP_INSTANCE_ID(patch[0]);
                UNITY_TRANSFER_INSTANCE_ID(patch[0], OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionWS = BARYCENTRIC_INTERPOLATE(positionWS);
                float3 normalWS = BARYCENTRIC_INTERPOLATE(normalWS);
                float2 uv = BARYCENTRIC_INTERPOLATE(uv);
                float4 tangentWS = BARYCENTRIC_INTERPOLATE(tangentWS);
                float4 displacementMap = SAMPLE_TEXTURE2D_LOD(_TrailTex, sampler_TrailTex, uv,0);
                float displacementUp = displacementMap.g;
                float displacementDown = displacementMap.r;
                float displacement = (1-displacementDown) * (_DisplacementStrength + (displacementUp * 0.1));

                Light light = GetMainLight();
                float4 worldPosition = (mul(unity_ObjectToWorld, positionWS));
                float3 lightDir = worldPosition.xyz - light.direction.xyz;
                float3 viewDir = normalize(lightDir);
                viewDir = normalize(worldPosition.xyz - _WorldSpaceCameraPos.xyz);
                OUT.viewDir = viewDir;
                
                normalWS = normalize(normalWS);
                normalWS += displacement; 
                positionWS.y += normalWS * displacement;
                
                
                    float3 worldTangent = mul((float3x3)unity_ObjectToWorld, tangentWS);
                    float3 binormal = cross(normalWS,tangentWS.xyz);
                    float3 worldBinormal = mul((float3x3)unity_ObjectToWorld, binormal);

               
                OUT.normalWS = normalize(cross(worldTangent,worldBinormal));
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.B = worldBinormal;
                OUT.T = worldTangent;
                OUT.positionWS = positionWS;
                OUT.uv = uv;

                return OUT;
            }
            
            
            
            
            
            //------------------------------------------------------------------------------------------
            //FRAGMENT SHADER

            float3 FragShader(Interpolators IN) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                

                float depth = SAMPLE_TEXTURE2D(_TrailTex, sampler_TrailTex, IN.uv).r * SAMPLE_TEXTURE2D(_TrailTex, sampler_TrailTex, IN.uv).g;
                float3 trailNormal = normalize(nFromH(IN.uv, IN.normalWS,IN.T, IN.B));
                //Main normal map
                float3 normalTex = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, TRANSFORM_TEX(IN.uv, _MainTex)));
                float3 normalWS = TransformTangentToWorld(normalTex,half3x3(IN.T, IN.B, trailNormal));
                normalWS = normalize(normalWS);
                

                //Glitter specular
                float3 glitter = GlitterSpecular(IN.uv,IN.normalWS, mainLight, IN.viewDir, IN.T, IN.B);
                
                //Rim Light
                float rim = RimRamp(mainLight, trailNormal, IN.positionWS);

                float3 diffuseLight = DiffuseLightingJourney(mainLight,trailNormal); //ToonRamp(mainLight, shadowCoord,normal);
                float4 shadowColor = _ShadowColor;

                float3 snowColor = diffuseLight * lerp(_MainColor,_ShadowColor, depth);
                return snowColor + glitter + rim;

            }

            ENDHLSL

        }
        
    }
}
