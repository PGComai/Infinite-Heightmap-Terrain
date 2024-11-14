# Infinite-Heightmap-Terrain
 A terrain generator for Godot that loads in chunks like Minecraft

## How to use
Copy the addons folder into the res:// directory of your project, or install through the Godot Asset Library.

Add resources such as terrain_noise, terrain_color_steepness_curve, terrain_material, etc. Example resources are included in the "sample resources" folder.

For chunk loading to work properly, make sure to add a player node which will determine the position of chunks to be loaded, and use the get_terrain_height() function to spawn your player at the correct y value.
