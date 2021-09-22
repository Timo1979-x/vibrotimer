@ECHO OFF
"C:\avrstu4\AvrAssembler2\avrasm2.exe" -S "D:\work\schemes\_avr\vibrotimer\labels.tmp" -fI -W+ie -C V2 -o "D:\work\schemes\_avr\vibrotimer\vibrotimer.hex" -d "D:\work\schemes\_avr\vibrotimer\vibrotimer.obj" -e "D:\work\schemes\_avr\vibrotimer\vibrotimer.eep" -m "D:\work\schemes\_avr\vibrotimer\vibrotimer.map" "D:\work\schemes\_avr\vibrotimer\vibrotimer.asm"
