//
//  Shaders.metal
//  Persyk
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



vertex VertexOut vertex_main(const VertexIn vertex_in [[stage_in]],
                             constant float2 &offset [[buffer(1)]]) {
    VertexOut out;
    
    out.position = float4(vertex_in.position.x + offset.x,
                          vertex_in.position.y + offset.y,
                          vertex_in.position.z,
                          vertex_in.position.w);
    
    out.texCoord = vertex_in.texCoord;
    
    return out;
}


fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> texture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    return texture.sample(textureSampler, in.texCoord);
}
