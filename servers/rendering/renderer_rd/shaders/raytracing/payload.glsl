struct RayPayload {
	highp vec3 color;
	bool miss;
	/// Hit position
	highp vec3 pos;
	uint depth;
};
