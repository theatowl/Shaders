#ifndef ANAEL_COMMON_LIBRARY_INCLUDED
#define ANAEL_COMMON_LIBRARY_INCLUDED


#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

float   _ToonShadowOffset;
float   _ToonShadowSmoothness;
float4  _ToonShadowColor;
float4  _ToonShadowColor2;
float4  _ToonShadowColor3;
float   _ToonShadowGradientStretch;

float   _ToonSpecularStrength;
float   _ToonSpecularSmoothness;
float4  _ToonSpecularColor1;
float4  _ToonSpecularColor2;
float4  _ToonSpecularColor3;
float   _ToonSpecularGradientStretch;

float   _ToonRimAmount;
float   _ToonRimThreshold;
float4  _ToonRimColor;




void InitToon(float shadowOffset, float shadowSmoothness, float4 shadowColor, float4 shadowColor2, float4 shadowColor3, float shadowGradientStretch )
{
    _ToonShadowOffset = shadowOffset;
    _ToonShadowSmoothness = shadowSmoothness;
    _ToonShadowColor = shadowColor;
    _ToonShadowColor2 = shadowColor2;
    _ToonShadowColor3 = shadowColor3;
    _ToonShadowGradientStretch = shadowGradientStretch;
}

void InitSpecular(float specStrength, float specSmoothness, float4 specularColor1, float4 specularColor2, float4 specularColor3, float specularGradientStretch)
{
    _ToonSpecularStrength = specStrength;
    _ToonSpecularSmoothness = specSmoothness;
    _ToonSpecularColor1 = specularColor1;
    _ToonSpecularColor2 = specularColor2;
    _ToonSpecularColor3 = specularColor3;
    _ToonSpecularGradientStretch = specularGradientStretch;

}

void InitRim(float toonRimAmount, float toonRimTreshold, float4 rimColor)
{
    _ToonRimAmount = toonRimAmount;
    _ToonRimThreshold = toonRimTreshold;
    _ToonRimColor = rimColor;
}


float4 BlendMultiply(float4 Base, float4 Blend, float Opacity)
            {
                
                float4 OUT = (Base*Blend);
                OUT = lerp(Base,OUT,Opacity);
                return OUT;
            }

float4 BlendOverlay(float4 Base, float4 Blend, float Opacity)
            {
                float4 result1 = 1.0 - 2.0 * (1.0 - Base) * (1.0 - Blend);
                float4 result2 = 2.0 * Base * Blend;
                float4 zeroOrOne = step(Base, 0.5);
                float4 output = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
                return  lerp(Base, output, Opacity);
            }

float4 Gradient(float4 Color1, float4 Color2, float4 Color3, float GradientStretch)
            {
               float4 mixColor1Color2 = lerp(Color1, Color2, GradientStretch);
               float4 mixGradient = lerp(mixColor1Color2, Color3, GradientStretch);
               return mixGradient;
            }


