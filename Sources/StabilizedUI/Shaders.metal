//
//  Shaders.metal
//  StabilizedUI
//
//  Created by Діана Цісарук on 15.12.2025.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(const VertexIn in [[stage_in]],
                             constant float4 &params [[buffer(1)]])
{
    VertexOut out;
    float2 offset = params.xy;
    float2 scale  = params.zw;

    out.position = float4(
        in.position.x * scale.x + offset.x,
        in.position.y * scale.y + offset.y,
        in.position.z,
        in.position.w
    );
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]])
{
    constexpr sampler s(mag_filter::linear,
                        min_filter::linear,
                        mip_filter::none,
                        address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}

