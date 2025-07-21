#include "common.hlsl"

struct Input {
  uint vertexID : SV_VertexID;
};

struct Output{
  float4 clipPosition : SV_Position;
  float3 texCoords : TEXCOORD0;
};

Output main(Input input){
  float2 vertices[]= { // Los vertices estan en NDC
    float2(-1,-1),
    float2(3, -1),
    float2(-1, 3),
  };

  float4 clipSpacePosition = float4(vertices[input.vertexID], 1, 1); // Estos dos unos son Z para pushear al final y w para nada.

  float4 viewSpacePosition = mul(invProjectionMat, clipSpacePosition);
  
  float4 viewDir = mul(invViewMat, float4(viewSpacePosition.xyz, 0));


  Output output;
  output.clipPosition = clipSpacePosition;
  output.texCoords = viewDir.xyz;
  return output;
}