float4 ToonRamp(float4 shadowCoord, float3 normal, float3 worldPos)
            {
                
                float shadowMap = MainLightRealtimeShadow(shadowCoord);
                 // grab the main light
                #if _MAIN_LIGHT_SHADOWS_CASCADE || _MAIN_LIGHT_SHADOWS 
                    Light mainLight = GetMainLight(shadowCoord);
                #else
	                Light mainLight = GetMainLight(shadowCoord); 
                #endif

                float mainLightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                float4 lightColor = float4(mainLight.color, 1);

                // Main Light shadows with the dot product
	            float d = dot(mainLight.direction, normal)* 0.5 + 0.5 ;
                float combinedShadows = min(d, shadowMap);
                float lightIntensity = d>0?1 : 0;

                // Smoothstep the shadows 
	            float toonRamp = smoothstep( _ToonShadowOffset ,  _ToonShadowOffset + _ToonShadowSmoothness, combinedShadows);
                
                // Additional Lights
                float4 addLights = 0;
                #if _ADDITIONAL_LIGHTS
                    int additionalLightsCount = GetAdditionalLightsCount();
                    for (int i = 0; i<additionalLightsCount; ++i)
                    {
                        Light light = GetAdditionalLight(i,worldPos);
                        float lightAttenuation =  smoothstep(light.shadowAttenuation , light.shadowAttenuation + 0.01,light.distanceAttenuation * 10);
                        float4 addlightColor = (float4(light.color, 1) * lightAttenuation );
                        
                        float d = (dot(light.direction, normal)* 0.5 + 0.5);
                        float combinedShadows = min(d, shadowMap);
                        float lightIntensity = d>0?1 : 0;
                        float addtoonRamp = smoothstep( _ToonShadowOffset ,  _ToonShadowOffset + _ToonShadowSmoothness, combinedShadows);
                        addLights += addtoonRamp * addlightColor;
                    }
                #endif
                toonRamp *= mainLightAttenuation;
                //shadow color
                float4 toonRampTinting = Gradient(_ToonShadowColor,_ToonShadowColor2,_ToonShadowColor3, (clamp(d,0,1) *  _ToonShadowGradientStretch ));
                
                float4 baseColor = toonRamp * lightColor;
                baseColor += addLights;
                float4 toonRampOutput = clamp((1-toonRamp),0,1) * toonRampTinting;
                float4 toonLighting = baseColor + toonRampOutput;

                return toonLighting;
            }


 float4 ReflectionRamp(float4 shadowCoord,float3 normal, float3 worldPos)
            {
                 // grab the main light
                #if _MAIN_LIGHT_SHADOWS_CASCADE || _MAIN_LIGHT_SHADOWS 
                    Light mainLight = GetMainLight(shadowCoord);
                #else
	                Light mainLight = GetMainLight(shadowCoord); 
                #endif
                float mainLightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                //Specular   
                float3 halfVector = normalize(mainLight.direction);
                //View direction
                float3 viewDir = normalize(GetWorldSpaceViewDir(worldPos));
                //dot product for blinn phong model
                float NdotH = dot(halfVector, normal);
                NdotH *= dot(viewDir, normal) * 1.25;
                //Smoothstep for toon
                float reflectionIntensitySmoothstep = smoothstep( _ToonSpecularStrength, _ToonSpecularSmoothness + _ToonSpecularStrength, NdotH);
                reflectionIntensitySmoothstep *= mainLightAttenuation;

                float4 addLights = 0;
                 //Additional lights
                #if _ADDITIONAL_LIGHTS
                    int additionalLightsCount = GetAdditionalLightsCount();
                    for (int i = 0; i<additionalLightsCount; ++i)
                    {
                        Light light = GetAdditionalLight(i, worldPos);
                        float lightAttenuation =  smoothstep(light.shadowAttenuation , light.shadowAttenuation + 0.01 ,light.distanceAttenuation);
                        float4 addlightColor = (float4(light.color, 1) * lightAttenuation );
                        
                        float3 halfVector = normalize(light.direction) * lightAttenuation;
                        float NdotH = (dot(normal, halfVector) * 0.5 + 0.5) * lightAttenuation;
                        NdotH *= dot(viewDir, normal) * 1.25;
                        reflectionIntensitySmoothstep += smoothstep( _ToonSpecularStrength, _ToonSpecularSmoothness + _ToonSpecularStrength, NdotH) * lightAttenuation;
                        
                    }
                #endif

                //specular color
                float4 reflectionTinting = Gradient(_ToonSpecularColor1,  _ToonSpecularColor2 , _ToonSpecularColor3,(clamp(NdotH, 0,1) * _ToonSpecularGradientStretch) );
                float4 reflectionColor = reflectionIntensitySmoothstep  *  reflectionTinting;
                return reflectionColor;
            }


float4 RimRamp(float4 shadowCoord, float3 normal, float3 worldPos)
            {
                // grab the main light
                #if _MAIN_LIGHT_SHADOWS_CASCADE || _MAIN_LIGHT_SHADOWS 
                    Light mainLight = GetMainLight(shadowCoord);
                #else
	                Light mainLight = GetMainLight(shadowCoord); 
                #endif
                float mainLightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                // RimLight
                float d = dot(mainLight.direction, normal)* 0.5 + 0.5 ;
                //View direction
                float3 viewDir = normalize(GetWorldSpaceViewDir(worldPos));
                //dot product for rim
                float4 rimDot = 1 - dot(viewDir, normal);
                float floatRimDot = rimDot.x * rimDot.y * rimDot.z * rimDot.w;
                float rimIntensitydot = floatRimDot* pow(abs(d), _ToonRimThreshold);
                float rimIntensity = smoothstep(_ToonRimAmount - 0.01, _ToonRimAmount + 0.01, rimIntensitydot);
                rimIntensity *= mainLightAttenuation;

                float4 addLights = 0;
                 //Additional lights
                #if _ADDITIONAL_LIGHTS
                    int additionalLightsCount = GetAdditionalLightsCount();
                    for (int i = 0; i<additionalLightsCount; ++i)
                    {
                        Light light = GetAdditionalLight(i, worldPos);
                        float lightAttenuation =  smoothstep(light.shadowAttenuation , light.shadowAttenuation + 0.01,light.distanceAttenuation);
                        
                        float d = (dot(light.direction, normal)* 0.5 + 0.5) * lightAttenuation;
                        float4 rimDot = 1 - dot(viewDir, normal);
                        float floatRimDot = rimDot.x * rimDot.y * rimDot.z * rimDot.w;
                        float rimIntensitydot = floatRimDot* pow(abs(d), _ToonRimThreshold);
                        rimIntensity += smoothstep(_ToonRimAmount - 0.01, _ToonRimAmount + 0.01, rimIntensitydot) * lightAttenuation;   
                    }
                #endif
                
                float4 rim = rimIntensity * _ToonRimColor;
                return rim;
            }



#endif