#!/bin/bash

# DISCLAIMER : This script is provided without any warranty of any kind. Use at your own risk. 
# DISCLAIMER : Use this script only with media you possess.
# BACKUP : Make sure you have a backup of your files.
# This script converts flac to mp3
#
# Version 1.0 "Does the job"
# Version 1.1 "tag cleanup / echo cleanup"
#
# Prerequisites: 
# metaflac (flac)
# cpulimit
# lame
# ImageMagick
# ffmpeg
# id3

# gets the script dir and name 
# checks if the script is already running
pathsource="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pathsourcescriptname=$(basename $BASH_SOURCE) 

for pid in $(pidof -x "$pathsourcescriptname"); do
    if [ $pid != $$ ]; then
        echo "[$(date)] : $pathsourcescriptname : Process is already running with PID $pid"
        exit 1
    fi
done

pathinit=$pathsource/init.txt
if [ ! -f "$pathinit" ] ; then	
	echo "config file missing"
	exit 1
fi

# true  : make the script verbose to the console
# false : only writes the log file
switchhelp="true"

# variables
# variables are read from init.txt
pathflacsource=$(grep -m 1 "pathflacsource=" $pathinit | awk -F'=' '{print $2}')
pathmp3dest=$(grep -m 1 "pathmp3dest=" $pathinit | awk -F'=' '{print $2}')
pathbase="$pathsource/db/base.txt"
pathlog="$pathsource/log"
filelog="$pathlog/flac2mp3.txt"
pathtmp="$pathsource/tmp"
pathtmpdata="$pathsource/tmp/data"
filethumbnail=$(grep -m 1 "filethumbnail=" $pathinit | awk -F'=' '{print $2}') ; if [ -z "$filethumbnail" ] ; then filethumbnail="Folder.jpg" ; fi
coverlist="tmp-front.jpg;$(grep -m 1 "coverlist=" $pathinit | awk -F'=' '{print $2}')"
coverfolderlist=$(grep -m 1 "coverfolderlist=" $pathinit | awk -F'=' '{print $2}')
varmp3quality=$(grep -m 1 "mp3quality=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$varmp3quality" ] ; then varmp3quality=0 ; fi
valcpulimit=$(grep -m 1 "valcpulimit=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$valcpulimit" ] ; then valcpulimit=50 ; fi
picturesize=$(grep -m 1 "picturesize=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$picturesize" ] ; then picturesize=200 ; fi
waittime=$(grep -m 1 "waittime=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$waittime" ] ; then waittime=5 ; fi
#ffmpeg/avconv fork
converter=$(grep -m 1 "converter=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$converter" ] ; then converter="ffmpeg" ; fi
varvolume=$(grep -m 1 "volume=" $pathinit | awk -F'=' '{print $2}') ; if [ -z "$varvolume" ] ; then varvolume=0 ; fi
# note : pathexclus-X is read later in the script
# note : smbpattern-X is read later in the script

# function : checkprereq : checks if the prerequisites are available
checkprereq()
{
	varmetaflac=$(which metaflac)
	varcpulimit=$(which cpulimit)
	varlame=$(which lame)
	varconverter=$(which $converter)
	varid3=$(which id3)

	go=1
	#testing binaries
	if [ ! -f "$varmetaflac" ] ; then echo "metaflac missing" ; go=0 ; fi
	if [ ! -f "$varcpulimit" ] ; then echo "cpulimit missing" ; go=0; fi
	if [ ! -f "$varlame" ] ; then echo "lame missing" ; go=0; fi
	if [ ! -f "$varconverter" ] ; then echo "converter missing" ; go=0 ; fi
	if [ ! -f "$varid3" ] ; then echo "id3 missing" ; go=0 ; fi
	
	#testing directories
	if [ ! -d "$pathflacsource" ]; then echo "pathflacsource missing" ; go=0; fi
	if [ ! -d "$pathmp3dest" ]; then echo "pathmp3dest missing" ; go=0; fi

	if [ $go -eq 1 ]; then

		if [ ! -d "$pathlog" ]; then
			echo "creating folder : $pathlog"
			mkdir "$pathlog"	
		fi
		createfolder "$pathsource/db"
		createfolder "$pathtmp"
		createfolder "$pathtmpdata"

		return 0
		
	else
		echo "prerequisite missing"
		return 1
	fi
}

