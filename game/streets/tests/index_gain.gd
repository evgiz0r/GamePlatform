extends SceneTree
## Would indexing the merged meshes pay? They are triangle soups (every triangle its own three
## vertices). For each merged mesh (the one tone material) this indexes a copy with
## SurfaceTool.index() -- vertices with the same position, normal and colour shared -- and
## adds up: vertices before and after, the index buffer it would need (16-bit while a mesh has
## under 65,536 vertices, else 32-bit), the bytes before and after (a vertex here is about 20
## bytes: position 12, normal 4, colour 4), and how long indexing took (the load would pay
## that, more in a browser). CHUNK=n indexes each mesh in pieces of at most n vertices (the
## build has no threads in a browser: a piece must fit in a frame) and adds the slowest
## piece and how many pieces (each a draw call) the meshes became.
##   tests/run.sh index_gain 7
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:   # (the rest of the city built in the background, merged at the end)
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	const VB := 20
	var meshes := 0
	var before := 0
	var after := 0
	var idx_bytes := 0
	var wide := 0
	var us := 0
	var biggest := 0
	var chunk := int(OS.get_environment("CHUNK")) / 3 * 3 if OS.get_environment("CHUNK") != "" else 0
	var pieces := 0
	var slowest := 0
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.mesh is ArrayMesh or mi.mesh.get_surface_count() == 0:
			continue
		var am := mi.mesh as ArrayMesh
		if am.surface_get_material(0) != g._tone_material or am.surface_get_array_index_len(0) > 0:
			continue
		var arr := am.surface_get_arrays(0)
		var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var step := chunk if chunk > 0 else n
		for from in range(0, n, step):
			var part := arr
			if step < n:
				part = []
				part.resize(Mesh.ARRAY_MAX)
				for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
					if arr[a] != null:
						part[a] = arr[a].slice(from, mini(from + step, n))
			var pn := mini(step, n - from)
			var t0 := Time.get_ticks_usec()
			var st := SurfaceTool.new()
			st.create_from_arrays(part)
			st.index()
			var out := st.commit_to_arrays()
			var took := Time.get_ticks_usec() - t0
			us += took
			slowest = maxi(slowest, took)
			pieces += 1
			var u := (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			after += u
			var ib := 2 if u < 65536 else 4
			if ib == 4:
				wide += 1
			idx_bytes += pn * ib
		meshes += 1
		before += n
		biggest = maxi(biggest, n)
	print("merged meshes %d (biggest %d vertices): %.2f M vertices -> %.2f M (%.0f%%) + %.2f M indices (%d pieces need 32-bit)" % [meshes, biggest,
		before / 1.0e6, after / 1.0e6, 100.0 * after / maxf(before, 1.0), before / 1.0e6, wide])
	print("in %d pieces (CHUNK %d), the slowest %.1f ms" % [pieces, chunk, slowest / 1000.0])
	print("bytes: %.0f MB -> %.0f MB (%.0f MB vertices + %.0f MB indices); indexing took %.1f s here" % [before * VB / 1048576.0,
		(after * VB + idx_bytes) / 1048576.0, after * VB / 1048576.0, idx_bytes / 1048576.0, us / 1.0e6])
	quit(0)
