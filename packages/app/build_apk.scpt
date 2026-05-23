on run
    tell application "Terminal"
        activate
        do script "cd /Users/siddharthapothulapati/Projects/gativani-app && export PATH=$PATH:/Users/siddharthapothulapati/flutter/bin && flutter clean && flutter pub get && flutter build apk --debug && echo 'Build complete!' && sleep 10"
    end tell
end run