# function : writelog
writelog(){
	if [ $switchhelp = "true" ] ;then echo "$1" ;fi	
	echo "$1"  >> $filelog		
}

# function : checksizehuman : converts bytes to a human readable unit (mb / gb / tb) and returns the value
checksizehuman()
{
	local retval=$(echo $1 | awk '{ sum=$1 ; hum[1024**3]="Gb";hum[1024**2]="Mb";hum[1024]="Kb"; for (x=1024**3; x>=1024; x/=1024){ if (sum>=x) { printf "%.2f %s\n",sum/x,hum[x];break } }}' )
	echo $retval
}

# function : createfolder and logs it
createfolder(){
if [ ! -d "$1" ]; then
	writelog "creating folder : $1"
	mkdir "$1"
fi
}

# function : limitprocess : limits cpu consuption 
# $1 : process name to limit
limitprocess(){	
	if [ $valcpulimit -gt 0 ]; then
		cpulimit --exe $1 --limit $valcpulimit > /dev/null 2>&1 &
	fi
}

# function : purgeprocess : stops cpu consuption limit for the $1 variable
purgeprocess(){
	if [ $valcpulimit -gt 0 ]; then
		local id1cpulimit="dummy"
		
		while [ -n "$id1cpulimit" ]; do
			id1cpulimit=$(ps aux|grep "cpulimit --exe $1 --limit $valcpulimit" | grep -v grep |head -n 1 | awk '{print $2}')
			
			if [ -n "$id1cpulimit" ]; then 
				#writelog "id : $id1cpulimit"
				kill $id1cpulimit
				wait $id1cpulimit 2>/dev/null
			fi			
		done
	fi
}

# function : smbcompatibility : replace the windows incompatible characters in the filename 
smbcompatibility(){
		
	while read fs ; do 
		local tmpbasename=$(basename "$fs")
		local tmpdirname=$(dirname "$fs")
	
		writelog "smb compatibility conversion input : $fs"
		for i in {1..6} ; do
			
			local tmpsmbpattern=$(grep -m 1 "smbpattern-$i=" $pathinit | awk -F'=' '{print $2}')
			local tmpsmbreplace=$(grep -m 1 "smbreplace-$i=" $pathinit | awk -F'=' '{print $2}')
			if [ -n "$tmpsmbpattern" ] && [ -n "$tmpsmbreplace" ] ; then
				tmpsmbpattern="[$tmpsmbpattern]"
				tmpbasename="${tmpbasename//$tmpsmbpattern/$tmpsmbreplace}"
			fi
		done

		writelog "smb compatibility conversion output :  $tmpdirname/$tmpbasename"
		mv "$fs" "$tmpdirname/$tmpbasename"
		
	done < <(find "$1" -maxdepth 1 -type f -name "*[<>:\\|?*]*")
	
}

