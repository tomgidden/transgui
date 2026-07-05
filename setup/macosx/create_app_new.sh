#!/bin/sh

set -x

prog_ver="$(cat ../../VERSION.txt)"
build="$(git rev-list --abbrev-commit --max-count=1 HEAD ../..)"
lazarus_ver="$(lazbuild -v)"
fpc_ver="$(fpc -i V | head -n 1)"
appname="Transmission Remote GUI"
dmg_dist_file="../../Release/transgui-$prog_ver.dmg"
dmgfolder=./Release
appfolder="$dmgfolder/$appname.app"

if [ -z "${CI-}" ]; then
  ./install_deps.sh
fi

mkdir -p ../../Release/
sed -i.bak "s/'Version %s'/'Version %s Build $build'#13#10'Compiled by: $fpc_ver, Lazarus v$lazarus_ver'/" ../../about.lfm

lazbuild -B ../../transgui.lpi --lazarusdir=/Library/Lazarus/ --compiler=/usr/local/bin/fpc --cpu=x86_64 --widgetset=cocoa

# lazbuild may place the binary at the project root or in the unit output
# dir depending on version, so check both.
for cand in ../../transgui ../../units/transgui; do
  if [ -e "$cand" ]; then
    exename="$cand"
    break
  fi
done

if [ -z "$exename" ] || ! [ -e "$exename" ]; then
  echo "built transgui binary not found"
  exit 1
fi
strip "$exename"

rm -rf "$appfolder"

echo "Creating $appfolder..."
mkdir -p "$appfolder/Contents/MacOS/lang"
mkdir -p "$appfolder/Contents/Resources"

mv "$exename" "$appfolder/Contents/MacOS"
cp ../../lang/transgui.* "$appfolder/Contents/MacOS/lang"

cp ../../history.txt "$dmgfolder"
cp ../../README.md "$dmgfolder"

cp PkgInfo "$appfolder/Contents"
cp transgui.icns "$appfolder/Contents/Resources"
sed -e "s/@prog_ver@/$prog_ver/" Info.plist > "$appfolder/Contents/Info.plist"

ln -s /Applications "$dmgfolder/Drag \"Transmission Remote GUI\" here!"

hdiutil create -ov -anyowners -volname "transgui-v$prog_ver" -format UDRW -srcfolder ./Release -fs HFS+ "tmp.dmg"

mount_device="$(hdiutil attach -readwrite -noautoopen "tmp.dmg" | awk 'NR==1{print$1}')"
mount_volume="$(mount | grep "$mount_device" | sed 's/^[^ ]* on //;s/ ([^)]*)$//')"
cp transgui.icns "$mount_volume/.VolumeIcon.icns"
SetFile -c icnC "$mount_volume/.VolumeIcon.icns"
SetFile -a C "$mount_volume"

hdiutil detach "$mount_device"
rm -f "$dmg_dist_file"
hdiutil convert tmp.dmg -format UDBZ -imagekey zlib-level=9 -o "$dmg_dist_file"

rm tmp.dmg
rm -rf "$dmgfolder"
mv ../../about.lfm.bak ../../about.lfm

if [ -z "${CI-}" ]; then
  open "$dmg_dist_file"
fi
