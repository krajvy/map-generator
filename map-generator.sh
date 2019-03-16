#!/bin/bash
#
# Script for downloading and converting Open Street Maps pbf map
# to format for programs like Locus or c:geo in mobile phones
#
# @author Jan 'krajvy' Krivohlavek <krajvy@gmail.com>
#
# @require
# * phyghtmap
# * osmosis with mapwriter plugin
# * osmconvert
#
# For really big maps it is recommended:
#
# 1) Enlarge /tmp mountpoint
# mount -o remount,size=8G,noatime /tmp
#
# 2) Set JAVA heap size
# export JAVACMD_OPTIONS=-Xmx8G
#

# Exit when anything goes wrong
set -e

# Basic configuration variables
DIR_TMP='tmp'
DIR_OUT='maps'
TAG_CONF_FILE='conf/tag-mapping.xml'
HEIGHT_FORMAT='view3'
MAP_PREFIX=''
WORKERS=2

# For logging and debugging
TIME_START=$(date +%s.%N)

# Change directory to scripts default
cd "`dirname "$(readlink -f $0)"`"

# Check for parameters or print help
while [[ $# -gt 0 ]]; do
	case $1 in
		-m|--map)
			MAP_URL=${2}
			shift # past argument
			;;
		-p|--polygon)
			POLY_FILE=${2}
			shift # past argument
			;;
		-t|--tag-conf-file)
			TAG_CONF_FILE=${2}
			shift # past argument
			;;
		-f|--height-format)
			HEIGHT_FORMAT=${2}
			shift # past argument
			;;
		-w|--workers)
			WORKERS=${2}
			shift # past argument
			;;
		-x|--prefix)
			MAP_PREFIX=${2}
			shift # past argument
			;;
		-h|--help|*)
			echo "=================================================="
			echo "Help for open street maps downloader and compiler:"
			echo "=================================================="
			echo ""
			echo -e "\e[1m-m <url>\e[0m"
			echo -e "\e[1m--map <url>\e[0m"
			echo "     URL with map data."
			echo "     example: 'http://download.geofabrik.de/europe/czech-republic-latest.osm.pbf'"
			echo ""
			echo -e "\e[1m-p <file>\e[0m"
			echo -e "\e[1m--polygon <file>\e[0m"
			echo "     Polygon file which will extract submap from downloaded map data. This file can be downloaded from https://wambachers-osm.website/boundaries/"
			echo "     example: 'conf/Prague.poly'"
			echo ""
			echo -e "\e[1m-t <file>\e[0m"
			echo -e "\e[1m--tag-conf-file <file>\e[0m"
			echo "     XML file with definition what will be displayed in final map."
			echo "     default: 'conf/tag-mapping.xml'"
			echo ""
			echo -e "\e[1m-f <format>\e[0m"
			echo -e "\e[1m--height-format <format>\e[0m"
			echo "     Height format that is passed to phyghtmap and merged to map."
			echo "     default: 'view3'"
			echo "     available: 'srtm1', 'srtm3', 'view1' and 'view3'"
			echo ""
			echo -e "\e[1m-w <number>\e[0m"
			echo -e "\e[1m--workers <number>\e[0m"
			echo "     How many workers (cores) do we want to work"
			echo "     default: 2"
			echo ""
			echo -e "\e[1m-x <prefix>\e[0m"
			echo -e "\e[1m--prefix <prefix>\e[0m"
			echo "     Prefix of generated files for better orientation in folders."
			echo "     example: 'cz-'"
			exit 0
			;;
	esac
	shift # past argument or value
done

# poly url should be generated from map url (without -latest.osm.pbf)

# Set other needed variables
MAP_NAME="${MAP_PREFIX}"$(basename ${MAP_URL} .osm.pbf)
# Map name can now end with -latest - strip it out
MAP_NAME="${MAP_NAME%-latest}"
MAP_NAME_TMP="${DIR_TMP}/${MAP_NAME}.osm.pbf"
MAP_NAME_COMPLETE="${DIR_TMP}/${MAP_NAME}.complete.pbf"
MAP_NAME_MERGE="${DIR_TMP}/${MAP_NAME}.merge.pbf"
MAP_NAME_FINAL="${DIR_OUT}/${MAP_NAME}.map"

# If polygon file hasn't been attached by parameter
if [ ! -f $POLY_FILE ] || [ "x${POLY_FILE}" = "x" ]; then
	# I need to download my own polygon file
	POLY_URL="${MAP_URL%.osm.pbf}"
	# Poly URL can now end with -latest
	POLY_URL="${POLY_URL%-latest}.poly"
	POLY_FILE="${DIR_TMP}/${MAP_PREFIX}"$(basename "${POLY_URL}")
fi

HEIGHT_FILE=""

LOG_FILE="${DIR_OUT}/${MAP_NAME}.log"

# Output formating functions
function linf {
	echo -e "\e[1m\e[94m[i]\e[0m ${1}"
}
function lerr {
	echo -e "\e[1m\e[31m[!]\e[0m ${1}"
}

# Log functions
function logPrint {
	echo "$(date +%s.%N)"" > ${1}" >> $LOG_FILE
}
function logClear {
	echo '' > $LOG_FILE
}