# function : findcover : searches for cover in folder $1 's subfolder based on variables 
# files   : coverlist 
# folders : coverfolderlist
findcover(){
	#echos are sent return
	foundclres="false"
	IFS=';' read -ra arcovlst <<< "$coverlist"
	for covlst in "${arcovlst[@]}"; do
			
		local clres=$(find "$1" -maxdepth 1 -type f -iname "$covlst"  | head -n1)		
		if [ -n "$clres" ]; then 
			foundclres="true"
			echo "$clres"
			break	
		fi
			
		if [ "$foundclres" = "false" ] && [ -n "$coverfolderlist" ] ; then
			IFS=';' read -ra arcovfldlst <<< "$coverfolderlist"
			for covfldlst in "${arcovfldlst[@]}"; do
				
				local clres=$(find "$1" -type d -iname "$covfldlst" -exec find {} -type f -iname "$covlst" \; | head -n1)		
				
				if [ -n "$clres" ]; then 
					foundclres="true"
					echo "$clres"
					break
				fi
			done
		fi
		
		if [ "$foundclres" = "false" ]; then 
			
			local clres=$(find "$1" -type f -iname "$covlst" | head -n1)		
			
			if [ -n "$clres" ]; then 
				foundclres="true"
				echo "$clres"
				break	
			fi
		fi			
	
	if [ "$foundclres" = "true" ]; then 
		break	
	fi
		
	done
} 


# function : extractcover : extract the first front cover if available
extractcover(){
	
	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "block*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/block"*
	fi
	
	metaflac "$1" --list --block-type=PICTURE > "$pathtmp/block.txt"
	valexit=$?
	
	if [ $valexit -eq 0 ]; then
		#creates a short list of pictures number
		grep "METADATA block #" "$pathtmp/block.txt" > "$pathtmp/block-2.txt"
		
		#iterates the pictures looking for a "type: 3 (Cover (front))"
		while IFS='' read -r varline || [[ -n "$varline" ]]; do
			varnumpicture=$(echo -n "${varline##*\#}")
			
			metaflac "$1" --list --block-number=$varnumpicture > "$pathtmp/block-3.txt"
			
			varcheck=$(grep "type: 3 (Cover (front))" "$pathtmp/block-3.txt")
			if [ -n "$varcheck" ]; then 
				typemime=$(grep "MIME type:" "$pathtmp/block-3.txt")
				typemime="${typemime##*"MIME type: "}"
				typemime=$(echo -n "$typemime")
				
				typew=$(grep "width:" "$pathtmp/block-3.txt")
				typew="${typew##*"width: "}"
				typew=$(echo -n "$typew")
							
				typeh=$(grep "height:" "$pathtmp/block-3.txt")
				typeh="${typeh##*"height: "}"
				typeh=$(echo -n "$typeh")
				writelog "extractcover : $typemime $typeh x $typew"
				
				case "$typemime" in
				"image/jpeg")			 
					metaflac --block-number=$varnumpicture --export-picture-to="$pathtmp/tmp-front.jpg" "$1"
					;;
				"image/png")				
					metaflac --block-number=$varnumpicture --export-picture-to="$pathtmp/tmp-front.png" "$1"
					convert "$pathtmp/tmp-front.png" -quality 95 "$pathtmp/tmp-front.jpg"
					;;
				*)
					writelog "extractcover : Unknown file type" 
					;;
				esac
				
				#keep the iteration ability, but no need to iterate as soon as one is found
				break
				
			fi
		done < "$pathtmp/block-2.txt"
	fi
}

# function : getpicture : iterates to find a cover file 
# is stopped after first success by a break
getpicture(){

	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "block*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/block"*
	fi
	local tmpinttype=0
	metaflac "$1" --list --block-type=PICTURE > "$pathtmp/block.txt"
	valexit=$?
	
	if [ $valexit -eq 0 ]; then
		#creates a short list of pictures number
		grep "METADATA block #" "$pathtmp/block.txt" > "$pathtmp/block-2.txt"
		
		#iterates the pictures looking for a "type: 3 (Cover (front))"
		while IFS='' read -r varline || [[ -n "$varline" ]]; do
			varnumpicture=$(echo -n "${varline##*\#}")
			
			metaflac "$1" --list --block-number=$varnumpicture > "$pathtmp/block-3.txt"
			
			varcheck=$(grep "type: 3 (Cover (front))" "$pathtmp/block-3.txt")
			if [ -n "$varcheck" ]; then 
				typemime=$(grep "MIME type:" "$pathtmp/block-3.txt")
				typemime="${typemime##*"MIME type: "}"
				typemime=$(echo -n "$typemime")
				
				typew=$(grep "width:" "$pathtmp/block-3.txt")
				typew="${typew##*"width: "}"
				typew=$(echo -n "$typew")
							
				typeh=$(grep "height:" "$pathtmp/block-3.txt")
				typeh="${typeh##*"height: "}"
				typeh=$(echo -n "$typeh")
				writelog "getpicture : $typemime $typeh x $typew"
				
				case "$typemime" in
				"image/jpeg")			 
					tmpinttype=1
					;;
				"image/png")				
					tmpinttype=2
					;;
				*)
					echo "Unknown file type"
					;;
				esac
				
				#keep the iteration ability, but no need to iterate as soon as one is found
				break
				
			fi
		done < "$pathtmp/block-2.txt"
	fi
	return $tmpinttype
}


