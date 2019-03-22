# Map generator

Script for generating binary map for offline smartphone apps like [Locus](https://www.locusmap.eu/) or [c:geo](https://www.cgeo.org/).

As input it uses `.pbf` OpenStreetMap files. These files can be downloaded from <http://download.geofabrik.de>.

By default, the script will add contour into map. Height data are downloaded by `phyghtmap` program and should be NASA SRTM data. Contour adding can be skipped by passing `-S` parameter.

You can clip a subregion from downloaded map by passing in a `.poly` file (`-p <file>` parameter) with subregion coordinations. This file can be generated and downloaded from <https://wambachers-osm.website/boundaries/>.
This will speed up whole process of final map generating.
When no subregion file is passed, it will automaticly download `.poly` file for whole downloaded map.

## Dependencies on other programs

These dependecies are written down for Linux distribution Manjaro. On your distributions can differ in name and other dependencies, but they should be similar and recognizable.

When program name will differ, minor tweaks in main shell script will be needed.

This shell script was never ment to run under Windows or MacOS, but maybe it can.

### Phyghtmap

Generate OSM contour lines from NASA SRTM data.

In Manjaro it can be found in AUR.

More info can be found on [OpenStreetMap wiki page](https://wiki.openstreetmap.org/wiki/Phyghtmap).

### Osmconvert

OpenStreetMap file format converter (.osm, .o5m, and .pbf)

In Manjaro it can be found in AUR.

More info can be found on [OpenStreetMap wiki page](https://wiki.openstreetmap.org/wiki/Osmconvert).

### Osmosis

Command line Java application for processing OSM data.

In Manjaro it can be found in AUR.

More info can be found on [OpenStreetMap wiki page](https://wiki.openstreetmap.org/wiki/Osmosis).

### Mapwriter plugin for Osmosis

Tool to convert OSM data files into maps that can be displayed with mapsforge.

More info on [Mapsforge GitHub](https://github.com/mapsforge/mapsforge/blob/master/docs/Getting-Started-Map-Writer.md).

### JAVA

For `Osmosis` it is required to have installed `java-runtime`, which ideally are `jre8-openjdk` and `jre8-openjdk-headless` packages.

## System tweaks

For processing bigger regions, it is recommended to tweak system for larger memory usage. Regions such as Czech Republic or Netherlands are big enough to cause these problems.

### JAVA heap size

Automaticaly it is set to 8G by shell script. This can be skipped by passing `-J` parameter.

If you want to set it manually, you can by following command:

```bash
export JAVACMD_OPTIONS=-Xmx8G
```

### Size of /tmp mountpoint

Basic `/tmp` directory has size limit to stored files. You can reach this limit simply by processing region such as Czech Republic and then whole script exits with memory error.

```bash
mount -o remount,size=16G,noatime /tmp
```

After reboot this will be set back to default value in your system.

Someimes it is recmmended the `/tmp` directory clean by yourself. Sometimes there are abandoned temporary files from subprograms and they are relatively big.

```bash
cd /tmp
rm *.tmp
```

## Tag mapping file

Tag mapping file is stored under `./conf` folder. This complex XML file is definition what will be displayed in final map.

Inside included `tag-mapping.xml` file are many commented hints and links to tweak this file even further.

## Parameters

### -m <url> ; --map <url>

Set a source URL for map to download. Map have to be OpenStreetMap `.pbf` format. Urls can be found on <http://download.geofabrik.de>.

### -p <file> ; --polygon <file>

Manually set polygon borders for final map. This is usefull when you need map of one city and not whole country.

Polygon file have to be in `poly` format and can be generated and downloaded from <https://wambachers-osm.website/boundaries/>.

When this parameter is ommitted, default polygon file will be downloaded for whole source map.

### -m <name> ; --name <name>

Set output map name.

When this parameter is ommitted, default name will be same as map name form URL.

### -t <file> ; --tag-conf-file <file>

Manually set tags definition which should be displayed in final map.

When this parameter is ommitted, default file `./conf/tag-mapping.xml` will be used.

### -S ; --skip-contour-lines

Passing this parameter you will skip controu lines process. No data will be downloaded, computed and merged to final map. After that, whole process should be faster.

### -J ; --skip-java-heap

Passing this parameter you will skip setting JAVA heap size. You don't need to set JAVA heap when you are processing small country or region. No speed burst will be added.

### -f <format> ; --height-format <format>

This will set downloaded height format from `phyghtmap` program. Possible values are 'srtm1', 'srtm3', 'view1' and 'view3'. Preffered format is 'view3', others were tested very long time ago, so they can be buggy.

When this parameter is ommitted, default 'view3' will be used.

### -w <number> ; --workers <number>

This will set number of dedicated threads for computing. Less should be slower, more should be faster. It depends how many threads your system has.

When this parameter is ommitted, default 2 will be used.

### -h ; --help

This will display command line help.

## Example command

Download latest map for Czech Republic; clip from it only Prague region; don't add contour lines; skip setting JAVA heap size; set 4 threads for computing.

```bash
./map-generator.sh -m http://download.geofabrik.de/europe/czech-republic-latest.osm.pbf -p "conf/CZ-Prague.poly" -S -J -w 4
```

## Directories description

### ./conf

Configuration folder for `tag-mapping.xml` file.

### ./maps

Output folder with generated maps and logs.

### ./tmp

Folder with temporary data.

Here are all downloaded stuff, which can be deleted after map is generated. Also here are downloaded height data in subfolder `hgt`.

## Known problems

Right at this moment I have problem with running this script, which seems to never end after map is finalized. I suppose that there is bug in `Osmosis` which generates final output correctly, but the program itself hangs and never exits.

One day this should be able to save tourist routes in map.

To avoid problems with dependecies, it is planned to try out Docker. I'm little bit afraid of really big memory consumption during map generation. We will see sometimes.

## Other sources

*   [Map server](http://download.geofabrik.de)
*   [Polygon server](https://wambachers-osm.website/boundaries/)
*   [Phyghtmap](https://wiki.openstreetmap.org/wiki/Phyghtmap)
*   [Osmconvert](https://wiki.openstreetmap.org/wiki/Osmconvert)
*   [Osmosis](https://wiki.openstreetmap.org/wiki/Osmosis)
*   [Mapwriter plugin](https://github.com/mapsforge/mapsforge/blob/master/docs/Getting-Started-Map-Writer.md)
