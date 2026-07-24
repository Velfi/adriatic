// Vulkan wireframe ribbon pass. Each logical edge is expanded into two
// triangles so line width and interpolation are portable across Vulkan drivers.
struct Push {
    float4x4 view_projection;
    float2 viewport;
    float line_width_pixels;
    float _padding;
};
[[vk::push_constant]] ConstantBuffer<Push> push;

struct VertexInput {
    // x: endpoint selector (0/1); y: ribbon side (-1/+1).
    float2 parameter : POSITION;
    float3 start_position : TEXCOORD0;
    float3 end_position : TEXCOORD1;
    float4 start_color : COLOR0;
    float4 end_color : COLOR1;
};

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
};

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    float4 start_clip = mul(push.view_projection, float4(input.start_position, 1));
    float4 end_clip = mul(push.view_projection, float4(input.end_position, 1));
    float t = input.parameter.x;
    output.position = lerp(start_clip, end_clip, t);
    float2 start_ndc = start_clip.xy / max(start_clip.w, .0001);
    float2 end_ndc = end_clip.xy / max(end_clip.w, .0001);
    float2 direction_pixels = (end_ndc - start_ndc) * push.viewport;
    float direction_length = max(length(direction_pixels), .0001);
    float2 perpendicular = float2(-direction_pixels.y, direction_pixels.x) / direction_length;
    float2 offset_ndc = perpendicular * input.parameter.y * push.line_width_pixels * 2.0 / max(push.viewport, 1.0);
    output.position.xy += offset_ndc * output.position.w;
    output.color = lerp(input.start_color, input.end_color, t);
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    return input.color;
}
