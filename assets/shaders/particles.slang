struct Push {
    float4 camera_position;
    float4 camera_right;
    float4 camera_up;
    float4 camera_forward;
    float4 projection;
    float4 fog_color;
    float4 water; // time, weather, wind x, wind z
    float4 sun;
};
[[vk::push_constant]] ConstantBuffer<Push> push;

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
};

float hash(uint n) {
    n ^= n * 61u;
    n ^= n >> 16;
    n *= 9u;
    n ^= n >> 4;
    return float(n & 0x00ffffffu) / 16777216.0;
}

float3 particle_position(uint id, float time) {
    float seed = hash(id * 747796405u + 2891336453u);
    float angle = hash(id * 277803737u + 1013904223u) * 6.2831853;
    float radius = .6 + hash(id * 1597334677u + 17u) * 2.4;
    float cycle = frac(time * (.18 + seed * .22) + hash(id + 31u));
    float3 p = float3(cos(angle) * radius, cycle * 2.4, sin(angle) * radius);
    p.x += sin(time * .7 + seed * 9.0) * .35;
    p.z += cos(time * .6 + seed * 7.0) * .35;
    return p + float3(1300.0, 6.0, 1300.0);
}

VertexOutput vertex_main(uint vertex_id : SV_VertexID) {
    uint particle_id = vertex_id / 6u;
    uint corner = vertex_id % 6u;
    float3 corners[6] = {
        float3(-1, -1, 0), float3(1, -1, 0), float3(1, 1, 0),
        float3(-1, -1, 0), float3(1, 1, 0), float3(-1, 1, 0)
    };
    float seed = hash(particle_id * 747796405u + 2891336453u);
    float cycle = frac(push.water.x * (.18 + seed * .22) + hash(particle_id + 31u));
    float size = (.055 + hash(particle_id * 1597334677u + 17u) * .12) * (1.0 - cycle * .25);
    float3 world = particle_position(particle_id, push.water.x);
    world += (push.camera_right.xyz * corners[corner].x + push.camera_up.xyz * corners[corner].y) * size;
    float3 view = world - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth - far_plane * near_plane / (far_plane - near_plane);
    VertexOutput output;
    output.position = float4(x, -y, clip_z, depth);
    output.color = float4(lerp(float3(.95, .65, .22), float3(1.0, .92, .55), seed), 1.0 - cycle);
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    return input.color;
}
