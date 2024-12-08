#[raygen]

#version 460

//#VERSION_DEFINES

#define MAX_VIEWS 2

#include "../scene_data_inc.glsl"
#include "payload.glsl"

#pragma shader_stage(raygen)
#extension GL_EXT_ray_tracing : enable

layout(location = 0) rayPayloadEXT RayPayload payload;

// Render target in raytracing is a storage image with general layout.
layout(set = 0, binding = 0, rgba32f) uniform image2D image;

// Bounding Volume Hierarchy: top-level acceleration structure.
layout(set = 0, binding = 1) uniform accelerationStructureEXT tlas;

layout(set = 0, binding = 2, std140) uniform SceneDataBlock {
	SceneData data;
} scene_data_block;


void main() {
	const vec2 pixel_center = vec2(gl_LaunchIDEXT.xy) + vec2(0.5);
	const vec2 in_uv = pixel_center / vec2(gl_LaunchSizeEXT.xy);
	vec2 d = in_uv * 2.0 - 1.0;

	float size_y = gl_LaunchSizeEXT.y;
	float aspect_ratio = gl_LaunchSizeEXT.x / size_y;

	vec4 target = scene_data_block.data.inv_projection_matrix * vec4(d.x /* aspect_ratio */, d.y, 1.0, 1.0);
	vec4 origin = scene_data_block.data.inv_view_matrix * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 direction = scene_data_block.data.inv_view_matrix * vec4(normalize(target.xyz), 0);

	float t_min = 0.001;
	float t_max = 10000.0;

	payload.color = vec3(0.0, 0.0, 0.0);
	payload.miss = true;
	payload.depth = 0;

	traceRayEXT(tlas, gl_RayFlagsOpaqueEXT, 0xFF, 0, 0, 0, origin.xyz, t_min, direction.xyz, t_max, 0);

	imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(payload.color, 1.0));
}

#[miss]

#version 460

#pragma shader_stage(miss)
#extension GL_EXT_ray_tracing : enable

#include "payload.glsl"

layout(location = 0) rayPayloadInEXT RayPayload payload;

void main() {
	payload.miss = true;
}

#[closest_hit]

#version 460

#pragma shader_stage(closest_hit)
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_tracing_position_fetch : require

#include "payload.glsl"
#include "../light_data_inc.glsl"

layout(location = 0) rayPayloadInEXT RayPayload payload;
layout(location = 1) rayPayloadEXT RayPayload shadow_payload;

// Bounding Volume Hierarchy: top-level acceleration structure.
layout(set = 0, binding = 1) uniform accelerationStructureEXT tlas;

layout(set = 0, binding = 3, std140) restrict readonly buffer OmniLights {
	LightData data[];
}
omni_lights;

hitAttributeEXT vec3 attribs;

void main() {
	payload.miss = false;

	payload.depth += 1;
	payload.color = vec3(1.0, 1.0, 1.0);
	vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);

	vec3 pos0 = gl_HitTriangleVertexPositionsEXT[0];
	vec3 pos1 = gl_HitTriangleVertexPositionsEXT[1];
	vec3 pos2 = gl_HitTriangleVertexPositionsEXT[2];

	payload.pos = pos0 * barycentrics.x + pos1 * barycentrics.y + pos2 * barycentrics.z;

	if (payload.depth == 2) {
		return;
	}

	vec3 normal = normalize(cross(pos1 - pos0, pos2 - pos0));
	vec3 origin = payload.pos - normal * 0.01;

	normal = normalize(vec3(normal * gl_WorldToObjectEXT));
	payload.color = (normal + 1.0) / 2.0;

	float t_min = 0.001;
	float t_max = 10000.0;

	for (uint i = 0; i < omni_lights.data.length(); i++) {
		vec3 light_pos =  omni_lights.data[i].position;
		vec3 light_vec = light_pos - origin;
		vec3 direction = normalize(light_vec);

		traceRayEXT(tlas, gl_RayFlagsOpaqueEXT, 0xFF, 0, 0, 0, origin.xyz, t_min, direction.xyz, t_max, 0);

		if (payload.miss == false) {
			float light_distance = length(light_vec);
			float hit_distance = length(payload.pos - origin);
			if (hit_distance < light_distance) {
				// then there's an occlusion
				payload.color = vec3(0.0, 0.0, 0.0);
			}
			break;
		}
	}
}