# function : getmp3tag : gets flac tags
# $1 tag to get
getmp3tag(){
	if [ -f "$pathtmpdata/tmptrack3.txt" ]; then
		local retval=$(grep -i -m 1 "^$1" "$pathtmpdata/tmptrack3.txt" | awk -F'=' '{print $2}')
	fi
	echo $retval
}


resizepicturebasic(){

	if [ -f "$pathtmp/tmp-resize.jpg" ]; then rm "$pathtmp/tmp-resize.jpg" ; fi
	 
	local varsize
	local typew=$(convert "$1" -print "%w" /dev/null)
	local typeh=$(convert "$1" -print "%h" /dev/null)
	
	writelog "w : $typew  ::  h : $typeh"
	
	if [ -n "$typew" ] && [ -n "$typeh" ]; then

		if [ $typeh -gt $picturesize ] || [ $typew -gt $picturesize ]; then
			writelog "> $picturesize (h or w)"
			
			varsize="$picturesize$(echo -n "x")$picturesize"
			#convert will keep the shape even if a square surface is provided
			convert "$1" -resize $varsize "$pathtmp/tmp-resize.jpg"	
		else
			writelog "<= $picturesize (h and w)"
		fi	
	
	fi

}



# function : extracttags : gets flac tags store them to $pathtmpdata/tmptrack3.txt
extracttags(){

		if [ ! -f "$pathtmpdata/tmptrack1.txt" ]; then
			metaflac --export-tags-to="$pathtmpdata/tmptrack1.txt" "$1"
		fi
		
		local tagyear=$(grep -i -m 1 "^year" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		if [ -z "$tagyear" ]; then tagyear=$(echo $(echo $(grep -i -m 1 "^date" "$pathtmpdata/tmptrack1.txt") | awk -F'=' '{print $2}') | awk -F' ' '{print $1}') ; fi	
				
		local tagtitle=$(grep -i -m 1 "^title" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagartist=$(grep -i -m 1 "^artist" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagalbumartist=$(grep -i -m 1 "^ALBUMARTIST" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagalbum=$(grep -i -m 1 "^album" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagdate=$(grep -i -m 1 "^date" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')	
		local tagtrack=$(grep -i -m 1 "^TRACKNUMBER" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')	
		local tagtracktot=$(grep -i -m 1 "^TRACKTOTAL" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')	
		local tagdisc=$(grep -i -m 1 "^DISCNUMBER" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')	
		local tagdisctot=$(grep -i -m 1 "^DISCTOTAL" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local taggenre=$(grep -i -m 1 "^Genre" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagpub=$(grep -i -m 1 "^Label" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')
		local tagreleasedate=$(grep -i -m 1 "^RELEASE DATE" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}')

		#sometime multiline
		#note : ffmpeg 2.7.1 : single line with ; delimiter
		local tagComposer=$(grep -i "^Composer" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}' | tr '\n' ';' | sed 's/.$//')
		local tagTIT1=$(grep -i "^Style" "$pathtmpdata/tmptrack1.txt" | awk -F'=' '{print $2}' | tr '\n' ';' | sed 's/.$//')

		
		echo ";FFMETADATA1" > "$pathtmpdata/tmptrack3.txt"
		if [ -n "$tagTIT1" ]; then echo "TIT1=$tagTIT1" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagtitle" ]; then echo "title=$tagtitle" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagalbum" ]; then echo "album=$tagalbum" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagyear" ]; then echo "Year=$tagyear" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagpub" ]; then echo "TPUB=$tagpub" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagTMED" ]; then echo "TMED=$tagTMED" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$taggenre" ]; then echo "genre=$taggenre" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagtrack" ]; then echo "track=$tagtrack" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagdisc" ]; then echo "disc=$tagdisc" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagartist" ]; then echo "artist=$tagartist" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagalbumartist" ]; then echo "album_artist=$tagalbumartist" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagComposer" ]; then echo "composer=$tagComposer" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagdisctot" ]; then echo "DISCTOTAL=$tagdisctot" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagreleasedate" ]; then echo "Release date=$tagreleasedate" >> "$pathtmpdata/tmptrack3.txt" ; fi
		if [ -n "$tagtracktot" ]; then echo "TRACKTOTAL=$tagtracktot" >> "$pathtmpdata/tmptrack3.txt" ; fi
	
}


# function : flactomp3 : converts and adds tags
flactomp3()
{
	
		if [ $varvolume -eq 0 ]; then
			$converter -hide_banner -i "$1" "$pathtmpdata/tmptrack.wav" < /dev/null
		else
			writelog "volume changed to : $varvolume"
			$converter -hide_banner -i "$1" -filter:a volume=$varvolume "$pathtmpdata/tmptrack.wav" < /dev/null
		fi
		
		lame "$pathtmpdata/tmptrack.wav" -V $varmp3quality -q 0 "$pathtmpdata/tmptrack.mp3" --tt "$(getmp3tag "title")" --ta "$(getmp3tag "artist")" --tl "$(getmp3tag "album")" --tn "$(getmp3tag "track")" --tv "TIT1=$(getmp3tag "TIT1")"
		
		$converter -hide_banner -i "$pathtmpdata/tmptrack.mp3" -i "$pathtmpdata/tmptrack3.txt" -map_metadata 1 -c:a copy -id3v2_version 3 -write_id3v1 1 "$pathtmpdata/tmptrack2.mp3" < /dev/null
		
		if [ -f "$pathtmpdata/tmp-front.jpg" ]; then
			writelog "adding front picture"
			$converter -hide_banner -i "$pathtmpdata/tmptrack2.mp3" -i "$pathtmpdata/tmp-front.jpg" -y -c copy -id3v2_version 3 -write_id3v1 1 -map 0 -map 1 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (Front)" "$pathtmpdata/tmptrack3.mp3" < /dev/null
		else
			cp "$pathtmpdata/tmptrack2.mp3" "$pathtmpdata/tmptrack3.mp3"
		fi
	
		
		id3 -2 -wTSSE "encoder=V $varmp3quality encoding SLOW" "$pathtmpdata/tmptrack3.mp3"
		if [ -n "$(getmp3tag "year")"  ]; then  
			id3 -y "$(getmp3tag "year")" "$pathtmpdata/tmptrack3.mp3"
		fi
	
		sleep 1s
	
}


# function : processingcore : main switcher
processingcore(){
	writelog "processingcore ***********************************************************"	
	
	tmppicture=0
	origin=$1
	shortpathandfile=$2
	writelog "shortpathandfile: $shortpathandfile"
	
	filename=$(basename "$origin/$shortpathandfile")
	dirname=$(dirname "$origin/$shortpathandfile")
	
	shortpathanddir=${dirname#${origin}/}
	#when there is no subdirectories
	if [ "$dirname" = "$origin" ]; then 
		shortpathanddir=""
		shortpathanddirl=""
		shortpathanddirlr="/"
	else
		shortpathanddirl="/$shortpathanddir"
		shortpathanddirlr="/$shortpathanddir/"
	fi
	
	filenamenoextension=${filename%.*}

	done="false"
	if [ -f $pathbase ]; then
		
		fileinbase=$(grep -F -m 1 "$shortpathandfile" $pathbase)
		if [ ! -z "$fileinbase" ]; then 
			done="true" 
			writelog "already done"
		fi
		
	else
		writelog "database doesn't exist" 
	fi	

	if [ $done = "false" ]; then

		if [ -f "$origin/$shortpathandfile" ] ; then
			
			writelog "cleaning temp data file cache"
			if [ "$(echo "$(find "$pathtmpdata" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
				rm "$pathtmpdata/"*.*
			fi
			if [ -f "$pathtmp/tmp-*.jpg" ] ; then rm "$pathtmp/tmp-*.jpg" ; fi	
			
			sleep 1
			limitprocess metaflac
			limitprocess lame
			limitprocess "$converter"
			
			if [ -f "$origin/$shortpathandfile" ] ; then actualsize=$(wc -c <"$origin/$shortpathandfile") ; fi
			temps0=$actualsize
			writelog "Size 0s timestamp : Bytes : $actualsize  :: Readable : $(checksizehuman $actualsize)"
			sleep $waittime
	
			if [ -f "$origin/$shortpathandfile" ] ; then actualsize=$(wc -c <"$origin/$shortpathandfile") ; fi
			temps1=$actualsize
			writelog "Size $(echo -n $waittime)s timestamp : Bytes : $actualsize  :: Readable : $(checksizehuman $actualsize)"

			#file extracting
			if [ $temps0 -eq $temps1 ]; then

				if [ ! -d "$pathmp3dest$shortpathanddirl" ]; then
					mkdir -p "$pathmp3dest$shortpathanddirl"
				fi

				#embedded picture
				if [ -f "$origin/$shortpathandfile" ] ; then
					getpicture "$origin/$shortpathandfile"			
					tmppicture=$?
					if [ $tmppicture -ne 0 ]; then
						extractcover "$origin/$shortpathandfile"
						if [ -f "$pathtmp/tmp-front.jpg" ]; then
							mv "$pathtmp/tmp-front.jpg" "$pathtmpdata/tmp-front.jpg"
						fi		
					fi
				fi
				
				#picture search
				if [ ! -f "$pathtmpdata/tmp-front.jpg" ]; then
					filecover="$(findcover "$origin$shortpathanddirl")"
					if [ -n "$filecover" ]; then
						writelog "filecover:  $filecover"
						cp "$filecover"	"$pathtmpdata/tmp-front.jpg"
					fi
				fi
				
				#picture resize
				if [ -f "$pathtmpdata/tmp-front.jpg" ]; then
					resizepicturebasic "$pathtmpdata/tmp-front.jpg"
				fi
				if [ -f "$pathtmp/tmp-resize.jpg" ]; then
					rm "$pathtmpdata/tmp-front.jpg"
					mv "$pathtmp/tmp-resize.jpg" "$pathtmpdata/tmp-front.jpg"
				fi
				
				#compression
				extracttags "$origin/$shortpathandfile"	
				flactomp3 "$origin/$shortpathandfile"	
				if [ -f "$pathtmpdata/tmptrack3.mp3" ]; then
					if [ -f "$pathmp3dest$shortpathanddirlr$filenamenoextension.mp3" ]; then rm "$pathmp3dest$shortpathanddirlr$filenamenoextension.mp3" ; fi
					mv "$pathtmpdata/tmptrack3.mp3" "$pathmp3dest$shortpathanddirlr$filenamenoextension.mp3"
				fi
				
				#thumbnail
				if [ ! -f "$pathmp3dest$shortpathanddirlr$filethumbnail" ]; then
					if [ -f "$pathtmpdata/tmp-front.jpg" ]; then
						writelog "adding thumbnail"
						mv "$pathtmpdata/tmp-front.jpg" "$pathmp3dest$shortpathanddirlr$filethumbnail" 
					fi
				fi
				
				#smb compatibility
				if [ -n "$(echo $(grep -m 1 "smbpattern-1=" $pathinit) | awk -F'=' '{print $2}')" ] && [ -n "$$(echo $(grep -m 1 "smbreplace-1=" $pathinit) | awk -F'=' '{print $2}')" ] ; then	
					smbcompatibility "$pathmp3dest$shortpathanddirlr$filenamenoextension.mp3"
				fi
				
				#inventory
				if [ -f "$origin/$shortpathandfile" ]; then
					echo "$shortpathandfile">>$pathbase
				fi
			
				sleep 1
				purgeprocess metaflac
				purgeprocess lame
				purgeprocess "$converter"

			fi
		
		fi
	fi #$done=true
}

# function : fileprocessing : handles a text database to find the differencies between 2 runs
# main loop
fileprocessing()
{
	purgeprocess shnsplit 

	writelog "cleaning temp cache"
	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/"*.*
	fi
	
	writelog "searching source for files : $1"
	find "$1" -type f -name "*.flac" > "$pathtmp/listlocalflac.txt"

	writelog "path correction"

	awk -v var="$1/" '{gsub(var, "");print}' "$pathtmp/listlocalflac.txt" > "$pathtmp/listlocalflac-2.txt"

	if [ -f "$pathbase" ]; then
		writelog "database copy"
		cp -f "$pathbase" "$pathtmp/tmpbase.txt"
		writelog "empty lines removal"
		grep -a . "$pathtmp/tmpbase.txt" > "$pathtmp/tmpbase-2.txt"

		writelog "differencies spotting"
		grep -aFvf "$pathtmp/tmpbase-2.txt" "$pathtmp/listlocalflac-2.txt" > "$pathtmp/diff.txt"
	else
		writelog "no database found, every file is processed"
		cp "$pathtmp/listlocalflac-2.txt" "$pathtmp/diff.txt"
	fi

	# path exclusions handling
	writelog "exclusions handling"
	#note: increase array size for more exclusion
	#removes exclusions from the loop
	for i in {1..10} ; do
		el=$(echo $(grep -m 1 "pathexclus-$i=" $pathinit) | awk -F'=' '{print $2}')
		if [ -n "$el" ]; then
			writelog "exclusion : $el"
			grep -aEv "^$el" "$pathtmp/diff.txt" > "$pathtmp/diff-2.txt"
			cat "$pathtmp/diff-2.txt" > "$pathtmp/diff.txt"
		fi
	done

	nblines=$(wc -l "$pathtmp/diff.txt" | awk '{print $1}')

	if [ $nblines -gt 0 ]; then

		while IFS='' read -r line || [[ -n "$line" ]]; do
			f="$line"
			if [ -n "$f" ]; then
				if [ -f "$1/$f" ]; then
					processingcore "$1" "$f"
				fi
			fi

		done < "$pathtmp/diff.txt"	
		
	else
		writelog "no diff, nothing to do"
	fi
}


if checkprereq ; then
	writelog "=========== Begin: $(date +"%Y-%m-%d--%H-%M-%S")"

	fileprocessing "$pathflacsource"
	
	if [  -d "$pathtmp" ]; then
		writelog "cleaning temp cache"
		if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
			rm "$pathtmp/"*.*
		fi
	fi
	if [  -d "$pathtmpdata" ]; then
		writelog "cleaning temp data cache"
		if [ "$(echo "$(find "$pathtmpdata" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
			rm "$pathtmpdata/"*.*
		fi
	fi
	
	writelog "=========== End  : $(date +"%Y-%m-%d--%H-%M-%S")"
fi

