#include "common.hlsl"

cbuffer Local : register(b1, space3){
  float3 materialSpecularColor;
  float materialShininess;
};

struct Input {
  float4 color : TEXCOORD0;
  float2 uv : TEXCOORD1;
  float3 position: TEXCOORD2;
  float3 normal : TEXCOORD3;
};

Texture2D<float4> diffuseMap : register(t0, space2);
SamplerState smp : register(s0, space2);

float3 blinnPhongBRDF(float3 dirToLight, float3 dirToView, float3 surfaceNormal, float3 materialDiffussionReflection){

  // We calculate the vector that splits the angle between dtl and dtv in 2 equal angles.
  float3 halfWayDir = normalize(dirToLight + dirToView);
  
  // We get the cosine of the new vector over the surface normal, this is equal to a dot product.
  float specularDot = max(0, dot(halfWayDir, surfaceNormal));
  float specularFactor = pow(specularDot, materialShininess);

  float3 specularReflection = materialSpecularColor * specularFactor;
  return materialDiffussionReflection + specularReflection;
}

float4 main(Input input) : SV_Target0 {
  float3 vecToLight = lightPosition - input.position;
  float distToLight = length(vecToLight);
  float3 dirToLight = vecToLight / distToLight;

  float3 dirToView = normalize(viewPosition - input.position);

  float3 surfaceNormal = normalize(input.normal);
  float3 materialDiffussionReflection = diffuseMap.Sample(smp, input.uv).rgb;

  float3 ambientIrradiance = ambientLightColor;
  float3 reflectedRadiance =  ambientIrradiance * materialDiffussionReflection;

  float incidenceAngleFactor = dot(dirToLight, surfaceNormal);
  if (incidenceAngleFactor > 0){
    float attenuationFactor = 1/(distToLight * distToLight);
    float3 incomingRadiance = lightColor * lightIntensity;
    float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
    float3 brdf = blinnPhongBRDF(dirToLight, dirToView, surfaceNormal, materialDiffussionReflection);

    reflectedRadiance += irradiance * brdf;
  } 

  float3 emittedRadiance = {0,0,0};
  float3 outRadiance = emittedRadiance + reflectedRadiance;

  return float4(outRadiance, 1);
}
