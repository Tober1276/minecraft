# CurseForge Generic

## This is a generic egg for CurseForge modpacks

You will need to provide a modpack Project ID. For example, the Project ID for [All the Mods 8 - ATM8](https://www.curseforge.com/minecraft/modpacks/all-the-mods-8) is `520914`.
This can be found on the modpack page in the `About Project` section in the right sidebar.

You can also optionally specify a File ID. If you do not specify a File ID, the latest version will be used.
For example, the File ID for the server pack of [All the Mods 8 - ATM8](https://www.curseforge.com/minecraft/modpacks/all-the-mods-8) version `1.0.17` is `4504876`.
This can be found on the modpack page by clicking the desired file and copying the ID at the end of the URL (the number after `/files/`).

The script will automatically setup Forge, Fabric, Quilt, or NeoForge depending on the modpack.

You *must* specify a CurseForge API key.
You can find out how to get an API key [here](https://support.curseforge.com/en/support/solutions/articles/9000208346-about-the-curseforge-api-and-how-to-apply-for-a-key).

## Server Ports

The Minecraft server requires a single port for access (default 25565), but plugins and mods may require extra ports to be enabled for the server.

| Port  | Default |
|-------|---------|
| Game  | 25565   |