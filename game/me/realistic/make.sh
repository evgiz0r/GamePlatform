#!/usr/bin/env bash
# The realistic avatar: a MakeHuman body (CC0) shaped and dressed like him, rigged with the
# CMU-named skeleton (MPFB's CC0 rig + weights), driven by CMU motion capture, rendered by
# Blender's EEVEE. Everything is fetched here; nothing big is committed. See ../DEV.md.
#
#   game/me/realistic/make.sh            fetch, build, bake, render all four, encode
#   SCENES="wave" game/me/realistic/make.sh
# Env: RES (854x480), SAMPLES (8). Outputs land in game/me/realistic/work/ (gitignored by
# the work/.gitignore this writes).
set -eu
cd "$(dirname "$0")"
mkdir -p work && echo "*" > work/.gitignore
W=work
# Blender as a Python module (no Blender install needed) -- the cloud sessions have no Blender
[ -x $W/py/bin/python ] || { python3 -m venv $W/py && $W/py/bin/pip install -q bpy; }
B=$W/py/bin/python
# EEVEE needs EGL even headless (a bare container lacks it: apt-get install libegl1 libegl-mesa0)
fetch() {  # repo dir paths...: a sparse, blob-less checkout of just those paths
  local repo=$1 dir=$2; shift 2
  [ -d $W/$dir ] || git clone -q --depth 1 --filter=blob:none --no-checkout https://github.com/$repo $W/$dir
  (cd $W/$dir && git checkout HEAD -- "$@")
}
fetch makehumancommunity/makehuman mh makehuman/data/3dobjs makehuman/data/targets/macrodetails \
  makehuman/data/targets/head makehuman/data/targets/nose makehuman/data/targets/chin \
  makehuman/data/targets/forehead makehuman/data/targets/cheek makehuman/data/targets/neck \
  makehuman/data/targets/stomach
fetch makehumancommunity/mpfb2 mpfb2 src/mpfb/data/rigs/standard src/mpfb/data/mesh_metadata
fetch meshula/cmu-mocap cmu data/016/16_15.bvh data/141/141_16.bvh data/113/113_04.bvh data/018/18_08.bvh
export MH_DATA=$W/mh/makehuman/data MPFB_DATA=$W/mpfb2/src/mpfb/data
$B build_me.py -- $W/me.blend
$B look.py -- $W/me.blend $W/me_look.blend
D=$W/cmu/data
$B mocap.py -- $W/me_look.blend $W/c_walk.blend $D/016/16_15.bvh 1 472 --name walk
$B mocap.py -- $W/me_look.blend $W/c_wave.blend $D/141/141_16.bvh 1 300 --name wave --inplace
$B mocap.py -- $W/me_look.blend $W/c_dance.blend $D/113/113_04.bvh 1 971 --name dance --inplace
$B mocap.py -- $W/me_look.blend $W/c_teach.blend $D/018/18_08.bvh 1 2087 --name explain
# scene: clip, first frame, last frame (30 fps after baking)
declare -A RANGE=([walk]="5 118" [wave]="1 75" [dance]="20 243" [teach]="30 330")
for s in ${SCENES:-walk wave dance teach}; do
  set -- ${RANGE[$s]}
  $B scene.py -- $W/c_$s.blend $W/r_$s --scene $s --from $1 --to $2 --res ${RES:-854x480} --samples ${SAMPLES:-8}
  ffmpeg -loglevel error -y -framerate 30 -i $W/r_$s/f%04d.png -c:v libx264 -crf 20 -pix_fmt yuv420p \
    -movflags +faststart $W/real_$s.mp4
  echo "made $W/real_$s.mp4"
done
