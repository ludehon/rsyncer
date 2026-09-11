on run arguments
    set mountPath to item 1 of arguments
    set diskFolder to POSIX file mountPath as alias
    set backgroundFile to POSIX file (mountPath & "/.background/installer.tiff") as alias
    tell application "Finder"
        set installerWindow to make new Finder window to diskFolder
        set current view of installerWindow to icon view
        set toolbar visible of installerWindow to false
        set statusbar visible of installerWindow to false
        set bounds of installerWindow to {160, 120, 800, 568}
        set viewOptions to icon view options of installerWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        set label position of viewOptions to bottom
        set shows item info of viewOptions to false
        set background picture of viewOptions to backgroundFile
        set position of item "Rsyncer.app" of diskFolder to {170, 245}
        set position of item "Applications" of diskFolder to {470, 245}
        update diskFolder without registering applications
        delay 2
        close installerWindow
    end tell
end run
