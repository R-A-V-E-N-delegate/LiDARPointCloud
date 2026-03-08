#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float pointSize;
    float3 padding;
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
    float pointSize [[point_size]];
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant float3* positions [[buffer(0)]],
                              constant float3* colors [[buffer(1)]],
                              constant Uniforms& uniforms [[buffer(2)]]) {
    VertexOut out;

    float4 worldPosition = float4(positions[vertexID], 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;

    out.color = colors[vertexID];

    // Scale point size based on distance for better visualization
    float distance = length(viewPosition.xyz);
    out.pointSize = uniforms.pointSize * (1.0 / max(distance, 0.5));

    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               float2 pointCoord [[point_coord]]) {
    // Create circular points with soft edges
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) {
        discard_fragment();
    }

    // Soft edge
    float alpha = 1.0 - smoothstep(0.3, 0.5, dist);

    return float4(in.color, alpha);
}
