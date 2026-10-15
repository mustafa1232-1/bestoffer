@echo off
set "args=%*"
"%ProgramFiles%\Google\Chrome\Application\chrome.exe" --use-fake-ui-for-media-stream --use-fake-device-for-media-stream --autoplay-policy=no-user-gesture-required %args:&=^&%
