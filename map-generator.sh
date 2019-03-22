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
MAP_NAME_OUT=''
WORKERS=2
CONTOUR=1
SET_JAVA_HEAP=8

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
		-S|--skip-contour-lines)
			CONTOUR=0
			;;
		-f|--height-format)
			HEIGHT_FORMAT=${2}
			shift # past argument
			;;
		-w|--workers)
			WORKERS=${2}
			shift # past argument
			;;
		-J|--skip-java-heap)
			SET_JAVA_HEAP=0
			;;
		-n|--name)
			MAP_NAME_OUT=${2}
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
			echo "     default: '${TAG_CONF_FILE}'"
			echo ""
			echo -e "\e[1m-S <file>\e[0m"
			echo -e "\e[1m--skip-contour-lines\e[0m"
			echo "     Skip processing contour lines into map. Generating should be faster"
			echo ""
			echo -e "\e[1m-J <file>\e[0m"
			echo -e "\e[1m--skip-java-heap\e[0m"
			echo "     Skip setting JAVA heap size for bigger maps"
			echo ""
			echo -e "\e[1m-f <format>\e[0m"
			echo -e "\e[1m--height-format <format>\e[0m"
			echo "     Height format that is passed to phyghtmap and merged to map."
			echo "     default: '${HEIGHT_FORMAT}'"
			echo "     available: 'srtm1', 'srtm3', 'view1' and 'view3'"
			echo ""
			echo -e "\e[1m-w <number>\e[0m"
			echo -e "\e[1m--workers <number>\e[0m"
			echo "     How many workers (cores) do we want to work"
			echo "     default: ${WORKERS}"
			echo ""
			echo -e "\e[1m-n <name>\e[0m"
			echo -e "\e[1m--name <name>\e[0m"
			echo "     Name for final output map."
			echo "     example: 'cz-prague'"
			echo "     default name will be same as map name from URL"
			exit 0
			;;
	esac
	shift # past argument or value
done

# Set other needed variables

MAP_NAME=$(basename ${MAP_URL} .osm.pbf)
# Map name can now end with -latest - strip it out
MAP_NAME="${MAP_NAME%-latest}"

# When no output map name was given as parameter
if [ -z $MAP_NAME_OUT ]; then
	MAP_NAME_OUT=$MAP_NAME
fi

MAP_NAME_TMP="${DIR_TMP}/${MAP_NAME}.osm.pbf"
MAP_NAME_COMPLETE="${DIR_TMP}/${MAP_NAME}.complete.pbf"
MAP_NAME_MERGE="${DIR_TMP}/${MAP_NAME}.merge.pbf"
MAP_NAME_FINAL="${DIR_OUT}/${MAP_NAME_OUT}.map"

# If polygon file hasn't been attached by parameter
if [ ! -f $POLY_FILE ] || [ "x${POLY_FILE}" = "x" ]; then
	# I need to download my own polygon file
	POLY_URL="${MAP_URL%.osm.pbf}"
	# Poly URL can now end with -latest
	POLY_URL="${POLY_URL%-latest}.poly"
	POLY_FILE="${DIR_TMP}/"$(basename "${POLY_URL}")
fi

HEIGHT_FILE=""

LOG_FILE="${DIR_OUT}/${MAP_NAME_OUT}.log"

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

# Set JAVA heap if needed
if [ $SET_JAVA_HEAP -gt 0 ]; then
	linf "Setting JAVA heap to ${SET_JAVA_HEAP}G"
	export JAVACMD_OPTIONS=-Xmx${SET_JAVA_HEAP}G
else
	linf "Skipping set of JAVA heap..."
fi

# Download function
function download {
	local URL=$1
	local FILE=$2

	if [ "x${URL}" = "x" ] || [ "x${FILE}" = "x" ]; then
		lerr 'Not enough parameters for downloading! Nothing to do...'
		exit 1
	fi

	local cmd="wget -c ${URL} -O ${FILE}"

	linf "Downloading ${URL} to ${FILE}"
	logPrint "Downloading: ${cmd}"

	eval $cmd
	
	linf "Download ${URL} to ${FILE} done."
	logPrint "Download ${URL} to ${FILE} done."
}

# Process functions

# Download main map data from OSM
function downloadMap {
	local URL=$1
	local FILE=$2

	linf "Download map data..."

	if [ -z $URL ]; then
		lerr "Map URL not set! Nothing to do..."
		exit 1
	fi

	# Download desired file in the first way
	download "${URL}" "${FILE}"

	if [ "x${FILE}" == "x" ] || [ ! -e $FILE ]; then
		lerr "Can't download map data!"
		exit 1
	fi

	logPrint "Download of map data complete"
}

# Download file with borders polygon
function downloadPolygon {
	local URL=$1
	local FILE=$2

	if [ "x${FILE}" == "x" ] || [ -f $FILE ]; then
		linf "Polygon file already exists, skipping download"
		return 0
	fi
	
	linf "Download polygon file..."

	# If polygon URL is set
	if [ "x${URL}" != "x" ]; then
		# Download desired file if is set URL
		download "${URL}" "${FILE}"
	fi

	if [ ! -e $FILE ]; then
		lerr "Can't download polygon file!"
		exit 1
	fi

	logPrint "Download of polygon file complete"
}

