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

To swap one: download the same id's `diff_1k.jpg` and `nor_gl_1k.jpg`, keep the import
settings (VRAM compressed, mipmaps on, normal maps flagged and capped at 512), and put its
average colour in `TEX_MEAN` in `streets.gd`: the mean of the file's stored (sRGB) values,
0-1 per channel. The shaders divide by it, so a wrong average tints the whole surface.
