# Textures

All from [Poly Haven](https://polyhaven.com/textures), CC0 (public domain): no credit
required, given anyway. The 1k JPG downloads, renamed `<id>_diff.jpg` (colour) and
`<id>_nor.jpg` (OpenGL normal map, imported at 512 px).

| file | Poly Haven id | covers | used for |
|---|---|---|---|
| `asphalt_02_*` | asphalt_02 | 3 m | road grit and fine cracks |
| `aerial_asphalt_01_diff` | aerial_asphalt_01 | 30 m | patches and tyre marks over it |
| `concrete_pavers_02_*` | concrete_pavers_02 | 2 m | Israeli pavements (pavers) |
| `concrete_pavement_*` | concrete_pavement | 1.8 m | Bedford's pavements (slabs, scaled up) |
| `leafy_grass_*` | leafy_grass | 2 m | grass, earth, the open ground |
| `painted_plaster_wall_*` | painted_plaster_wall | 2 m | building render |
| `bark_brown_02_*` | bark_brown_02 | 1 m | tree trunks and branches |
| `palm_tree_bark_*` | palm_tree_bark | 1.3 m | palm trunks (colour capped at 1024 px) |

`leaves_atlas.png` (2x2 cells: broad leaves, small narrow leaves, feathery fronds, needle
sprays) is made by `leaf_atlas.py` from two Poly Haven *model* textures, also CC0: the
leaves of [island_tree_01](https://polyhaven.com/a/island_tree_01) and of
[jacaranda_tree](https://polyhaven.com/a/jacaranda_tree), cut out of their black
backgrounds and scattered into clusters; the needle sprays are drawn by the script. To
remake it, download those two `*_leaves_diff_1k.jpg` files from Poly Haven and run
`python3 leaf_atlas.py <island leaves> <jacaranda leaves> leaves_atlas.png`; it prints each
cell's average colour for `LEAF_MEAN` in `streets.gd`.

To swap one: download the same id's `diff_1k.jpg` and `nor_gl_1k.jpg`, keep the import
settings (VRAM compressed, mipmaps on, normal maps flagged and capped at 512), and put its
average colour in `TEX_MEAN` in `streets.gd`: the mean of the file's stored (sRGB) values,
0-1 per channel. The shaders divide by it, so a wrong average tints the whole surface.

`sky_day.jpg` is the sky half of Poly Haven's CC0 HDRI
[kloofendal_48d_partly_cloudy_puresky](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky)
(the 4k .hdr), tonemapped (ACES) and cut to 4096x1024 by `hdr_sky.py`:
`python3 hdr_sky.py <the .hdr> sky_day.jpg 4096`. It prints where the sun is across the
photo (`SKY_SUN_U`) and its average and horizon colours (`SKY_MEAN`, `SKY_HORIZON`) for
`streets.gd`. Imported lossy (WebP), no mipmaps: it is only ever the background.