# Download height data for given polygon of map
function downloadHeightData {
	local POLYGON=$1
	local NAME=$2

	linf "Download height data..."

	if [ "x${POLYGON}" == "x" ] || [ ! -f $POLYGON ]; then
		lerr "Can't get height data - missing polygon file!"
		exit 1
	fi
	if [ "x${NAME}" == "x" ]; then
		lerr "Can't get height data - not enough parameters!"
		exit 1
	fi

	local cmd="phyghtmap --polygon=${POLYGON} --output-prefix=${DIR_TMP}/${NAME} --source=${HEIGHT_FORMAT} --pbf --jobs=${WORKERS} --step=10 --line-cat=100,50 --no-zero-contour --start-node-id=20000000000 --start-way-id=10000000000 --write-timestamp --max-nodes-per-tile=0 --hgtdir=${DIR_TMP}/hgt"

	logPrint "Downloading height data: ${cmd}"

	eval $cmd

	logPrint "Download of height data complete"
}

# Complete map by given polygon - especially complete cross-border ways or clip submap
function completeMapByPolygon {
	local POLYGON=$1
	local MAP_IN=$2
	local MAP_OUT=$3

	linf "Complete map by given polygon..."

	if [ "x${POLYGON}" == "x" ] || [ ! -f $POLYGON ]; then
		lerr "Can't complete map - missing polygon file!"
		exit 1
	fi
	if [ "x${MAP_IN}" == "x" ] || [ "x${MAP_OUT}" == "x" ]; then
		lerr "Can't complete map - not enough parameters!"
		exit 1
	fi

	local cmd="osmconvert ${MAP_IN} -B=${POLYGON} --verbose --complete-ways --complete-multipolygons --complete-boundaries --out-pbf -o=${MAP_OUT}"

	logPrint "Completing map by polygon: ${cmd}"

	eval $cmd

	logPrint "Completing map by polygon complete"
}

# Merge map with its height data
function mergeMapAndHeight {
	local HEIGHT=$1
	local MAP_IN=$2
	local MAP_OUT=$3

	linf "Merge height data with actual map..."

	if [ "x${HEIGHT}" == "x" ] || [ ! -e $HEIGHT ]; then
		lerr "Can't merge height file with map - missing height file!"
		exit 1
	fi
	if [ "x${MAP_IN}" == "x" ] || [ "x${MAP_OUT}" == "x" ]; then
		lerr "Can't merge height file with map - not enough parameters!"
		exit 1
	fi

	local cmd="osmosis --read-pbf-fast file=${MAP_IN} workers=${WORKERS} --sort-0.6 --read-pbf-fast ${HEIGHT} workers=${WORKERS} --sort-0.6 --merge --write-pbf ${MAP_OUT}"

	logPrint "Merging height data with map: ${cmd}"

	eval $cmd

	logPrint "Merge height data complete"
}

# Generate output map and display what is defined in TAG_CONF_FILE
function generateFinalMap {
	local MAP_IN=$1
	local MAP_OUT=$2

	linf "Generating final map..."

	if [ "x${MAP_OUT}" == "x" ] || [ "x${MAP_IN}" == "x" ] || [ ! -e $MAP_IN ]; then
		lerr "Can't generate final map!"
		exit 1
	fi

	local cmd="osmosis --read-pbf-fast file=${MAP_IN} workers=${WORKERS} --buffer --sort --mapfile-writer file=${MAP_OUT} type=hd  tag-conf-file=${TAG_CONF_FILE}"

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
downloadMap "${MAP_URL}" "${MAP_NAME_TMP}"
# Download border file
downloadPolygon "${POLY_URL}" "${POLY_FILE}"
if [ $CONTOUR == 1 ]; then
	# Download height data for map
	downloadHeightData "${POLY_FILE}" "${MAP_NAME}"
	# Get height file
	HEIGHT_FILE=$(find $DIR_TMP -type f -name ${MAP_NAME}"_*.osm.pbf" -print)
	logPrint "Height file name: ${HEIGHT_FILE}"
	# Complete cross-border ways or clip submap from map
	completeMapByPolygon "${POLY_FILE}" "${MAP_NAME_TMP}" "${MAP_NAME_COMPLETE}"
	# Merge downloaded map and computed height data
	mergeMapAndHeight "${HEIGHT_FILE}" "${MAP_NAME_COMPLETE}" "${MAP_NAME_MERGE}"
else
	linf "Skipping contour processing..."
	logPrint "Skipping contour processing..."
	# Complete cross-border ways or clip submap from map
	completeMapByPolygon "${POLY_FILE}" "${MAP_NAME_TMP}" "${MAP_NAME_COMPLETE}"
	# set variable for generating final map
	MAP_NAME_MERGE=$MAP_NAME_COMPLETE
fi
# Generate output map with all data
generateFinalMap "${MAP_NAME_MERGE}" "${MAP_NAME_FINAL}"
# Clean generated stuff from HD
#cleanAfter

linf "Everything seems to be OK"

# And final logs and exit
TIME_END=$(date +%s.%N)
TIME_DIFF=$(echo "${TIME_END} - ${TIME_START}" | bc)

linf "Generating ${MAP_NAME_FINAL} took ${TIME_DIFF} sec."
logPrint "Generating ${MAP_NAME_FINAL} took ${TIME_DIFF} sec."