# Download function
function download {
	if [ "x$1" = "x" ] || [ "x$2" = "x" ]; then
		lerr 'Not enough parameters for downloading! Nothing to do...'
		exit 1
	fi

	local cmd="wget -c ${1} -O ${2}"

	linf "Downloading ${1} to ${2}"
	logPrint "Downloading: ${cmd}"

	eval $cmd
}

# Process functions

# Download main map data from OSM
function downloadMap {
	linf "Download map data..."

	if [ -z $MAP_URL ]; then
		lerr "Map URL not set! Nothing to do..."
		exit 1
	fi

	# Download desired file in the first way
	download "${MAP_URL}" "${MAP_NAME_TMP}"

	if [ ! -e $MAP_NAME_TMP ]; then
		lerr "Can't download map data!"
		exit 1
	fi

	logPrint "Download of map data complete"
}
# Download height data for given polygon of map
function downloadHeightData {
	linf "Download height data..."

	# If polygon URL is set
	if [ "x${POLY_URL}" != "x" ]; then
		# Download desired file if is set URL
		download "${POLY_URL}" "${POLY_FILE}"
	fi

	if [ ! -f $POLY_FILE ]; then
		lerr "Can't get height data - missing POLY_FILE!"
		exit 1
	fi

	local cmd="phyghtmap --polygon=${POLY_FILE} --output-prefix=${DIR_TMP}/${MAP_NAME} --source=${HEIGHT_FORMAT} --pbf --jobs=2 --step=10 --line-cat=100,50 --start-node-id=20000000000 --start-way-id=10000000000 --write-timestamp --max-nodes-per-tile=0 --hgtdir=${DIR_TMP}/hgt"

	logPrint "Downloading height data: ${cmd}"

	eval $cmd

	HEIGHT_FILE=$(find $DIR_TMP -type f -name ${MAP_NAME}"_*.osm.pbf" -print)

	logPrint "Download of height data complete"
	logPrint "Height file name: ${HEIGHT_FILE}"
}
# Complete map by given polygon - especially complete cross-border ways or clip submap
function completeMapByPolygon {
	linf "Complete map by given polygon..."

	if [ ! -f $POLY_FILE ]; then
		lerr "Can't complete map - missing POLY_FILE"
		exit 1
	fi

	local cmd="osmconvert ${MAP_NAME_TMP} -B=${POLY_FILE} --verbose --complete-ways --complex-ways -o=${MAP_NAME_COMPLETE}"

	logPrint "Completing map by polygon: ${cmd}"

	eval $cmd

	logPrint "Completing map by polygon complete"
}
# Merge map with its height data
function mergeMapAndHeight {
	linf "Merge height data with actual map..."

	if [ ! -e $HEIGHT_FILE ]; then
		lerr "Can't merge height file with map - missing HEIGHT_FILE!"
		exit 1
	fi

	local cmd="osmosis --read-pbf-fast file=${MAP_NAME_COMPLETE} workers=${WORKERS} --sort-0.6 --read-pbf-fast ${HEIGHT_FILE} workers=${WORKERS} --sort-0.6 --merge --write-pbf ${MAP_NAME_MERGE}"

	logPrint "Merging height data with map: ${cmd}"

	eval $cmd

	logPrint "Merge height data complete"
}
# Generate output map and display what is defined in TAG_CONF_FILE
function generateFinalMap {
	linf "Generating final map..."

	if [ ! -e $MAP_NAME_MERGE ]; then
		lerr "Can't generate final map!"
		exit 1
	fi

	local cmd="osmosis --read-pbf file=${MAP_NAME_MERGE} --buffer --mapfile-writer file=${MAP_NAME_FINAL} type=hd  tag-conf-file=${TAG_CONF_FILE}"

	logPrint "Generating final map: ${cmd}"

	eval $cmd

	logPrint "Generating final map complete"
}

# Clear logfile
logClear
# Log print
logPrint "Start time: ${TIME_START}"
logPrint "Map URL: ${MAP_URL}"
logPrint "Map download to file: ${MAP_NAME_TMP}"

# If polygon URL is set
if [ "x${POLY_URL}" != "x" ]; then
	logPrint "Polygon URL: ${POLY_URL}"
	logPrint "Polygon download to file: ${POLY_FILE}"
else
	logPrint "Polygon given file: ${POLY_FILE}"
fi

logPrint "Tag configuration file: ${TAG_CONF_FILE}"
logPrint "Map name: ${MAP_NAME}"
logPrint "Map merge file name: ${MAP_NAME_MERGE}"
logPrint "Map complete file name: ${MAP_NAME_COMPLETE}"
logPrint "Map output name: ${MAP_NAME_FINAL}"

# Download map data
downloadMap
# Download height data for map
downloadHeightData
# Complete cross-border ways or clip submap from map
completeMapByPolygon
# Merge downloaded map and computed height data
mergeMapAndHeight
# Generate output map with all data
generateFinalMap
# Clean generated stuff from HD
#cleanAfter

linf "Everything seems to be OK"

# And final logs and exit
TIME_END=$(date +%s.%N)
TIME_DIFF=$(echo "${TIME_END} - ${TIME_START}" | bc)

linf "Generating ${MAP_NAME_FINAL} took ${TIME_DIFF} sec."
logPrint "Generating ${MAP_NAME_FINAL} took ${TIME_DIFF} sec."
