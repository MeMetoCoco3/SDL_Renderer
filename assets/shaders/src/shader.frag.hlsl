struct Input {
  float4 color : TEXCOORD0;
  float2 uv : TEXCOORD1;
};

Texture2D<float4> tex : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
  float4 color = tex.Sample(smp, input.uv);
  // color.rgb = pow(color.rgb, 2.2);

  // Now colors are linear, gama correction defeated.

  float4 finalColor =  color * input.color;
  // finalColor.rgb = pow(color.rgb, 1/2.2);
  return finalColor;
}
